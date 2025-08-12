# PhotoShare

A simple, secure Flask-based photo sharing application with Docker deployment and SSL support.

## Features

- **Secure Authentication**: Password-protected access to your photos
- **Media Gallery**: Organized photo and video browsing with pagination
- **Docker Deployment**: One-command deployment with SSL certificates
- **Responsive Design**: Works on desktop and mobile devices
- **Download Support**: Direct download links for media files
- **Flexible Storage**: Host media on external drives, network storage, or cloud mounts

## Why This Storage Structure?

PhotoShare uses a flexible media directory structure (`/mnt/photoshare/media/`) that offers significant advantages:

### **External Drive Support**
- **Easy mounting**: Mount external drives directly to `/mnt/photoshare/media/`
- **Hot-swappable storage**: Swap drives without touching your application
- **Large capacity**: Use high-capacity drives without filling your main system storage

### **Cloud & Network Storage**
- **Cloud mounts**: Mount cloud storage (Google Drive, Dropbox, S3) via FUSE
- **NAS integration**: Connect to Network Attached Storage seamlessly
- **Remote storage**: Keep media separate from application server

### **Local Flexibility**
- **Separate partitions**: Keep photos on dedicated storage partitions
- **RAID arrays**: Use RAID configurations for redundancy
- **SSD + HDD**: App on fast SSD, media on large HDD

### **Easy Migration & Backup**
- **Simple backups**: Backup just the media directory independently
- **Server migration**: Move application without touching media files
- **Storage upgrades**: Upgrade storage capacity without rebuilding

This architecture means your PhotoShare application stays lightweight while your media storage can grow and adapt to your needs.

## Server Setup

Before running the deployment script, you need to create the media directory structure on your server where your photos and videos will be stored.

### 1. Connect to your server (if using the remote option)

```bash
ssh your-username@your-server-ip
```

### 2. Create the media directory structure

PhotoShare expects your media files to be organized in folders under `/mnt/photoshare/media/`. Create this structure:

```bash
sudo mkdir -p /mnt/photoshare/media
sudo chown -R $USER:$USER /mnt/photoshare
```

### 3. Upload your photos and videos

Organize your media files into folders within `/mnt/photoshare/media/` however you like. For example:

```
/mnt/photoshare/media/
├── Family-Photos/
│   ├── birthday-2024.jpg
│   ├── vacation.mp4
│   └── wedding.png
├── Travel/
│   ├── paris-trip.jpg
│   ├── tokyo-street.jpg
│   └── mountain-hike.mov
└── Events/
    ├── graduation.jpg
    └── concert.mp4
```

You can upload files using any method you prefer:
- **SCP**: `scp -r ./my-photos/ user@server:/mnt/photoshare/media/Family-Photos/`
- **SFTP**: Use an SFTP client like FileZilla
- **rsync**: `rsync -avz ./photos/ user@server:/mnt/photoshare/media/Travel/`

### 4. Set proper permissions

After uploading, ensure the web server can read your media files:

```bash
find /mnt/photoshare/media -type f -exec chmod 644 {} \;
find /mnt/photoshare/media -type d -exec chmod 755 {} \;
```

## Deployment Options

PhotoShare supports both local and remote deployment. Choose the option that fits your setup.

### Local Deployment

Deploy PhotoShare directly on your current machine:

1. **Set up media files locally**:
   ```bash
   sudo mkdir -p /mnt/photoshare/media
   sudo chown -R $USER:$USER /mnt/photoshare
   # Copy your photos to /mnt/photoshare/media/Your-Folder-Name/
   ```

2. **Clone and deploy**:
   ```bash
   git clone <your-repo-url>
   cd photoshare
   ./deploy.sh
   ```

3. **Choose option 1** (Local deployment) when prompted

### Remote Deployment

Deploy PhotoShare to a remote server via SSH:

1. **Set up media files on the remote server** (see Server Setup section above)

2. **Clone and deploy**:
   ```bash
   git clone <your-repo-url>
   cd photoshare
   ./deploy.sh
   ```

3. **Choose option 2** (Remote deployment) when prompted

## Interactive Configuration

The deployment script will prompt you for:
- **Deployment type** (local or remote)
- **Domain name or server IP** (with DNS validation)
- **SSH username and deployment path** (remote deployments only)
- **Login password and email** (with smart defaults)
- **SSL certificate preferences**

The script automatically:
- Validates DNS resolution both ways (domain and IP)
- Detects existing configuration and offers to reuse it
- Generates secure secrets and environment files
- Deploys with Docker and SSL certificates
- Starts the PhotoShare service
- Optionally configures auto-start on boot

No manual configuration files required - just run the script and follow the prompts.

## Requirements

- Docker and Docker Compose on your server
- A domain name pointing to your server
- Ports 80 and 443 open

### Installing Docker and Docker Compose

#### Ubuntu/Debian
```bash
# Update package index
sudo apt update

# Install prerequisites
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add your user to docker group
sudo usermod -aG docker $USER

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Log out and back in, then test
docker --version
docker compose version
```

#### CentOS/RHEL/Fedora
```bash
# Install Docker
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in, then test
docker --version
docker compose version
```

