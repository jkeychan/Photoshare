#!/bin/bash

# Exit on error
set -e

# Load environment variables from .env
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | xargs)
fi

# Default values
domain=${DOMAIN:-localhost}
email=${LETSENCRYPT_EMAIL:-""}
staging=${STAGING:-1} # Set to 0 for production certificates

# Create required directories
mkdir -p nginx/conf.d
mkdir -p nginx/templates

# Create dummy certificates in the Docker volume where nginx expects them
echo "Creating dummy certificates..."
docker-compose run --rm --entrypoint sh certbot -c "
  mkdir -p /etc/letsencrypt/live/$domain && \
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout /etc/letsencrypt/live/$domain/privkey.pem \
    -out /etc/letsencrypt/live/$domain/fullchain.pem \
    -subj '/CN=localhost'"

echo "Starting nginx..."
docker-compose up --force-recreate -d nginx webapp

echo "Deleting dummy certificates..."
docker-compose run --rm --entrypoint sh certbot -c "
  rm -rf /etc/letsencrypt/live/$domain && \
  rm -rf /etc/letsencrypt/archive/$domain && \
  rm -rf /etc/letsencrypt/renewal/$domain.conf"

echo "Requesting Let's Encrypt certificates..."
staging_arg=""
if [ $staging != "0" ]; then
    staging_arg="--staging"
fi

domain_args="-d $domain"

# Join $domains to -d args
docker-compose run --rm certbot certonly \
    $staging_arg \
    --webroot --webroot-path=/var/www/html \
    $domain_args \
    --email $email \
    --rsa-key-size 4096 \
    --agree-tos \
    --force-renewal \
    --non-interactive

echo "Reloading nginx..."
docker-compose exec nginx nginx -s reload 