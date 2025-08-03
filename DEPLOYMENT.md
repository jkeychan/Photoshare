# PhotoShare Docker Compose Deployment Guide

## Overview

This guide walks you through deploying PhotoShare using Docker Compose on a remote Azure server. The setup automatically generates secure secrets and handles SSL certificates via Let's Encrypt.

## Prerequisites

- Remote server running Linux (tested with Ubuntu)
- Docker and Docker Compose installed on the remote server
- SSH access to the remote server
- Domain name pointing to your server's IP address (required for SSL)

## Quick Start

1. **Configure Environment Variables**
   ```bash
   ./setup_env.sh
   ```
   This will prompt you for:
   - Admin password for PhotoShare login
   - Email address for Let's Encrypt SSL certificates
   - Whether to use staging (testing) or production SSL certificates

   The script automatically generates:
   - Flask secret key (FKEY)
   - CSRF secret key (WTFKEY) 
   - Secure password hash (PSHR)

2. **Deploy to Remote Server**
   ```bash
   ./deploy.sh
   ```

## Configure DNS (Important!)

**Before running the deployment**, ensure your domain's DNS A record points to your server:

1. Log into your domain registrar (GoDaddy, Namecheap, Cloudflare, etc.)
2. Navigate to DNS settings for `clue.photoshare.me`
3. Add/update an A record:
   - **Name**: `clue` (or `@` for root domain)
   - **Type**: `A`
   - **Value**: `172.190.187.223`
   - **TTL**: `300` (5 minutes)

DNS propagation can take 5-60 minutes. Verify with:
```bash
nslookup clue.photoshare.me
```

## Manual Environment Setup

If you prefer to set up the environment manually:

1. **Copy the example environment file:**
   ```bash
   cp env.example .env
   ```

2. **Edit `.env` with your values:**
   ```bash
   # Domain configuration
   DOMAIN=clue.photoshare.me
   LETSENCRYPT_EMAIL=your-email@example.com
   STAGING=1  # Use 0 for production SSL
   FLASK_ENV=production
   
   # Generate secrets (you can use the generate_secrets.py script)
   FKEY=<your-flask-secret-key>
   WTFKEY=<your-csrf-secret-key>
   PSHR=<your-password-hash>
   ```

3. **Generate secure secrets:**
   ```bash
   python3 generate_secrets.py "your-admin-password"
   ```

## Management Commands

Use the `manage.sh` script for common operations:

```bash
# View application logs
./manage.sh logs

# Check service status
./manage.sh status

# Restart services
./manage.sh restart

# Update application code
./manage.sh update

# Renew SSL certificates
./manage.sh ssl

# Open shell in webapp container
./manage.sh shell
```

## Troubleshooting

### 502 Bad Gateway
- Check if webapp container is running: `./manage.sh status`
- Restart nginx: `./manage.sh restart nginx`
- Check webapp logs: `./manage.sh logs webapp`

### SSL Certificate Issues
- Ensure DNS is pointing to your server
- Check certbot logs: `./manage.sh logs certbot`
- Try staging first: Set `STAGING=1` in `.env`

### Login Issues
- Verify password hash generation with: `./manage.sh shell`
- Check webapp logs for authentication errors
- Ensure CSRF is properly configured

### DNS Not Resolving
- Wait for DNS propagation (up to 1 hour)
- Test with: `nslookup clue.photoshare.me`
- Temporarily use HTTP-only mode for testing

## Security Notes

- **Change default passwords**: Always use strong, unique passwords
- **Use production SSL**: Set `STAGING=0` after testing
- **Secure server access**: Use SSH keys, disable password auth
- **Regular updates**: Keep Docker images and system packages updated
- **Monitor logs**: Regularly check application and security logs

## File Structure

```
photoshare-deploy/
├── docker-compose.yml       # Main container orchestration
├── Dockerfile              # Python app container definition
├── nginx/                  # Nginx configuration
│   └── templates/
├── .env                    # Environment variables (auto-generated)
├── setup_env.sh           # Environment setup script
├── deploy.sh              # Deployment script
├── manage.sh              # Management script
├── generate_secrets.py    # Secret generation utility
├── app.py                 # Flask application
├── config.py              # Application configuration
├── requirements.txt       # Python dependencies
├── templates/             # Jinja2 templates
└── static/               # Static assets (CSS, images, etc.)
```

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Your domain name | `clue.photoshare.me` |
| `LETSENCRYPT_EMAIL` | Email for SSL certificates | `admin@example.com` |
| `STAGING` | Use staging SSL (1) or production (0) | `1` |
| `FLASK_ENV` | Flask environment | `production` |
| `FKEY` | Flask secret key (auto-generated) | `base64-encoded-string` |
| `WTFKEY` | CSRF secret key (auto-generated) | `base64-encoded-string` |
| `PSHR` | Password hash (auto-generated) | `$2b$12$...` |

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review application logs with `./manage.sh logs`
3. Ensure all prerequisites are met
4. Verify DNS configuration
5. Test with staging SSL first before production 