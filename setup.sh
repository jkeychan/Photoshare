#!/usr/bin/env bash
# setup.sh — PhotoShare first-time setup
#
# Run this on the server where you want to host PhotoShare.
# Asks three questions (domain, email, password), then does everything else.
#
# Requirements: Docker (with Compose plugin), Python 3, bcrypt pip package.

set -euo pipefail
IFS=$'\n\t'

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}!${NC}  $*"; }
err()  { echo -e "  ${RED}✗${NC}  $*" >&2; }
die()  { err "$*"; exit 1; }
h1()   { echo; echo -e "${BOLD}${BLUE}── $* ──────────────────────────────────────${NC}"; }
ask()  { read -r -p "  $1 " "$2"; }      # ask <prompt> <varname>
asks() { read -s -r -p "  $1 " "$2"; echo; }  # ask silently (no echo)

# ── Must run from project root ────────────────────────────────────────────────
[[ -f "docker-compose.yml" && -f "app.py" ]] ||
    die "Run setup.sh from the Photoshare project directory (e.g. ~/photoshare)."

echo
echo -e "${BOLD}PhotoShare Setup${NC}"
echo "────────────────────────────────────────────────────────"
echo "  This script will configure and start your photo gallery."
echo "  It will ask for your domain, email, and a login password."
echo "  Everything else is automatic."
echo

# ── Step 1: Prerequisites ─────────────────────────────────────────────────────
h1 "Checking prerequisites"

command -v docker &>/dev/null       || die "Docker not found. Install it from https://docs.docker.com/get-docker/"
docker info &>/dev/null 2>&1        || die "Docker is not running. Start the Docker daemon and try again."
docker compose version &>/dev/null  || die "'docker compose' plugin not found. Update Docker to v20.10+."
ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1) + Compose plugin"

command -v python3 &>/dev/null      || die "python3 not found. Install Python 3.10 or later."
python3 -c "import bcrypt" 2>/dev/null || die "Python 'bcrypt' not installed. Run: pip3 install bcrypt"
ok "Python $(python3 --version | cut -d' ' -f2) + bcrypt"

command -v curl &>/dev/null         || die "curl not found. Install it (e.g. sudo apt install curl)."
ok "curl"

# ── Step 2: Re-use existing config? ───────────────────────────────────────────
REUSE_ENV=false
if [[ -f ".env" ]] && grep -q '^\$2[aby]\$' <(grep "^PSHR=" .env | cut -d= -f2-) 2>/dev/null; then
    h1 "Existing configuration found"
    existing_domain=$(grep "^DOMAIN=" .env | cut -d= -f2-)
    existing_email=$(grep "^LETSENCRYPT_EMAIL=" .env | cut -d= -f2-)
    echo "  Domain : $existing_domain"
    echo "  Email  : $existing_email"
    echo
    ask "Re-use this configuration? [Y/n]" yn
    if [[ ! "${yn:-}" =~ ^[Nn]$ ]]; then
        REUSE_ENV=true
        DOMAIN="$existing_domain"
        LETSENCRYPT_EMAIL="$existing_email"
        STAGING=$(grep "^STAGING=" .env | cut -d= -f2-)
        ok "Using existing .env"
    fi
fi

