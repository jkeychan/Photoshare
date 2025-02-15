#!/usr/bin/env python3
# generate_secrets.py

import bcrypt
import sys
import base64
import os


def generate_secret_key(length=48):
    return base64.b64encode(os.urandom(length)).decode('utf-8')


def generate_bcrypt_hash(password):
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: generate_secrets.py <admin_password>")
        sys.exit(1)

    admin_password = sys.argv[1]
    flask_secret_key = generate_secret_key()
    flask_wtf_secret_key = generate_secret_key()
    bcrypt_hash = generate_bcrypt_hash(admin_password)

    print(f"FLASK_SECRET_KEY={flask_secret_key}")
    print(f"FLASK_WTF_SECRET_KEY={flask_wtf_secret_key}")
    print(f"PSHR={bcrypt_hash}")
