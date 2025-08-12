#!/bin/bash

# PhotoShare Docker Compose Deployment Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
check_prerequisites() {
    local errors=0
    echo -e "${BLUE}Checking Prerequisites${NC}"
    echo "========================"
    
    # Check if we're in a git repository with the right structure
    if [[ ! -f "app.py" || ! -f "docker-compose.yml" || ! -f "Dockerfile" ]]; then
        echo -e "${RED}✗ Not in PhotoShare project directory${NC}"
        echo "  Missing required files: app.py, docker-compose.yml, or Dockerfile"
        ((errors++))
    else
        echo -e "${GREEN}✓ PhotoShare project files found${NC}"
    fi
    
    # Check for required scripts
    if [[ ! -f "scripts/init-letsencrypt.sh" || ! -f "scripts/setup_env.sh" || ! -f "scripts/generate_secrets.py" ]]; then
        echo -e "${RED}✗ Required scripts missing${NC}"
        echo "  Missing files in scripts/ directory"
        ((errors++))
    else
        echo -e "${GREEN}✓ Required scripts found${NC}"
    fi
    
    # Check for nginx configuration
    if [[ ! -f "nginx/nginx.conf" || ! -d "nginx/templates" ]]; then
        echo -e "${RED}✗ Nginx configuration missing${NC}"
        echo "  Missing nginx/nginx.conf or nginx/templates/"
        ((errors++))
    else
        echo -e "${GREEN}✓ Nginx configuration found${NC}"
    fi
    
    # Check for templates and static directories
    if [[ ! -d "templates" || ! -d "static" ]]; then
        echo -e "${RED}✗ Application directories missing${NC}"
        echo "  Missing templates/ or static/ directories"
        ((errors++))
    else
        echo -e "${GREEN}✓ Application directories found${NC}"
    fi
    
    return $errors
}

check_docker_setup() {
    local deployment_type=$1
    local remote_host=$2
    local remote_user=$3
    local remote_path=$4
    
    echo -e "${BLUE}Checking Docker Setup${NC}"
    echo "====================="
    
    if [[ "$deployment_type" == "local" ]]; then
        # Check local Docker installation
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}✗ Docker not found locally${NC}"
            echo "  Install Docker from: https://docs.docker.com/get-docker/"
            return 1
        fi
        
        if ! command -v docker-compose &> /dev/null; then
            echo -e "${RED}✗ Docker Compose not found locally${NC}"
            echo "  Install Docker Compose from: https://docs.docker.com/compose/install/"
            return 1
        fi
        
        # Check if Docker daemon is running
        if ! docker info &> /dev/null; then
            echo -e "${RED}✗ Docker daemon not running${NC}"
            echo "  Start Docker Desktop or run: sudo systemctl start docker"
            return 1
        fi
        
        echo -e "${GREEN}✓ Docker and Docker Compose ready locally${NC}"
        
    else
        # Test SSH connectivity first
        echo "Testing SSH connectivity to ${remote_host}..."
        if ! ssh -o ConnectTimeout=10 -o BatchMode=yes ${remote_user}@${remote_host} "echo 'SSH connection successful'" &> /dev/null; then
            echo -e "${RED}✗ Cannot connect to ${remote_host} via SSH${NC}"
            echo "  Please check:"
            echo "    - Server IP address is correct"
            echo "    - SSH key is configured"
            echo "    - Network connectivity"
            echo "    - Server is running and accessible"
            return 1
        fi
        echo -e "${GREEN}✓ SSH connection successful${NC}"
        
        # Check remote Docker installation
        if ! ssh -o ConnectTimeout=10 ${remote_user}@${remote_host} "command -v docker && command -v docker-compose" &> /dev/null; then
            echo -e "${RED}✗ Docker or Docker Compose not found on remote server${NC}"
            echo "  Install on remote server:"
            echo "    curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh"
            echo "    sudo usermod -aG docker ${remote_user}"
            return 1
        fi
        
        # Check if Docker daemon is running remotely
        if ! ssh -o ConnectTimeout=10 ${remote_user}@${remote_host} "docker info" &> /dev/null; then
            echo -e "${RED}✗ Docker daemon not running on remote server${NC}"
            echo "  Start Docker on remote server: sudo systemctl start docker"
            return 1
        fi
        
        echo -e "${GREEN}✓ Docker and Docker Compose ready on remote server${NC}"
    fi
    
    return 0
}