if ! $REUSE_ENV; then

    # ── Step 3: Domain ────────────────────────────────────────────────────────
    h1 "Domain name"
    echo "  Your domain must already have an A record pointing to this server."
    echo "  Let's Encrypt will verify ownership before issuing a certificate."
    echo

    while true; do
        ask "Domain (e.g. photos.example.com):" DOMAIN

        # Strip accidental scheme or path
        DOMAIN="${DOMAIN,,}"
        DOMAIN="${DOMAIN#*://}"
        DOMAIN="${DOMAIN%%/*}"
        DOMAIN="${DOMAIN%%.}"   # strip trailing dot

        # Must be empty guard
        [[ -n "$DOMAIN" ]] || { err "Domain cannot be empty."; continue; }

        # Format: labels separated by dots, each label alphanumeric + hyphens
        if [[ ! "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]; then
            err "Invalid domain format. Enter a fully-qualified domain like photos.example.com"
            continue
        fi

        # Not a bare IP
        if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            err "Enter a domain name, not an IP address. Let's Encrypt cannot issue certs for IPs."
            continue
        fi

        # DNS resolution check
        echo -n "  Resolving $DOMAIN... "
        resolved_ip=$(python3 -c "import socket; print(socket.gethostbyname('$DOMAIN'))" 2>/dev/null || true)

        if [[ -z "$resolved_ip" ]]; then
            echo
            warn "$DOMAIN did not resolve. DNS may not have propagated yet (can take up to 48 h)."
            warn "Let's Encrypt will fail if DNS is not set up before the certificate step."
            ask "Continue anyway? [y/N]" yn
            [[ "${yn:-}" =~ ^[Yy]$ ]] || continue
        else
            echo -e "${GREEN}${resolved_ip}${NC}"

            # Check if it points to this machine
            my_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null ||
                    curl -s --max-time 5 https://ifconfig.me 2>/dev/null || true)

            if [[ -n "$my_ip" && "$resolved_ip" == "$my_ip" ]]; then
                ok "$DOMAIN → $resolved_ip (this machine)"
            else
                warn "$DOMAIN resolves to $resolved_ip"
                [[ -n "$my_ip" ]] && warn "This machine's public IP appears to be $my_ip"
                warn "The domain must point to this server for SSL to work."
                ask "Continue anyway? [y/N]" yn
                [[ "${yn:-}" =~ ^[Yy]$ ]] || continue
            fi
        fi
        break
    done

    # ── Step 4: Email ─────────────────────────────────────────────────────────
    h1 "Email address"
    echo "  Used by Let's Encrypt for certificate expiry reminders only."
    echo "  Not stored anywhere else."
    echo

    while true; do
        ask "Email:" LETSENCRYPT_EMAIL
        LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL// /}"  # strip spaces

        [[ -n "$LETSENCRYPT_EMAIL" ]] || { err "Email cannot be empty."; continue; }

        # Must contain exactly one @
        local_part="${LETSENCRYPT_EMAIL%%@*}"
        domain_part="${LETSENCRYPT_EMAIL##*@}"
        at_count=$(tr -cd '@' <<< "$LETSENCRYPT_EMAIL" | wc -c)

        if [[ "$at_count" -ne 1 || -z "$local_part" || -z "$domain_part" ]]; then
            err "Invalid email — must contain exactly one @."
            continue
        fi

        # Domain part must have a dot with a TLD of at least 2 chars
        if [[ ! "$domain_part" =~ \.[a-zA-Z]{2,}$ ]]; then
            err "Email domain looks invalid (e.g. you@example.com)."
            continue
        fi

        ok "$LETSENCRYPT_EMAIL"
        break
    done

    # ── Step 5: Password ──────────────────────────────────────────────────────
    h1 "Login password"
    echo "  This is the password to access your gallery."
    echo "  Minimum 12 characters. Not stored in plaintext — bcrypt-hashed."
    echo

    while true; do
        asks "Password:" ADMIN_PASSWORD

        # Length
        if [[ ${#ADMIN_PASSWORD} -lt 12 ]]; then
            err "Password must be at least 12 characters (got ${#ADMIN_PASSWORD})."
            continue
        fi

        # Strength hints (informational, not blocking)
        strength=0
        [[ "$ADMIN_PASSWORD" =~ [a-z] ]]       && ((strength++)) || true
        [[ "$ADMIN_PASSWORD" =~ [A-Z] ]]       && ((strength++)) || true
        [[ "$ADMIN_PASSWORD" =~ [0-9] ]]       && ((strength++)) || true
        [[ "$ADMIN_PASSWORD" =~ [^a-zA-Z0-9] ]] && ((strength++)) || true

        if   [[ $strength -ge 4 ]]; then ok "Password strength: strong"
        elif [[ $strength -eq 3 ]]; then warn "Password strength: good (add symbols to make it stronger)"
        elif [[ $strength -eq 2 ]]; then warn "Password strength: fair (mix uppercase, numbers, and symbols)"
        else                              warn "Password strength: weak — consider a longer, more varied password"
        fi

        # Confirmation
        asks "Confirm password:" ADMIN_PASSWORD_CONFIRM
        if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
            err "Passwords do not match. Try again."
            # Clear both so they can't leak via error paths
            ADMIN_PASSWORD=""; ADMIN_PASSWORD_CONFIRM=""
            continue
        fi
        unset ADMIN_PASSWORD_CONFIRM
        break
    done

    # ── Step 6: SSL certificate mode ──────────────────────────────────────────
    h1 "SSL certificate"
    echo "  Staging certificates are issued by a Let's Encrypt test CA."
    echo "  They work but browsers will show a security warning."
    echo
    echo "  Recommended: use staging on your first run to verify everything"
    echo "  works, then run setup.sh again and choose production."
    echo

    ask "Use staging certificate? [Y/n]" yn
    if [[ "${yn:-}" =~ ^[Nn]$ ]]; then
        STAGING=0
        warn "Using PRODUCTION certificate."
        warn "Rate limit: 5 certificates per domain per week. Don't run this repeatedly."
    else
        STAGING=1
        ok "Using staging certificate — browser warning expected."
    fi

    # ── Step 7: Media directory ───────────────────────────────────────────────
    h1 "Media directory"
    MEDIA_DIR="/mnt/photoshare/media"

    if [[ ! -d "$MEDIA_DIR" ]]; then
        echo "  Creating $MEDIA_DIR..."
        sudo mkdir -p "$MEDIA_DIR"
        sudo chown -R "$USER:$USER" /mnt/photoshare
        ok "Created $MEDIA_DIR"
    else
        ok "$MEDIA_DIR already exists"
    fi

    # Warn if no media files found
    if ! find "$MEDIA_DIR" -maxdepth 3 -type f \
         \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
            -o -iname "*.mp4" -o -iname "*.mov" \) \
         -print -quit 2>/dev/null | grep -q .; then
        warn "No photos or videos found in $MEDIA_DIR."
        warn "Add them to subfolders there before using the gallery."
        warn "Example: $MEDIA_DIR/Summer-2024/beach.jpg"
    fi

    # ── Step 8: Generate .env ─────────────────────────────────────────────────
    h1 "Generating secrets"
    echo "  Generating cryptographic keys and hashing your password..."
    echo "  (bcrypt with cost factor 14 — this takes a few seconds)"
    echo

    # Flask keys: 256-bit hex via secrets module
    FKEY=$(python3  -c "import secrets; print(secrets.token_hex(32))")
    WTFKEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

    # bcrypt hash: password via stdin pipe, never via argv or env
    PSHR=$(printf '%s' "$ADMIN_PASSWORD" | python3 -c "
import sys, bcrypt
pw = sys.stdin.read()
print(bcrypt.hashpw(pw.encode('utf-8'), bcrypt.gensalt(rounds=14)).decode('utf-8'))
")
    # Password no longer needed in memory
    unset ADMIN_PASSWORD

    # Docker Compose treats $ as variable interpolation in .env values.
    # Escape every $ as $$ so the bcrypt hash is stored literally.
    PSHR_ENV="${PSHR//\$/\$\$}"

    cat > .env << EOF
DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
STAGING=${STAGING}
FLASK_ENV=production
FKEY=${FKEY}
WTFKEY=${WTFKEY}
PSHR=${PSHR_ENV}
EOF
    chmod 600 .env
    ok ".env written (permissions: 600)"

fi  # end ! REUSE_ENV

# ── Step 9: SSL certificate ───────────────────────────────────────────────────
h1 "SSL certificate"

# Check if a cert already exists for this domain
cert_exists=false
if docker run --rm \
       -v photoshare_certbot-etc:/etc/letsencrypt \
       certbot/certbot certificates 2>/dev/null \
   | grep -q "Domains:.*${DOMAIN}"; then
    cert_exists=true
fi

if $cert_exists; then
    ok "Certificate for ${DOMAIN} already exists — skipping issuance."
else
    echo "  Requesting Let's Encrypt certificate for ${DOMAIN}..."
    echo "  Port 80 must be free — stopping any running stack."
    echo

    docker compose down 2>/dev/null || true

    # Wait a moment for port to free
    sleep 2

    staging_flag=""
    [[ "${STAGING}" == "1" ]] && staging_flag="--staging"

    # Run certbot standalone — it binds to port 80, no nginx needed
    docker run --rm \
        -p 80:80 \
        -v photoshare_certbot-etc:/etc/letsencrypt \
        -v photoshare_certbot-var:/var/lib/letsencrypt \
        certbot/certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --no-eff-email \
            --email "${LETSENCRYPT_EMAIL}" \
            ${staging_flag} \
            -d "${DOMAIN}" && ok "Certificate issued." \
    || {
        err "Certificate issuance failed."
        err "Common causes:"
        err "  • ${DOMAIN} does not resolve to this server's IP"
        err "  • Port 80 is blocked by a firewall"
        err "  • Let's Encrypt rate limit hit (5 certs/domain/week for production)"
        err "Check the output above for details, fix the issue, and re-run setup.sh."
        exit 1
    }
fi

# ── Step 10: Start the stack ──────────────────────────────────────────────────
h1 "Starting PhotoShare"

mkdir -p logs/nginx
docker compose up --build -d --wait
ok "Stack started (webapp + nginx + certbot)"

# ── Step 11: Health check ─────────────────────────────────────────────────────
h1 "Health check"

sleep 3
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -A "$UA" --max-time 10 \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")

if [[ "$http_code" == "200" ]]; then
    ok "https://${DOMAIN}/ → HTTP 200"
elif [[ "$http_code" == "000" && "${STAGING}" == "1" ]]; then
    warn "Could not verify (staging cert — curl rejects it). That's expected."
    warn "Open https://${DOMAIN}/ in a browser, accept the SSL warning, and log in."
else
    warn "https://${DOMAIN}/ returned HTTP ${http_code}."
    warn "Give it a minute, then check: docker compose logs -f"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${GREEN}Setup complete!${NC}"
echo
if [[ "${STAGING}" == "1" ]]; then
    echo -e "  URL    : ${YELLOW}https://${DOMAIN}/${NC}"
    echo -e "  ${YELLOW}Browser will warn about the staging certificate — that's normal.${NC}"
    echo
    echo "  When you're happy everything works:"
    echo "    Edit .env and set STAGING=0"
    echo "    Run ./setup.sh again to get a real certificate."
else
    echo -e "  URL    : ${GREEN}https://${DOMAIN}/${NC}"
fi
echo
echo "  Useful commands:"
echo "    docker compose logs -f     — tail all logs"
echo "    docker compose ps          — check container status"
echo "    docker compose down        — stop"
echo "    docker compose up -d       — start (no rebuild)"
echo "    docker compose up --build -d — deploy code changes"
echo