### Verify Installation
After installation, verify Docker is working:
```bash
docker --version
docker compose version
docker run hello-world
```

## Project Structure

```
photoshare/
├── app.py                  # Main Flask application
├── config.py              # Application configuration  
├── requirements.txt        # Python dependencies
├── Dockerfile             # Container definition
├── docker-compose.yml     # Container orchestration
├── .env.example           # Environment template
├── deploy.sh              # One-command deployment script
├── scripts/               # Utility scripts
│   ├── setup_env.sh      # Environment setup
│   ├── init-letsencrypt.sh # SSL certificate setup
│   ├── generate_secrets.py # Secret generation
│   └── test_deployment.sh # Deployment testing suite
├── nginx/                # Web server configuration
├── static/               # CSS, images, favicon
└── templates/            # HTML templates
```

## Configuration

The application uses environment variables for configuration:

- `DOMAIN`: Your domain name
- `LETSENCRYPT_EMAIL`: Email for SSL certificates  
- `STAGING`: Use Let's Encrypt staging (1) or production (0)
- `FLASK_ENV`: Flask environment (production)
- Auto-generated secrets: `FKEY`, `WTFKEY`, `PSHR`

## Media Files

Place your photos and videos in `/mnt/photoshare/media/` on your server, organized in folders:

```
/mnt/photoshare/media/
├── Vacation-2024/
│   ├── beach.jpg
│   └── sunset.mp4
└── Family-Photos/
    ├── birthday.jpg
    └── wedding.mov
```

## Testing & Validation

PhotoShare includes comprehensive testing to ensure reliable deployments:

### Automatic Health Checks

The deployment script automatically runs health checks after deployment:

```bash
./deploy.sh
# ... deployment process ...

Running Post-Deployment Health Checks
======================================
✓ Checking Docker containers... PASS (2 containers running)
✓ Checking HTTP connectivity... PASS
✓ Checking HTTPS connectivity... PASS

✓ Checking media directory... PASS
✓ Checking SSL certificate... PASS (Let's Encrypt certificate)

🎉 All health checks passed! PhotoShare is ready to use.
```

### Manual Testing

For comprehensive testing, use the included test suite:

```bash
# Test local deployment
./scripts/test_deployment.sh --local

# Test specific domain
./scripts/test_deployment.sh --domain photos.example.com

# Test remote deployment
./scripts/test_deployment.sh --remote 192.168.1.100
```

### Test Categories

The test suite covers six critical areas:

1. **Infrastructure Tests**
   - Docker daemon and containers
   - Media directory accessibility
   - Port availability (80/443)

2. **Application Tests**
   - Homepage loading
   - Static file serving (CSS, favicon)
   - Error page handling (404)

3. **Security Tests**
   - HTTP to HTTPS redirects
   - Protected endpoint access

4. **SSL/TLS Tests**
   - Certificate validity
   - Strong cipher usage
   - Security headers (HSTS)

5. **Performance Tests**
   - Homepage load times
   - Static file delivery speed

6. **Media Tests**
   - File accessibility
   - Directory listing functionality

### Continuous Testing

For production deployments, consider:

- **Scheduled testing**: Run `./scripts/test_deployment.sh` via cron
- **Monitoring integration**: Parse test output for alerts
- **Load testing**: Use tools like `ab` or `wrk` for traffic simulation
- **SSL monitoring**: Monitor certificate expiration dates

### Troubleshooting Failed Tests

If tests fail, check:

```bash
# Container status
docker compose ps

# Application logs
docker compose logs

# System resources
df -h && free -m

# Network connectivity
curl -v https://your-domain.com
```

## Auto-Start Configuration

PhotoShare can be configured to automatically start on server boot/reboot using systemd.

### During Deployment

The deployment script will prompt:
```
Auto-Start Configuration
=========================
PhotoShare can be configured to start automatically on boot/reboot.

Enable auto-start on boot? [y/N]: y
```

If you choose "yes", the script will:
- Create a systemd service file (`/etc/systemd/system/photoshare.service`)
- Enable the service to start on boot
- Configure proper dependencies (starts after Docker)

### Manual Service Management

Once configured, you can manage PhotoShare using standard systemd commands:

```bash
# Start PhotoShare
sudo systemctl start photoshare

# Stop PhotoShare
sudo systemctl stop photoshare

# Check status
sudo systemctl status photoshare

# View logs
sudo journalctl -u photoshare -f

# Disable auto-start (if needed)
sudo systemctl disable photoshare

# Re-enable auto-start
sudo systemctl enable photoshare
```

### For Remote Deployments

The service is created on the remote server automatically:
```bash
# Remote service management
ssh user@server 'sudo systemctl status photoshare'
ssh user@server 'sudo systemctl restart photoshare'
```

### Service Details

The systemd service:
- **Starts after**: Docker service is running
- **Working directory**: Your PhotoShare deployment path
- **User**: Your deployment user (not root)
- **Commands**: Uses `docker compose up -d` and `docker compose down`
- **Auto-restart**: Enabled on system boot

This ensures PhotoShare reliably starts after server reboots without manual intervention.

## License

MIT License - see individual files for details.