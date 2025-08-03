#!/bin/bash

# Configuration
SERVER_IP="172.190.187.223"
SERVER_USER="j"
REMOTE_DIR="/home/j/photoshare-deploy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

case "$1" in
    logs)
        echo -e "${YELLOW}Fetching application logs...${NC}"
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose logs -f"
        ;;
    status)
        echo -e "${YELLOW}Checking application status...${NC}"
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose ps"
        ;;
    restart)
        echo -e "${YELLOW}Restarting application...${NC}"
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose restart"
        ;;
    stop)
        echo -e "${YELLOW}Stopping application...${NC}"
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose down"
        ;;
    start)
        echo -e "${YELLOW}Starting application...${NC}"
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose up -d"
        ;;
    shell)
        echo -e "${YELLOW}Connecting to server shell...${NC}"
        ssh ${SERVER_USER}@${SERVER_IP}
        ;;
    update)
        echo -e "${YELLOW}Updating application code...${NC}"
        rsync -avz --exclude '.git' --exclude '__pycache__' --exclude '*.pyc' --exclude 'node_modules' \
            ./ ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose up -d --build"
        ;;
    ssl)
        echo -e "${YELLOW}Renewing SSL certificates...${NC}"
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose run --rm certbot renew"
        ssh ${SERVER_USER}@${SERVER_IP} "cd ${REMOTE_DIR} && docker-compose exec nginx nginx -s reload"
        ;;
    *)
        echo -e "${GREEN}PhotoShare Management Script${NC}"
        echo "========================================="
        echo "Usage: $0 {logs|status|restart|stop|start|shell|update|ssl}"
        echo ""
        echo "Commands:"
        echo "  logs     - View application logs"
        echo "  status   - Check container status"
        echo "  restart  - Restart all services"
        echo "  stop     - Stop all services"
        echo "  start    - Start all services"
        echo "  shell    - Connect to server shell"
        echo "  update   - Update code and rebuild"
        echo "  ssl      - Renew SSL certificates"
        exit 1
        ;;
esac 