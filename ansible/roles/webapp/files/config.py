from datetime import timedelta
import os

# Note that these environment variables are for CSRF protection and other protections
# Ideally you will set these vars manually or via systemd


class Config:
    SECRET_KEY = os.environ.get('FLASK_SECRET_KEY', 'a_secret_key_for_local')
    WTF_CSRF_SECRET_KEY = os.environ.get(
        'FLASK_WTF_SECRET_KEY', 'a_csrf_secret_key_for_local')
    PASSWORD_HASH = os.environ.get('PSHR')
    SESSION_COOKIE_SECURE = True
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    PERMANENT_SESSION_LIFETIME = timedelta(days=1)
