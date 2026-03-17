# tests/conftest.py
import os
from pathlib import Path

import pytest
from PIL import Image


@pytest.fixture()
def tmp_media(tmp_path: Path) -> Path:
    """Temporary directory pre-populated with a small JPEG and PNG."""
    media = tmp_path / "media" / "album"
    media.mkdir(parents=True)
    img = Image.new("RGB", (600, 400), color=(100, 150, 200))
    img.save(media / "photo.jpg", "JPEG")
    img2 = Image.new("RGBA", (800, 800), color=(200, 100, 50, 128))
    img2.save(media / "transparent.png", "PNG")
    return tmp_path


@pytest.fixture()
def flask_client(tmp_media: Path, monkeypatch):
    """Flask test client with static folder pointed at tmp_media."""
    monkeypatch.setenv("STATIC_FOLDER", str(tmp_media))
    monkeypatch.setenv("FKEY", "test-secret")
    monkeypatch.setenv("WTFKEY", "test-csrf")
    monkeypatch.setenv("PSHR", "$2b$12$qfPpsxfAlFNAmznoj/n3wuitqnOkhYydBFSs7uMBaMrdO5gUGG2UK")
    import importlib
    import app as app_module
    importlib.reload(app_module)
    app_module.app.config["TESTING"] = True
    app_module.app.config["WTF_CSRF_ENABLED"] = False
    with app_module.app.test_client() as client:
        with client.session_transaction() as sess:
            sess["logged_in"] = True
        yield client
