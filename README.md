# Docker Deployment Guide

This directory contains the Docker configuration for deploying the application with SSL support using Let's Encrypt certificates.

## Prerequisites

- Docker
- Docker Compose
- A domain name pointing to your server
- Port 80 and 443 available on your server

## Setup Instructions

1. Copy the environment file and configure it:
   ```bash
   cp .env.example .env
   ```
   Edit `.env` and set your domain name, email, and other configuration options.

2. Make the initialization script executable:
   ```bash
   chmod +x init-letsencrypt.sh
   ```

3. Run the initialization script to set up SSL certificates:
   ```bash
   ./init-letsencrypt.sh
   ```
   This script will:
   - Create necessary directories
   - Generate temporary SSL certificates
   - Start Nginx
   - Request Let's Encrypt certificates
   - Reload Nginx with the new certificates

4. Start the application:
   ```bash
   docker-compose up -d
   ```

## Testing

The initial setup uses Let's Encrypt's staging environment to avoid rate limits. Once you've confirmed everything works:

1. Set `STAGING=0` in your `.env` file
2. Run the initialization script again to get production certificates:
   ```bash
   ./init-letsencrypt.sh
   ```

## Certificate Renewal

Certificates will automatically attempt to renew when they're within 30 days of expiration. The Docker Compose configuration includes the necessary volume mounts and configurations for automatic renewal.

## Troubleshooting

1. Check container logs:
   ```bash
   docker-compose logs -f
   ```

2. Check Nginx configuration:
   ```bash
   docker-compose exec nginx nginx -t
   ```

3. If certificates aren't being issued:
   - Ensure your domain points to the server
   - Check that ports 80 and 443 are open
   - Verify the email address in .env is valid
   - Check the certbot logs:
     ```bash
     docker-compose logs certbot
     ``` 