from __future__ import annotations

import os
from datetime import timedelta


def _require_env(name: str) -> str:
    """Return the value of a required environment variable, raising at startup if absent."""
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"Required environment variable {name!r} is not set. Cannot start."
        )
    return value


class Config:
    SECRET_KEY: str = _require_env("FKEY")
    WTF_CSRF_SECRET_KEY: str = _require_env("WTFKEY")
    # Docker Compose escapes $ as $$ in env values; unescape here.
    PASSWORD_HASH: str = _require_env("PSHR").replace("$$", "$")
    # Disable secure cookie in development (HTTP) so local testing works.
    SESSION_COOKIE_SECURE: bool = os.environ.get("FLASK_ENV") != "development"
    SESSION_COOKIE_HTTPONLY: bool = True
    SESSION_COOKIE_SAMESITE: str = "Lax"
    PERMANENT_SESSION_LIFETIME: timedelta = timedelta(days=1)
