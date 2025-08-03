#!/usr/bin/env python3
import os
from flask_bcrypt import Bcrypt
from config import Config

bcrypt = Bcrypt()
config_hash = getattr(Config, 'PASSWORD_HASH', 'NOT_FOUND')
env_hash = os.environ.get('PSHR', 'NOT_FOUND')

print('Config PASSWORD_HASH:', repr(config_hash))
print('Environment PSHR:', repr(env_hash))
print('Are they the same?', config_hash == env_hash)

# Test the password
test_password = 'farts123!'
print('Testing password:', repr(test_password))
print('Hash verification with config:',
      bcrypt.check_password_hash(config_hash, test_password))
print('Hash verification with env:',
      bcrypt.check_password_hash(env_hash, test_password))

# Also test if form validation might be the issue
print('Hash length:', len(config_hash) if config_hash != 'NOT_FOUND' else 'N/A')
print('Hash starts with $2b$:', config_hash.startswith(
    '$2b$') if config_hash != 'NOT_FOUND' else 'N/A')
