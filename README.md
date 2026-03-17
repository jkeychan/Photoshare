# Photoshare

Self-hosted, password-protected photo and video gallery. Serves images and videos from a directory tree via a Flask app behind nginx, with automatic HTTPS via Let's Encrypt.

## Stack

| Layer | Technology |
|-------|-----------|
| App | Python 3.14, Flask 3, Gunicorn |
| Web server | nginx (stable-alpine) |
| SSL | Let's Encrypt / Certbot |
| Thumbnails | Pillow — generated on first request, cached to disk |
| Containers | Docker Compose |

## Features

- **Single-password auth** — bcrypt-hashed, session-based with CSRF protection
- **Folder-based gallery** — media organised into albums under `/mnt/photoshare/media/`
- **Thumbnails** — JPEG thumbnails generated on demand and cached; nginx serves them directly on subsequent requests
- **Video support** — MP4 and MOV playback inline, with download links
- **Downloads section** — serve arbitrary files from a separate downloads directory
- **Pagination** — 10 items per page, cached across page flips (keyed on directory mtime)
- **nginx serving** — media and thumbnails served directly by nginx, not Flask
- **Security** — rate limiting, bot blocking, HSTS, CSP, X-Frame-Options, no hidden-file access, HTTPS-only

## Project Structure

```
photoshare/
├── app.py                  # Flask application
├── thumbnailer.py          # Pillow thumbnail generation (no Flask dependency)
├── config.py               # Config loaded from environment variables
├── requirements.txt        # Direct Python dependencies only
├── Dockerfile              # Multi-stage build (builder + slim runtime)
├── docker-compose.yml      # webapp + nginx + certbot
├── .env.example            # Environment variable template
├── nginx/
│   ├── nginx.conf          # Rate limits, connection zones
│   ├── blockuseragents.rules
│   └── templates/
│       └── default.conf.template  # Virtual host (HTTPS, proxying, static serving)
├── static/                 # CSS, favicon, static assets (committed)
│   ├── media/              # Symlink/mount — not committed
│   └── thumbnails/         # Generated cache — not committed
├── templates/              # Jinja2 HTML templates
└── tests/                  # pytest suite (11 tests)
```

## Setup

### 1. Clone and configure

```bash
git clone https://github.com/jkeychan/Photoshare.git
cd Photoshare
cp .env.example .env
```

Edit `.env`:

```bash
DOMAIN=photos.example.com
LETSENCRYPT_EMAIL=you@example.com
STAGING=1          # use Let's Encrypt staging until everything works, then set to 0
FLASK_ENV=production
FKEY=<random secret>
WTFKEY=<random secret>
PSHR=<bcrypt hash of your password>
```

Generate secrets and password hash:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"  # run twice for FKEY and WTFKEY
python3 -c "import bcrypt; print(bcrypt.hashpw(b'yourpassword', bcrypt.gensalt()).decode())"
```

### 2. Place your media

```
/mnt/photoshare/media/
├── Holiday-2024/
│   ├── beach.jpg
│   └── sunset.mp4
└── Family/
    └── birthday.png
```

`docker-compose.yml` mounts `/mnt/photoshare/media` into the containers read-only.

### 3. Obtain SSL certificate

Run certbot once to issue the initial certificate (nginx must be reachable on port 80):

```bash
docker compose run --rm certbot certonly \
  --webroot --webroot-path=/var/www/html \
  --email "$LETSENCRYPT_EMAIL" --agree-tos --no-eff-email \
  -d "$DOMAIN"
```

Switch `STAGING=0` in `.env` when ready for a production certificate.

### 4. Start

```bash
docker compose up --build -d
docker compose logs -f
```

### Certificate renewal

Certbot is included as a compose service. Run renewal manually or via cron:

```bash
docker compose run --rm certbot renew --non-interactive
docker compose exec nginx nginx -s reload
```

## Local Development

```bash
python3.14 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export FKEY=dev-secret WTFKEY=dev-csrf FLASK_ENV=development
export PSHR='$2b$12$...'  # bcrypt hash of a test password
python run_local.py
```

## Tests

```bash
pip install pytest pillow
pytest tests/ -v
```

11 tests cover the thumbnail module (unit) and thumbnail route (integration), including RGBA→JPEG conversion, path traversal blocking, cache behaviour, and login enforcement.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DOMAIN` | yes | Fully qualified domain name |
| `LETSENCRYPT_EMAIL` | yes | Email for Let's Encrypt notifications |
| `FLASK_ENV` | yes | `production` or `development` |
| `FKEY` | yes | Flask `SECRET_KEY` |
| `WTFKEY` | yes | Flask-WTF CSRF secret |
| `PSHR` | yes | bcrypt hash of the login password |
| `STAGING` | yes | `1` = Let's Encrypt staging, `0` = production |
| `STATIC_FOLDER` | no | Override static folder path (default: `/mnt/web/photoshare/static`) |

## License

MIT