check_media_directory() {
    local deployment_type=$1
    local remote_host=$2
    local remote_user=$3
    
    echo -e "${BLUE}Checking Media Directory${NC}"
    echo "========================"
    
    local media_path="/mnt/photoshare/media"
    
    if [[ "$deployment_type" == "local" ]]; then
        if [[ ! -d "$media_path" ]]; then
            echo -e "${YELLOW}⚠ Media directory not found locally${NC}"
            echo "  Creating $media_path..."
            if sudo mkdir -p "$media_path" && sudo chown -R $USER:$USER /mnt/photoshare; then
                echo -e "${GREEN}✓ Media directory created${NC}"
            else
                echo -e "${RED}✗ Failed to create media directory${NC}"
                echo "  Run: sudo mkdir -p $media_path && sudo chown -R $USER:$USER /mnt/photoshare"
                return 1
            fi
        else
            echo -e "${GREEN}✓ Media directory exists locally${NC}"
        fi
        
        # Check if there are any media files
        if [[ -z "$(find "$media_path" -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.mp4" -o -name "*.mov" 2>/dev/null | head -1)" ]]; then
            echo -e "${YELLOW}⚠ No media files found in $media_path${NC}"
            echo "  Add photos/videos to folders under $media_path/"
        else
            echo -e "${GREEN}✓ Media files found${NC}"
        fi
        
    else
        # Check remote media directory
        if ! ssh -o ConnectTimeout=10 ${remote_user}@${remote_host} "test -d $media_path" &> /dev/null; then
            echo -e "${YELLOW}⚠ Media directory not found on remote server${NC}"
            echo "  Creating $media_path on remote server..."
            if ssh ${remote_user}@${remote_host} "sudo mkdir -p $media_path && sudo chown -R $remote_user:$remote_user /mnt/photoshare"; then
                echo -e "${GREEN}✓ Media directory created on remote server${NC}"
            else
                echo -e "${RED}✗ Failed to create media directory on remote server${NC}"
                echo "  Run on server: sudo mkdir -p $media_path && sudo chown -R $remote_user:$remote_user /mnt/photoshare"
                return 1
            fi
        else
            echo -e "${GREEN}✓ Media directory exists on remote server${NC}"
        fi
        
        # Check if there are any media files remotely
        if ! ssh ${remote_user}@${remote_host} "find $media_path -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.mp4' -o -name '*.mov' 2>/dev/null | head -1" | grep -q .; then
            echo -e "${YELLOW}⚠ No media files found in $media_path on remote server${NC}"
            echo "  Upload photos/videos to folders under $media_path/ on the server"
        else
            echo -e "${GREEN}✓ Media files found on remote server${NC}"
        fi
    fi
    
    return 0
}

check_ports() {
    local deployment_type=$1
    local remote_host=$2
    local remote_user=$3
    local remote_path=$4
    
    echo -e "${BLUE}Checking Port Availability${NC}"
    echo "=========================="
    
    local port_errors=0
    local docker_conflicts=false
    
    if [[ "$deployment_type" == "local" ]]; then
        # Check local ports and identify Docker containers
        local port80_used=false
        local port443_used=false
        local port80_docker=""
        local port443_docker=""
        
        # Check if ports are in use
        if netstat -tuln 2>/dev/null | grep -q ":80 " || \
           ss -tuln 2>/dev/null | grep -q ":80 " || \
           lsof -i :80 2>/dev/null | grep -q LISTEN; then
            port80_used=true
            # Check if it's a Docker container
            port80_docker=$(docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null | grep ":80->" | head -1 || echo "")
        fi
        
        if netstat -tuln 2>/dev/null | grep -q ":443 " || \
           ss -tuln 2>/dev/null | grep -q ":443 " || \
           lsof -i :443 2>/dev/null | grep -q LISTEN; then
            port443_used=true
            # Check if it's a Docker container
            port443_docker=$(docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null | grep ":443->" | head -1 || echo "")
        fi
        
        # Handle port 80 conflicts
        if $port80_used; then
            if [[ -n "$port80_docker" ]]; then
                echo -e "${YELLOW}⚠ Port 80 in use by Docker container${NC}"
                echo "  $port80_docker"
                docker_conflicts=true
            else
                echo -e "${RED}✗ Port 80 is already in use locally${NC}"
                echo "  Services using port 80:"
                lsof -i :80 2>/dev/null || netstat -tuln 2>/dev/null | grep ":80 " || echo "  Could not identify process"
                ((port_errors++))
            fi
        else
            echo -e "${GREEN}✓ Port 80 available locally${NC}"
        fi
        
        # Handle port 443 conflicts
        if $port443_used; then
            if [[ -n "$port443_docker" ]]; then
                echo -e "${YELLOW}⚠ Port 443 in use by Docker container${NC}"
                echo "  $port443_docker"
                docker_conflicts=true
            else
                echo -e "${RED}✗ Port 443 is already in use locally${NC}"
                echo "  Services using port 443:"
                lsof -i :443 2>/dev/null || netstat -tuln 2>/dev/null | grep ":443 " || echo "  Could not identify process"
                ((port_errors++))
            fi
        else
            echo -e "${GREEN}✓ Port 443 available locally${NC}"
        fi
        
    else
        # Check remote ports and identify Docker containers
        local port80_check=$(ssh ${remote_user}@${remote_host} "netstat -tuln 2>/dev/null | grep ':80 ' || ss -tuln 2>/dev/null | grep ':80 '" 2>/dev/null || echo "")
        local port443_check=$(ssh ${remote_user}@${remote_host} "netstat -tuln 2>/dev/null | grep ':443 ' || ss -tuln 2>/dev/null | grep ':443 '" 2>/dev/null || echo "")
        
        local port80_docker=""
        local port443_docker=""
        
        if [[ -n "$port80_check" ]]; then
            port80_docker=$(ssh ${remote_user}@${remote_host} "docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null | grep ':80->' | head -1" || echo "")
            if [[ -n "$port80_docker" ]]; then
                echo -e "${YELLOW}⚠ Port 80 in use by Docker container on remote server${NC}"
                echo "  $port80_docker"
                docker_conflicts=true
            else
                echo -e "${RED}✗ Port 80 is already in use on remote server${NC}"
                echo "  Services using port 80:"
                ssh ${remote_user}@${remote_host} "lsof -i :80 2>/dev/null || echo '  Could not identify process'"
                ((port_errors++))
            fi
        else
            echo -e "${GREEN}✓ Port 80 available on remote server${NC}"
        fi
        
        if [[ -n "$port443_check" ]]; then
            port443_docker=$(ssh ${remote_user}@${remote_host} "docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null | grep ':443->' | head -1" || echo "")
            if [[ -n "$port443_docker" ]]; then
                echo -e "${YELLOW}⚠ Port 443 in use by Docker container on remote server${NC}"
                echo "  $port443_docker"
                docker_conflicts=true
            else
                echo -e "${RED}✗ Port 443 is already in use on remote server${NC}"
                echo "  Services using port 443:"
                ssh ${remote_user}@${remote_host} "lsof -i :443 2>/dev/null || echo '  Could not identify process'"
                ((port_errors++))
            fi
        else
            echo -e "${GREEN}✓ Port 443 available on remote server${NC}"
        fi
    fi
    
    # Handle Docker container conflicts (likely previous PhotoShare deployment)
    if $docker_conflicts; then
        echo
        echo -e "${BLUE}Docker containers detected using required ports${NC}"
        echo "This is likely a previous PhotoShare deployment that needs to be cleaned up."
        echo
        echo -n "Clean up existing Docker containers and redeploy? [Y/n]: "
        read -r CLEANUP_DOCKER
        
        if [[ ! "$CLEANUP_DOCKER" =~ ^[Nn]$ ]]; then
            echo "Cleaning up existing Docker containers..."
            if [[ "$deployment_type" == "local" ]]; then
                # Stop current project containers
                docker-compose down --volumes --remove-orphans 2>/dev/null || true
                
                # Stop any PhotoShare-related containers (different project names)
                echo "Stopping all PhotoShare-related containers..."
                docker ps -q --filter "name=photoshare" | xargs -r docker stop 2>/dev/null || true
                docker ps -aq --filter "name=photoshare" | xargs -r docker rm 2>/dev/null || true
                
                # Also check for containers using ports 80/443 directly
                CONTAINERS_80=$(docker ps -q --filter "publish=80" 2>/dev/null || echo "")
                CONTAINERS_443=$(docker ps -q --filter "publish=443" 2>/dev/null || echo "")
                
                if [[ -n "$CONTAINERS_80" ]]; then
                    echo "Stopping containers using port 80..."
                    echo "$CONTAINERS_80" | xargs -r docker stop 2>/dev/null || true
                    echo "$CONTAINERS_80" | xargs -r docker rm 2>/dev/null || true
                fi
                
                if [[ -n "$CONTAINERS_443" ]]; then
                    echo "Stopping containers using port 443..."
                    echo "$CONTAINERS_443" | xargs -r docker stop 2>/dev/null || true
                    echo "$CONTAINERS_443" | xargs -r docker rm 2>/dev/null || true
                fi
                
                # Prune unused containers and networks
                docker container prune -f 2>/dev/null || true
                docker network prune -f 2>/dev/null || true
                echo "Cleaned up local Docker containers and networks"
            else
                # Stop current project containers
                ssh ${remote_user}@${remote_host} "cd ${remote_path} && docker-compose down --volumes --remove-orphans 2>/dev/null || true"
                
                # Stop any PhotoShare-related containers (different project names)
                echo "Stopping all PhotoShare-related containers on remote server..."
                ssh ${remote_user}@${remote_host} "
                    docker ps -q --filter 'name=photoshare' | xargs -r docker stop 2>/dev/null || true;
                    docker ps -aq --filter 'name=photoshare' | xargs -r docker rm 2>/dev/null || true;
                    
                    # Also check for containers using ports 80/443 directly
                    CONTAINERS_80=\$(docker ps -q --filter 'publish=80' 2>/dev/null || echo '');
                    CONTAINERS_443=\$(docker ps -q --filter 'publish=443' 2>/dev/null || echo '');
                    
                    if [[ -n \"\$CONTAINERS_80\" ]]; then
                        echo 'Stopping containers using port 80...';
                        echo \"\$CONTAINERS_80\" | xargs -r docker stop 2>/dev/null || true;
                        echo \"\$CONTAINERS_80\" | xargs -r docker rm 2>/dev/null || true;
                    fi;
                    
                    if [[ -n \"\$CONTAINERS_443\" ]]; then
                        echo 'Stopping containers using port 443...';
                        echo \"\$CONTAINERS_443\" | xargs -r docker stop 2>/dev/null || true;
                        echo \"\$CONTAINERS_443\" | xargs -r docker rm 2>/dev/null || true;
                    fi;
                    
                    # Prune unused containers and networks
                    docker container prune -f 2>/dev/null || true;
                    docker network prune -f 2>/dev/null || true;
                "
                echo "Cleaned up remote Docker containers and networks"
            fi
            echo -e "${GREEN}Docker cleanup completed. Continuing with deployment...${NC}"
            return 0
        else
            echo -e "${RED}Cannot proceed with existing containers using required ports.${NC}"
            echo "Please manually stop the containers or choose a different deployment configuration."
            return 1
        fi
    fi
    
    # Handle non-Docker service conflicts
    if [[ $port_errors -gt 0 ]]; then
        echo
        echo -e "${RED}Port conflicts detected with system services!${NC}"
        echo "You have several options:"
        echo "1. Stop the conflicting services (recommended)"
        echo "2. Change PhotoShare to use different ports in docker-compose.yml"
        echo "3. Continue anyway (deployment will likely fail)"
        echo -n "Stop conflicting services automatically? [y/N]: "
        read -r STOP_SERVICES
        
        if [[ "$STOP_SERVICES" =~ ^[Yy]$ ]]; then
            echo "Attempting to stop conflicting services..."
            if [[ "$deployment_type" == "local" ]]; then
                sudo systemctl stop apache2 2>/dev/null || true
                sudo systemctl stop nginx 2>/dev/null || true
                echo "Stopped local web services"
            else
                ssh ${remote_user}@${remote_host} "sudo systemctl stop apache2 2>/dev/null || true; sudo systemctl stop nginx 2>/dev/null || true"
                echo "Stopped remote web services"
            fi
            echo -e "${GREEN}Services stopped. Continuing with deployment...${NC}"
        else
            echo -n "Continue deployment anyway? [y/N]: "
            read -r CONTINUE_ANYWAY
            if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi
    
    return 0
}

check_disk_space() {
    local deployment_type=$1
    local remote_host=$2
    local remote_user=$3
    
    echo -e "${BLUE}Checking Disk Space${NC}"
    echo "==================="
    
    local min_space_gb=2
    
    if [[ "$deployment_type" == "local" ]]; then
        local available_space=$(df /mnt 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}' || echo "0")
        if [[ $available_space -lt $min_space_gb ]]; then
            echo -e "${YELLOW}⚠ Low disk space: ${available_space}GB available${NC}"
            echo "  Recommend at least ${min_space_gb}GB free space"
        else
            echo -e "${GREEN}✓ Sufficient disk space: ${available_space}GB available${NC}"
        fi
    else
        local available_space=$(ssh ${remote_user}@${remote_host} "df /mnt 2>/dev/null | awk 'NR==2 {print int(\$4/1024/1024)}' || echo '0'")
        if [[ $available_space -lt $min_space_gb ]]; then
            echo -e "${YELLOW}⚠ Low disk space on remote server: ${available_space}GB available${NC}"
            echo "  Recommend at least ${min_space_gb}GB free space"
        else
            echo -e "${GREEN}✓ Sufficient disk space on remote server: ${available_space}GB available${NC}"
        fi
    fi
    
    return 0
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if (( i > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

resolve_domain_to_ip() {
    local domain=$1
    # Try multiple methods to resolve domain to IP
    local ip
    ip=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | head -1)
    if [[ -z "$ip" ]]; then
        ip=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{ print $2 }' | head -1)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(dig +short "$domain" 2>/dev/null | head -1)
    fi
    echo "$ip"
}

reverse_resolve_ip() {
    local ip=$1
    # Try multiple methods to reverse resolve IP to domain
    local domain
    domain=$(nslookup "$ip" 2>/dev/null | awk '/name = / { print $4 }' | sed 's/\.$//' | head -1)
    if [[ -z "$domain" ]]; then
        domain=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//' | head -1)
    fi
    echo "$domain"
}

setup_autostart() {
    local deployment_type=$1
    local remote_host=$2
    local remote_user=$3
    local remote_path=$4
    
    echo -e "${BLUE}Auto-Start Configuration${NC}"
    echo "========================="
    echo "PhotoShare can be configured to start automatically on boot/reboot."
    echo ""
    echo -n "Enable auto-start on boot? [y/N]: "
    read -r ENABLE_AUTOSTART
    
    if [[ ! "$ENABLE_AUTOSTART" =~ ^[Yy]$ ]]; then
        echo "Skipping auto-start configuration."
        return 0
    fi
    
    local service_content='[Unit]
Description=PhotoShare Application
Requires=docker.service
After=docker.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=WORKING_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0
User=SERVICE_USER

[Install]
WantedBy=multi-user.target'
    
    if [[ "$deployment_type" == "local" ]]; then
        echo "Creating systemd service for local PhotoShare..."
        
        # Create service file
        local service_file="/etc/systemd/system/photoshare.service"
        local working_dir=$(pwd)
        local current_user=$(whoami)
        
        echo "$service_content" | \
            sed "s|WORKING_DIR|$working_dir|g" | \
            sed "s|SERVICE_USER|$current_user|g" | \
            sudo tee "$service_file" > /dev/null
        
        # Enable and start service
        sudo systemctl daemon-reload
        sudo systemctl enable photoshare.service
        
        echo -e "${GREEN}✓ PhotoShare service created and enabled${NC}"
        echo "  Service file: $service_file"
        echo "  Working directory: $working_dir"
        echo "  User: $current_user"
        echo ""
        echo "Service commands:"
        echo "  sudo systemctl start photoshare    # Start service"
        echo "  sudo systemctl stop photoshare     # Stop service"
        echo "  sudo systemctl status photoshare   # Check status"
        echo "  sudo systemctl disable photoshare  # Disable auto-start"
        
    else
        echo "Creating systemd service on remote server..."
        
        # Get remote user if not provided
        if [[ -z "$remote_user" ]]; then
            echo -n "Remote username: "
            read -r remote_user
        fi
        
        # Create service file on remote server
        ssh ${remote_user}@${remote_host} "
            sudo tee /etc/systemd/system/photoshare.service > /dev/null << 'EOF'
$service_content
EOF"
        
        # Update service file with correct paths
        ssh ${remote_user}@${remote_host} "
            sudo sed -i 's|WORKING_DIR|${remote_path}|g' /etc/systemd/system/photoshare.service
            sudo sed -i 's|SERVICE_USER|${remote_user}|g' /etc/systemd/system/photoshare.service
            sudo systemctl daemon-reload
            sudo systemctl enable photoshare.service
        "
        
        echo -e "${GREEN}✓ PhotoShare service created and enabled on remote server${NC}"
        echo "  Service file: /etc/systemd/system/photoshare.service"
        echo "  Working directory: $remote_path"
        echo "  User: $remote_user"
        echo ""
        echo "Remote service commands:"
        echo "  ssh ${remote_user}@${remote_host} 'sudo systemctl start photoshare'    # Start service"
        echo "  ssh ${remote_user}@${remote_host} 'sudo systemctl stop photoshare'     # Stop service"
        echo "  ssh ${remote_user}@${remote_host} 'sudo systemctl status photoshare'   # Check status"
        echo "  ssh ${remote_user}@${remote_host} 'sudo systemctl disable photoshare'  # Disable auto-start"
    fi
    
    echo ""
    echo "Note: The service will automatically start PhotoShare after Docker starts on boot."
    echo "If you want to test it now, reboot your server or run the start command above."
    
    return 0
}

prompt_for_deployment_config() {
    echo -e "${BLUE}PhotoShare Deployment Configuration${NC}"
    echo "======================================"
    
    # Ask for deployment type
    echo "Choose deployment type:"
    echo "1) Local (deploy on this machine)"
    echo "2) Remote (deploy via SSH to another server)"
    echo -n "Enter choice [1/2]: "
    read -r DEPLOY_TYPE
    
    if [[ "$DEPLOY_TYPE" == "1" ]]; then
        DEPLOYMENT_TYPE="local"
        REMOTE_HOST="localhost"
        REMOTE_USER="$USER"
        REMOTE_PATH="$(pwd)"
        echo "Selected: Local deployment"
    else
        DEPLOYMENT_TYPE="remote"
        echo "Selected: Remote deployment"
    fi
    
    # Get domain or IP
    while true; do
        if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
            echo -n "Enter your domain name or public IP for SSL certificate: "
        else
            echo -n "Enter your domain name or server IP: "
        fi
        read -r INPUT
        
        if validate_ip "$INPUT"; then
            # It's an IP address
            if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
                REMOTE_HOST="$INPUT"
            fi
            echo -e "${YELLOW}Attempting reverse DNS lookup for IP $INPUT...${NC}"
            REVERSE_DOMAIN=$(reverse_resolve_ip "$INPUT")
            if [[ -n "$REVERSE_DOMAIN" ]]; then
                echo -e "${GREEN}✓ Reverse DNS: $REVERSE_DOMAIN${NC}"
                echo -n "Use $REVERSE_DOMAIN as your domain? [Y/n]: "
                read -r USE_REVERSE
                if [[ "$USE_REVERSE" =~ ^[Nn]$ ]]; then
                    echo -n "Enter your domain name for SSL certificate: "
                    read -r DOMAIN
                else
                    DOMAIN="$REVERSE_DOMAIN"
                fi
            else
                echo -e "${YELLOW}⚠️  Could not resolve IP to domain name${NC}"
                echo -n "Enter your domain name for SSL certificate: "
                read -r DOMAIN
            fi
            break
        else
            # Assume it's a domain name
            DOMAIN="$INPUT"
            echo -e "${YELLOW}Resolving domain $INPUT...${NC}"
            RESOLVED_IP=$(resolve_domain_to_ip "$INPUT")
            if [[ -n "$RESOLVED_IP" ]]; then
                echo -e "${GREEN}✓ Domain resolves to: $RESOLVED_IP${NC}"
                if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
                    echo -n "Deploy to this IP address? [Y/n]: "
                    read -r USE_IP
                    if [[ "$USE_IP" =~ ^[Nn]$ ]]; then
                        echo -n "Enter the correct server IP: "
                        read -r REMOTE_HOST
                    else
                        REMOTE_HOST="$RESOLVED_IP"
                    fi
                fi
                break
            else
                echo -e "${RED}✗ Could not resolve domain name${NC}"
                echo "Please enter a valid domain name or IP address."
            fi
        fi
    done
    
    # Get SSH details only for remote deployment
    if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
        echo -n "SSH username [$USER]: "
        read -r INPUT
        REMOTE_USER="${INPUT:-$USER}"
        
        echo -n "Deployment path [/home/$REMOTE_USER/photoshare]: "
        read -r INPUT
        REMOTE_PATH="${INPUT:-/home/$REMOTE_USER/photoshare}"
    fi
}

check_existing_env() {
    if [[ -f ".env" ]]; then
        # Check if it's just the example file
        if grep -q "DOMAIN=yourdomain.com" .env 2>/dev/null; then
            return 1  # It's the example file
        fi
        
        # Check if it has real values
        if grep -q "DOMAIN=" .env && grep -q "PSHR=" .env 2>/dev/null; then
            echo -e "${GREEN}✓ Found existing .env configuration${NC}"
            echo -n "Use existing configuration? [Y/n]: "
            read -r USE_EXISTING
            if [[ ! "$USE_EXISTING" =~ ^[Nn]$ ]]; then
                return 0  # Use existing
            fi
        fi
    fi
    return 1  # Need to create new
}

create_env_config() {
    local skip_password=false
    local skip_email=false
    
    # Check if we should skip password/email prompts
    if [[ -f ".env" ]] && grep -q "PSHR=" .env 2>/dev/null; then
        echo -n "Keep existing login password? [Y/n]: "
        read -r KEEP_PASSWORD
        if [[ ! "$KEEP_PASSWORD" =~ ^[Nn]$ ]]; then
            skip_password=true
        fi
    fi
    
    if [[ -f ".env" ]] && grep -q "LETSENCRYPT_EMAIL=" .env 2>/dev/null; then
        echo -n "Keep existing email address? [Y/n]: "
        read -r KEEP_EMAIL
        if [[ ! "$KEEP_EMAIL" =~ ^[Nn]$ ]]; then
            skip_email=true
        fi
    fi
    
    # Set environment variables for setup script
    export DOMAIN="$DOMAIN"
    
    if ! $skip_email; then
        DEFAULT_EMAIL="admin@$DOMAIN"
        echo -n "Let's Encrypt email address [$DEFAULT_EMAIL]: "
        read -r INPUT
        export LETSENCRYPT_EMAIL="${INPUT:-$DEFAULT_EMAIL}"
    fi
    
    if ! $skip_password; then
        echo -n "PhotoShare login password: "
        read -s ADMIN_PASSWORD
        echo
        export ADMIN_PASSWORD
    fi
    
    # SSL Certificate Configuration
    echo
    echo -e "${BLUE}SSL Certificate Configuration${NC}"
    echo "=============================="
    echo "Let's Encrypt offers two environments:"
    echo "• STAGING: For testing, no rate limits, but shows 'Not Secure' in browsers"
    echo "• PRODUCTION: Real certificates, but has rate limits (5 per week per domain)"
    echo
    echo "RECOMMENDED: Use staging first to test deployment, then redeploy with production."
    echo
    export STAGING=1
    echo -n "Use Let's Encrypt STAGING certificates (recommended for first deploy)? [Y/n]: "
    read -r USE_STAGING
    if [[ "$USE_STAGING" =~ ^[Nn]$ ]]; then
        export STAGING=0
        echo -e "${YELLOW}Using PRODUCTION certificates. Make sure your deployment works first!${NC}"
    else
        echo -e "${GREEN}Using STAGING certificates. Redeploy with 'n' once everything works.${NC}"
    fi
    
    # Run setup script if needed
    if [[ -f "scripts/setup_env.sh" ]] && (! $skip_password || ! $skip_email); then
        echo -e "${YELLOW}Generating .env configuration...${NC}"
        ./scripts/setup_env.sh
    fi
}

# Main configuration flow
echo -e "${GREEN}PhotoShare Deployment Script${NC}"
echo "========================================="

# Run initial prerequisite checks
if ! check_prerequisites; then
    echo -e "${RED}Prerequisites check failed. Please fix the above issues before continuing.${NC}"
    exit 1
fi

if ! check_existing_env; then
    prompt_for_deployment_config
    create_env_config
else
    # Extract values from existing .env
    DOMAIN=$(grep "^DOMAIN=" .env | cut -d'=' -f2-)
    prompt_for_deployment_config
fi

echo
echo -e "${BLUE}Running Pre-Deployment Checks${NC}"
echo "=============================="

# Run comprehensive checks
check_docker_setup "$DEPLOYMENT_TYPE" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PATH"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Docker setup check failed. Please fix the above issues.${NC}"
    exit 1
fi

check_media_directory "$DEPLOYMENT_TYPE" "$REMOTE_HOST" "$REMOTE_USER"

check_ports "$DEPLOYMENT_TYPE" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PATH"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Port availability check failed. Deployment cancelled.${NC}"
    exit 1
fi

check_disk_space "$DEPLOYMENT_TYPE" "$REMOTE_HOST" "$REMOTE_USER"

echo
echo -e "${GREEN}All pre-deployment checks completed!${NC}"
echo -n "Continue with deployment? [Y/n]: "
read -r CONTINUE_DEPLOY
if [[ "$CONTINUE_DEPLOY" =~ ^[Nn]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo
if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
    echo -e "${GREEN}Starting local deployment...${NC}"
else
    echo -e "${GREEN}Starting deployment to $REMOTE_HOST...${NC}"
fi

if [[ "$DEPLOYMENT_TYPE" == "remote" ]]; then
    # SSH connectivity is already verified in check_docker_setup
    # No need to test again here

    # Create remote directory
    echo -e "${YELLOW}Creating remote directory...${NC}"
    ssh ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_PATH}"

    # Copy files to remote server (excluding .DS_Store and other macOS files)
    echo -e "${YELLOW}Copying files to remote server...${NC}"
    rsync -avz --exclude '.git' --exclude '__pycache__' --exclude '*.pyc' --exclude 'node_modules' \
        --exclude '.DS_Store' --exclude '._*' --exclude '.Spotlight-V100' --exclude '.Trashes' \
        ./ ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/
fi

# Check if Docker is installed
echo -e "${YELLOW}Checking Docker installation...${NC}"
if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
    if ! docker --version && docker-compose --version; then
        echo -e "${RED}Docker or docker-compose not found locally!${NC}"
        echo "Please install Docker and Docker Compose:"
        echo "  Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
else
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
        echo ""
        echo "Then log out and back in for group changes to take effect."
        exit 1
    fi
fi

# Deploy the application
echo -e "${YELLOW}Deploying application...${NC}"
if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
    # Local deployment
    chmod +x scripts/init-letsencrypt.sh
    echo 'Stopping and cleaning up old containers...'
    docker-compose down --volumes --remove-orphans 2>/dev/null || true
    docker system prune -f
    docker image prune -f
    echo 'Building fresh containers...'
    docker-compose build --no-cache webapp
    echo 'Starting fresh deployment...'
    ./scripts/init-letsencrypt.sh
else
    # Remote deployment
    ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_PATH} && chmod +x scripts/init-letsencrypt.sh && \
        echo 'Stopping and cleaning up old containers...' && \
        docker-compose down --volumes --remove-orphans && \
        docker system prune -f && \
        docker image prune -f && \
        echo 'Building fresh containers...' && \
        docker-compose build --no-cache webapp && \
        echo 'Starting fresh deployment...' && \
        ./scripts/init-letsencrypt.sh"
fi

# Check if deployment was successful
echo -e "${YELLOW}Checking deployment status...${NC}"
if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
    if docker-compose ps; then
        echo -e "${GREEN}Local deployment completed successfully!${NC}"
        echo ""
        echo "Your application should now be accessible at:"
        echo "  http://localhost"
        if [[ "$DOMAIN" != "localhost" ]]; then
            echo "  https://$DOMAIN"
        fi
        echo ""
        echo "To check logs:"
        echo "  docker-compose logs -f"
        echo ""
        echo "To stop the application:"
        echo "  docker-compose down"
    else
        echo -e "${RED}Local deployment failed!${NC}"
        echo "Check the logs with:"
        echo "  docker-compose logs"
        exit 1
    fi
else
    if ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_PATH} && docker-compose ps"; then
        echo -e "${GREEN}Remote deployment completed successfully!${NC}"
        echo ""
        echo "Your application should now be accessible at:"
        echo "  http://${REMOTE_HOST}"
        if [[ "$DOMAIN" != "$REMOTE_HOST" ]]; then
            echo "  https://$DOMAIN"
        fi
        echo ""
        echo "To check logs:"
        echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker-compose logs -f'"
        echo ""
        echo "To stop the application:"
        echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker-compose down'"
    else
        echo -e "${RED}Remote deployment failed!${NC}"
        echo "Check the logs with:"
        echo "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_PATH} && docker-compose logs'"
        exit 1
    fi
fi

# Run post-deployment health checks
echo
echo -e "${BLUE}Running Post-Deployment Health Checks${NC}"
echo "======================================"

validate_deployment() {
    local deployment_type=$1
    local domain=$2
    local remote_host=$3
    local remote_user=$4
    local remote_path=$5
    
    local base_url
    local check_cmd_prefix=""
    
    if [[ "$deployment_type" == "remote" ]]; then
        if [[ "$domain" != "$remote_host" ]]; then
            base_url="https://$domain"
        else
            base_url="https://$remote_host"
        fi
        check_cmd_prefix="ssh ${remote_user}@${remote_host}"
    else
        if [[ -n "$domain" && "$domain" != "localhost" ]]; then
            base_url="https://$domain"
        else
            base_url="https://localhost"
        fi
    fi
    
    local health_errors=0
    
    # Check Docker containers are running
    echo -n "✓ Checking Docker containers... "
    if [[ "$deployment_type" == "remote" ]]; then
        local containers_running=$(ssh ${remote_user}@${remote_host} "cd ${remote_path} && docker-compose ps --services --filter 'status=running'" 2>/dev/null | wc -l)
    else
        local containers_running=$(docker-compose ps --services --filter 'status=running' 2>/dev/null | wc -l)
    fi
    
    if [[ $containers_running -ge 2 ]]; then
        echo -e "${GREEN}PASS${NC} ($containers_running containers running)"
    else
        echo -e "${RED}FAIL${NC} (only $containers_running containers running)"
        ((health_errors++))
    fi
    
    # Check HTTP response
    echo -n "✓ Checking HTTP connectivity... "
    if timeout 10 curl -s -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -o /dev/null -w "%{http_code}" "http://localhost" 2>/dev/null | grep -q "200\|302\|301"; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC} (HTTP not responding)"
        ((health_errors++))
    fi
    
    # Check HTTPS response (allow self-signed certs for staging)
    echo -n "✓ Checking HTTPS connectivity... "
    local https_response=$(timeout 10 curl -s -k -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -o /dev/null -w "%{http_code}" "$base_url" 2>/dev/null || echo "000")
    if [[ "$https_response" =~ ^(200|302|301)$ ]]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${YELLOW}WARN${NC} (HTTPS returned $https_response - may need time for SSL setup)"
    fi
    

    
    # Check media directory accessibility
    echo -n "✓ Checking media directory... "
    if [[ "$deployment_type" == "remote" ]]; then
        local media_accessible=$(ssh ${remote_user}@${remote_host} "test -d /mnt/photoshare/media && echo 'yes' || echo 'no'")
    else
        local media_accessible=$(test -d /mnt/photoshare/media && echo 'yes' || echo 'no')
    fi
    
    if [[ "$media_accessible" == "yes" ]]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC} (/mnt/photoshare/media not accessible)"
        ((health_errors++))
    fi
    
    # Check SSL certificate (if production)
    if [[ "$STAGING" == "0" ]]; then
        echo -n "✓ Checking SSL certificate... "
        local ssl_info=$(timeout 10 openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || echo "")
        if echo "$ssl_info" | grep -q "Let's Encrypt"; then
            echo -e "${GREEN}PASS${NC} (Let's Encrypt certificate)"
        else
            echo -e "${YELLOW}WARN${NC} (SSL certificate may still be initializing)"
        fi
    fi
    
    echo
    if [[ $health_errors -eq 0 ]]; then
        echo -e "${GREEN}🎉 All health checks passed! PhotoShare is ready to use.${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  $health_errors health check(s) failed. PhotoShare may need a few minutes to fully initialize.${NC}"
        echo "If issues persist, check the logs:"
        if [[ "$deployment_type" == "remote" ]]; then
            echo "  ssh ${remote_user}@${remote_host} 'cd ${remote_path} && docker-compose logs'"
        else
            echo "  docker-compose logs"
        fi
        return 1
    fi
}

validate_deployment "$DEPLOYMENT_TYPE" "$DOMAIN" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PATH"

# Optional auto-start configuration
setup_autostart "$DEPLOYMENT_TYPE" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PATH" 