#!/bin/bash

# PhotoShare Docker Compose Deployment Script
set -e

# Configuration
REMOTE_HOST="172.190.187.223"
REMOTE_USER="j"
REMOTE_PATH="/home/j/photoshare-deploy"
DOMAIN="clue.photoshare.me"

# Check if generate_secrets.py exists
if [[ ! -f "generate_secrets.py" ]]; then
    echo "Error: generate_secrets.py not found. Please ensure it exists in the project directory."
    exit 1
fi

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

echo "Generating secrets..."
# Generate secrets using the script
SECRETS_OUTPUT=$(python3 generate_secrets.py "$ADMIN_PASSWORD")

# Extract individual secrets
FKEY=$(echo "$SECRETS_OUTPUT" | grep "^FKEY=" | cut -d'=' -f2-)
WTFKEY=$(echo "$SECRETS_OUTPUT" | grep "^WTFKEY=" | cut -d'=' -f2-)
PSHR=$(echo "$SECRETS_OUTPUT" | grep "^PSHR=" | cut -d'=' -f2-)

# Escape special characters for shell
PSHR_ESCAPED=$(echo "$PSHR" | sed 's/\$/\$\$/g')

echo "Creating .env file with generated secrets..."
cat > .env << EOF
# Domain configuration
DOMAIN=${DOMAIN}

# Let's Encrypt email for SSL certificates
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}

# SSL staging (1 for testing, 0 for production)
STAGING=1

# Flask configuration
FLASK_ENV=production

# PhotoShare auto-generated secrets
FKEY=${FKEY}
WTFKEY=${WTFKEY}
PSHR=${PSHR_ESCAPED}
EOF

echo "✓ Secrets generated and .env file created"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}PhotoShare Deployment Script${NC}"
echo "========================================="

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please copy env.example to .env and configure it:"
    echo "  cp env.example .env"
    echo "  nano .env"
    exit 1
fi

# Verify we can connect to the server
echo -e "${YELLOW}Testing connection to server...${NC}"
if ! ssh -o ConnectTimeout=10 ${REMOTE_USER}@${REMOTE_HOST} "echo 'Connection successful'"; then
    echo -e "${RED}Error: Cannot connect to ${REMOTE_HOST}${NC}"
    echo "Please check:"
    echo "  - Server IP address"
    echo "  - SSH key authentication"
    echo "  - Network connectivity"
    exit 1
fi

# Create remote directory
echo -e "${YELLOW}Creating remote directory...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_PATH}"

# Copy files to remote server
echo -e "${YELLOW}Copying files to remote server...${NC}"
rsync -avz --exclude '.git' --exclude '__pycache__' --exclude '*.pyc' --exclude 'node_modules' \
    ./ ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/

# Check if Docker is installed on remote server
echo -e "${YELLOW}Checking Docker installation...${NC}"
if ! ssh ${REMOTE_USER}@${REMOTE_HOST} "docker --version && docker-compose --version"; then
    echo -e "${RED}Docker or docker-compose not found on remote server!${NC}"
    echo "Please install Docker and Docker Compose on the server:"
    echo "  # Install Docker"
    echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
    echo "  sh get-docker.sh"
    echo "  sudo usermod -aG docker ${REMOTE_USER}"
    echo ""
    echo "  # Install Docker Compose"
    echo "  sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
    echo "  sudo chmod +x /usr/local/bin/docker-compose"
    exit 1
fi

# Deploy on remote server
echo -e "${YELLOW}Deploying application on remote server...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_PATH} && chmod +x init-letsencrypt.sh && ./init-letsencrypt.sh"

# Check if deployment was successful
echo -e "${YELLOW}Checking deployment status...${NC}"
if ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_PATH} && docker-compose ps"; then
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo ""
    echo "Your application should now be accessible at:"
    echo "  http://${REMOTE_HOST}"
    echo ""
    echo "To check logs:"
    echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker-compose logs -f'"
    echo ""
    echo "To stop the application:"
    echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker-compose down'"
else
    echo -e "${RED}Deployment failed!${NC}"
    echo "Check the logs with:"
    echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker-compose logs'"
    exit 1
fi 