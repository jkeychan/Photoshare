from datetime import timedelta
import os

# Note that these environment variables are for CSRF protection and other protections
# Ideally you will set these vars manually or via systemd


class Config:
    SECRET_KEY = os.environ.get('FKEY', 'a_secret_key_for_local')
    WTF_CSRF_SECRET_KEY = os.environ.get(
        'WTFKEY', 'a_csrf_secret_key_for_local')
    # Unescape double dollar signs from Docker Compose environment variable escaping
    _raw_password_hash = os.environ.get('PSHR')
    PASSWORD_HASH = _raw_password_hash.replace(
        '$$', '$') if _raw_password_hash else None
    SESSION_COOKIE_SECURE = True  # Set to True when using HTTPS
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    PERMANENT_SESSION_LIFETIME = timedelta(days=1)
