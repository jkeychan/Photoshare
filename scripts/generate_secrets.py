#!/usr/bin/env python3
"""Generate PhotoShare .env secrets: Flask keys and a bcrypt password hash.

Password is read from stdin — never from argv or environment variables —
so it never appears in shell history, process listings, or system logs.

Usage (interactive):
    python3 scripts/generate_secrets.py

Usage (scripted, password via pipe):
    printf '%s' "$password" | python3 scripts/generate_secrets.py

Output (copy into .env, or let setup.sh handle it automatically):
    FKEY=...
    WTFKEY=...
    PSHR=...
"""

from __future__ import annotations

import getpass
import secrets
import sys

import bcrypt

# bcrypt cost factor — each increment doubles the work.
# 14 gives ~0.5 s on modern hardware; well above OWASP minimum of 10.
_BCRYPT_ROUNDS: int = 14

# 256-bit hex keys for Flask SECRET_KEY and WTF_CSRF_SECRET_KEY.
_KEY_BYTES: int = 32


def flask_key() -> str:
    return secrets.token_hex(_KEY_BYTES)


def bcrypt_hash(password: str) -> str:
    return bcrypt.hashpw(
        password.encode("utf-8"),
        bcrypt.gensalt(rounds=_BCRYPT_ROUNDS),
    ).decode("utf-8")


def main() -> None:
    if sys.stdin.isatty():
        # Interactive: prompt securely (input not echoed)
        password = getpass.getpass("Password: ")
        if not password:
            print("Error: password cannot be empty.", file=sys.stderr)
            sys.exit(1)
    else:
        # Scripted: read from pipe, strip trailing newline only
        password = sys.stdin.read().rstrip("\n")
        if not password:
            print("Error: no password received on stdin.", file=sys.stderr)
            sys.exit(1)

    print(f"FKEY={flask_key()}")
    print(f"WTFKEY={flask_key()}")
    print(f"PSHR={bcrypt_hash(password)}")


if __name__ == "__main__":
    main()
