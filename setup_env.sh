#!/bin/bash

# PhotoShare Environment Setup Script
# This script generates secure secrets and creates the .env file

set -e

DOMAIN="${DOMAIN:-clue.photoshare.me}"

echo "PhotoShare Environment Setup"
echo "============================"

# Prompt for admin password if not provided
if [[ -z "$ADMIN_PASSWORD" ]]; then
    echo -n "Enter admin password for PhotoShare: "
    read -s ADMIN_PASSWORD
    echo
fi

# Prompt for email if not provided
if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
    echo -n "Enter email for Let's Encrypt SSL certificates: "
    read LETSENCRYPT_EMAIL
fi

# Ask about staging vs production
echo -n "Use Let's Encrypt staging (recommended for testing)? [Y/n]: "
read -r STAGING_CHOICE
if [[ "$STAGING_CHOICE" =~ ^[Nn]$ ]]; then
    STAGING=0
else
    STAGING=1
fi

echo
echo "Generating secure secrets..."

# Check if generate_secrets.py exists
if [[ ! -f "generate_secrets.py" ]]; then
    echo "Error: generate_secrets.py not found in current directory"
    exit 1
fi

# Generate secrets using the script
SECRETS_OUTPUT=$(python3 generate_secrets.py "$ADMIN_PASSWORD")

# Extract individual secrets
FKEY=$(echo "$SECRETS_OUTPUT" | grep "^FKEY=" | cut -d'=' -f2-)
WTFKEY=$(echo "$SECRETS_OUTPUT" | grep "^WTFKEY=" | cut -d'=' -f2-)
PSHR=$(echo "$SECRETS_OUTPUT" | grep "^PSHR=" | cut -d'=' -f2-)

# Escape special characters for shell/Docker Compose
PSHR_ESCAPED=$(echo "$PSHR" | sed 's/\$/\$\$/g')

echo "Creating .env file..."
cat > .env << EOF
# Domain configuration
DOMAIN=${DOMAIN}

# Let's Encrypt email for SSL certificates
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}

# SSL staging (1 for testing, 0 for production)
STAGING=${STAGING}

# Flask configuration
FLASK_ENV=production

# PhotoShare auto-generated secrets (generated on $(date))
FKEY=${FKEY}
WTFKEY=${WTFKEY}
PSHR=${PSHR_ESCAPED}
EOF

echo "✓ Environment file created successfully!"
echo
echo "Configuration summary:"
echo "  Domain: ${DOMAIN}"
echo "  Email: ${LETSENCRYPT_EMAIL}"
echo "  SSL Staging: ${STAGING} ($([ "$STAGING" = "1" ] && echo "testing" || echo "production"))"
echo "  Secrets: Generated and secured"
echo
echo "You can now run: ./deploy.sh" 