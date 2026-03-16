"""Local development runner. Sets required env vars and disables HTTPS-only cookie."""

import os

os.environ.setdefault("FLASK_ENV", "development")
os.environ.setdefault("FKEY", "localdev-secret")
os.environ.setdefault("WTFKEY", "localdev-csrf")
# bcrypt hash of "localtest"
os.environ.setdefault(
    "PSHR", "$2b$12$qfPpsxfAlFNAmznoj/n3wuitqnOkhYydBFSs7uMBaMrdO5gUGG2UK"
)
os.environ.setdefault(
    "STATIC_FOLDER",
    os.path.join(os.path.dirname(__file__), "static"),
)

from app import app  # noqa: E402

if __name__ == "__main__":
    app.run(port=8080, debug=False)
