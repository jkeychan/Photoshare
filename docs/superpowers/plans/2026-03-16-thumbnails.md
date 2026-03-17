# Thumbnail Generation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and serve small JPEG thumbnails for photo grid pages so browsers download ~30KB previews instead of full-resolution images (often 3–20 MB each).

**Architecture:** A `thumbnailer.py` module handles Pillow-based thumbnail generation. A Flask route `/thumb/<directory>/<filename>` generates thumbnails on first request and caches them to `static/thumbnails/` on disk. Subsequent page loads for the same album serve from disk. An nginx location block serves pre-existing thumbnails directly, bypassing Flask entirely on warm requests. The directory grid template swaps full-image `<img>` src to the thumbnail URL while keeping the full-resolution link on click.

**Tech Stack:** Python 3.11, Pillow (already in requirements.txt), Flask `send_from_directory`, nginx `try_files`, pytest

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `thumbnailer.py` | **Create** | Pure thumbnail generation logic (Pillow); no Flask imports |
| `app.py` | **Modify** | Add `_THUMBNAILS_ROOT*` constants, `/thumb/` route, wire up thumbnailer |
| `templates/directory.html` | **Modify** | Swap `<img>` src to thumbnail URL; preserve full-res click link |
| `nginx/templates/default.conf.template` | **Modify** | Add `^~ /static/thumbnails/` location with `try_files → @flask` fallback |
| `static/thumbnails/` | **Create (gitignored)** | On-disk cache for generated thumbnails |
| `.gitignore` | **Create/Modify** | Exclude `static/thumbnails/` and `__pycache__` |
| `tests/test_thumbnailer.py` | **Create** | Unit tests for generation logic |
| `tests/test_thumb_route.py` | **Create** | Integration tests for `/thumb/` Flask route |
| `tests/conftest.py` | **Create** | Shared pytest fixtures (Flask test client, temp media dir) |

---

## Chunk 1: Thumbnail generation module + tests

### Task 1: Test infrastructure

**Files:**
- Create: `tests/conftest.py`
- Create: `tests/__init__.py`

- [ ] **Step 1: Create tests/ package and conftest**

```python
# tests/__init__.py  (empty)
```

```python
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
    # 600×400 JPEG
    img = Image.new("RGB", (600, 400), color=(100, 150, 200))
    img.save(media / "photo.jpg", "JPEG")
    # 800×800 RGBA PNG
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
        with app_module.app.session_transaction() as sess:
            sess["logged_in"] = True
        yield client
```

- [ ] **Step 2: Verify conftest imports cleanly**

```bash
cd /Users/jeff/photoshare-deploy
pip install pytest pytest-flask
python -m pytest tests/ --collect-only
```
Expected: 0 items collected, no errors.

- [ ] **Step 3: Commit**

```bash
git add tests/
git commit -m "test: add pytest infrastructure and shared fixtures"
```

---

### Task 2: thumbnailer module

**Files:**
- Create: `thumbnailer.py`
- Create: `tests/test_thumbnailer.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_thumbnailer.py
from pathlib import Path

import pytest
from PIL import Image

from thumbnailer import generate_thumbnail


def test_jpeg_thumbnail_created(tmp_path):
    src = tmp_path / "photo.jpg"
    Image.new("RGB", (2000, 1500)).save(src, "JPEG")
    dest = tmp_path / "thumb.jpg"

    generate_thumbnail(src, dest)

    assert dest.exists()
    with Image.open(dest) as img:
        assert img.format == "JPEG"
        assert max(img.size) <= 400


def test_thumbnail_respects_size_param(tmp_path):
    src = tmp_path / "photo.jpg"
    Image.new("RGB", (2000, 2000)).save(src, "JPEG")
    dest = tmp_path / "thumb.jpg"

    generate_thumbnail(src, dest, size=(200, 200))

    with Image.open(dest) as img:
        assert max(img.size) <= 200


def test_png_rgba_converted_to_jpeg(tmp_path):
    """RGBA PNGs must be converted to RGB before JPEG save."""
    src = tmp_path / "photo.png"
    Image.new("RGBA", (800, 600), (255, 0, 0, 128)).save(src, "PNG")
    dest = tmp_path / "thumb.jpg"

    generate_thumbnail(src, dest)

    assert dest.exists()
    with Image.open(dest) as img:
        assert img.format == "JPEG"
        assert img.mode == "RGB"


def test_parent_dirs_created(tmp_path):
    src = tmp_path / "photo.jpg"
    Image.new("RGB", (400, 300)).save(src, "JPEG")
    dest = tmp_path / "deep" / "nested" / "thumb.jpg"

    generate_thumbnail(src, dest)

    assert dest.exists()


def test_aspect_ratio_preserved(tmp_path):
    """Wide image should not be distorted — only longest side clamped."""
    src = tmp_path / "wide.jpg"
    Image.new("RGB", (1600, 400)).save(src, "JPEG")
    dest = tmp_path / "thumb.jpg"

    generate_thumbnail(src, dest, size=(400, 400))

    with Image.open(dest) as img:
        w, h = img.size
        assert w == 400
        assert h == 100  # 1600:400 → 4:1 → 400×100
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_thumbnailer.py -v
```
Expected: `ImportError: No module named 'thumbnailer'`

- [ ] **Step 3: Implement thumbnailer.py**

```python
# thumbnailer.py
"""Thumbnail generation utilities.

This module has no Flask dependency — it can be imported in tests, management
scripts, and the Flask app without side effects.
"""
from pathlib import Path

from PIL import Image

_DEFAULT_SIZE = (400, 400)


def generate_thumbnail(
    src: Path,
    dest: Path,
    size: tuple[int, int] = _DEFAULT_SIZE,
) -> None:
    """Generate a JPEG thumbnail of *src* at *dest*.

    *size* is the maximum bounding box (width, height) — the image is scaled
    down to fit within it while preserving aspect ratio (PIL ``thumbnail``
    semantics).  Images already smaller than *size* are not enlarged.

    Parent directories of *dest* are created automatically.  Any source format
    supported by Pillow is accepted; the output is always JPEG for consistent
    file size and browser compatibility.

    Args:
        src:  Path to the source image file.
        dest: Destination path for the generated thumbnail.
        size: Maximum (width, height) in pixels. Default 400×400.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as img:
        img.thumbnail(size, Image.LANCZOS)
        img.convert("RGB").save(dest, "JPEG", quality=85, optimize=True)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_thumbnailer.py -v
```
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add thumbnailer.py tests/test_thumbnailer.py
git commit -m "feat: add thumbnail generation module with Pillow"
```

---

## Chunk 2: Flask thumbnail route

### Task 3: /thumb/ route

**Files:**
- Modify: `app.py` — add `_THUMBNAILS_ROOT*` constants and `thumbnail()` view
- Create: `tests/test_thumb_route.py`

- [ ] **Step 1: Write failing route tests**

```python
# tests/test_thumb_route.py
"""Integration tests for the /thumb/ route."""


def test_thumbnail_returns_200_for_existing_image(flask_client, tmp_media):
    """First request generates the thumbnail and returns it."""
    resp = flask_client.get("/thumb/album/photo.jpg")
    assert resp.status_code == 200
    assert resp.content_type.startswith("image/")


def test_thumbnail_is_cached_on_disk(flask_client, tmp_media):
    """Second request serves from cache (file must exist after first request)."""
    flask_client.get("/thumb/album/photo.jpg")
    thumb = tmp_media / "thumbnails" / "album" / "photo.jpg"
    assert thumb.exists()

    resp = flask_client.get("/thumb/album/photo.jpg")
    assert resp.status_code == 200


def test_thumbnail_for_missing_source_returns_404(flask_client):
    resp = flask_client.get("/thumb/album/nonexistent.jpg")
    assert resp.status_code == 404


def test_thumbnail_path_traversal_blocked(flask_client):
    resp = flask_client.get("/thumb/../../../etc/passwd")
    assert resp.status_code in (400, 404)


def test_thumbnail_requires_login(flask_client, tmp_media):
    """Unauthenticated request should redirect to login."""
    with flask_client.session_transaction() as sess:
        sess.clear()
    resp = flask_client.get("/thumb/album/photo.jpg")
    assert resp.status_code == 302


def test_png_source_served_as_jpeg(flask_client, tmp_media):
    resp = flask_client.get("/thumb/album/transparent.png")
    assert resp.status_code == 200
    assert "jpeg" in resp.content_type or "image" in resp.content_type
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_thumb_route.py -v
```
Expected: `404 NOT FOUND` (route doesn't exist yet).

- [ ] **Step 3: Add thumbnail constants and route to app.py**

In `app.py`, after the `_DOWNLOADS_ROOT_R` line add:

```python
_THUMBNAILS_ROOT = _STATIC_ROOT / "thumbnails"
_THUMBNAILS_ROOT_R = _THUMBNAILS_ROOT.resolve()

_THUMB_SIZE = (400, 400)
```

After the existing imports at the top, add:

```python
from thumbnailer import generate_thumbnail
```

Add the route after `downloads()`:

```python
@app.route("/thumb/<path:directory>/<filename>")
@login_required
def thumbnail(directory: str, filename: str):
    """Serve a thumbnail for a media image, generating it on first request.

    Thumbnails are cached as JPEG files in ``static/thumbnails/``, mirroring
    the ``static/media/`` directory structure.  Subsequent requests for the
    same image are served from disk without re-generating.
    """
    directory = unquote(directory)
    filename = unquote(filename)

    src = _safe_path(_MEDIA_ROOT_R, directory, filename)
    if not src.is_file():
        abort(404)

    # Thumbnails are always stored as JPEG (e.g. transparent.png → transparent.jpg)
    thumb_name = Path(filename).stem + ".jpg"
    thumb = _safe_path(_THUMBNAILS_ROOT_R, directory, thumb_name)

    if not thumb.is_file():
        try:
            generate_thumbnail(src, thumb, _THUMB_SIZE)
        except Exception:
            app.logger.exception("Failed to generate thumbnail for %s", src)
            abort(500)

    return send_from_directory(thumb.parent, thumb.name)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python -m pytest tests/test_thumb_route.py -v
```
Expected: 6 passed.

- [ ] **Step 5: Run full test suite**

```bash
python -m pytest tests/ -v
```
Expected: all pass.

- [ ] **Step 6: Ruff check**

```bash
ruff format app.py thumbnailer.py && ruff check app.py thumbnailer.py
```
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add app.py thumbnailer.py tests/test_thumb_route.py tests/conftest.py
git commit -m "feat: add on-demand thumbnail route with disk cache"
```

---

## Chunk 3: Template + nginx + gitignore

### Task 4: Update directory template to use thumbnails

**Files:**
- Modify: `templates/directory.html`

The `<img>` inside the photo grid currently loads full-resolution media. Change it to load the thumbnail instead, keeping the full-resolution `<a href>` link intact so clicking still opens the original.

- [ ] **Step 1: Update the image block in directory.html**

Replace this block (around line 30):

```html
        {% if file.lower().endswith(('.jpg', '.jpeg', '.png')) %}
        <a href="{{ url_for('static', filename='media/' + directory + '/' + file) }}">
            <img src="{{ url_for('static', filename='media/' + directory + '/' + file) }}" alt="{{ file }}" loading="lazy">
        </a>
```

With:

```html
        {% if file.lower().endswith(('.jpg', '.jpeg', '.png')) %}
        <a href="{{ url_for('static', filename='media/' + directory + '/' + file) }}">
            <img src="{{ url_for('thumbnail', directory=directory, filename=file) }}" alt="{{ file }}" loading="lazy">
        </a>
```

Only the `img src` attribute changes — the anchor href stays pointing at the full-resolution file.

- [ ] **Step 2: Smoke-test locally**

```bash
python run_local.py
# open http://localhost:8080 in browser
# log in with password: localtest
# navigate to a directory — confirm images display (thumbnails generated in static/thumbnails/)
# click an image — confirm full-resolution opens
```

- [ ] **Step 3: Commit**

```bash
git add templates/directory.html
git commit -m "feat: use thumbnails in directory grid; full-res link preserved"
```

---

### Task 5: Gitignore and nginx

**Files:**
- Create/Modify: `.gitignore`
- Modify: `nginx/templates/default.conf.template`

- [ ] **Step 1: Add static/thumbnails/ to .gitignore**

```bash
# Check if .gitignore exists
cat .gitignore 2>/dev/null || echo "(none)"
```

Add or create `.gitignore` to include:

```
# Generated thumbnail cache — do not commit
static/thumbnails/

# Python
__pycache__/
*.pyc
.env
venv/
```

- [ ] **Step 2: Add nginx thumbnails location**

In `nginx/templates/default.conf.template`, add this block **before** the `^~ /static/` location (so the longer prefix wins):

```nginx
    # Thumbnails — served directly by nginx when cached; Flask generates on miss.
    # NOTE: This block must come before ^~ /static/ so the longer prefix takes precedence.
    location ^~ /static/thumbnails/ {
        alias /mnt/web/photoshare/static/thumbnails/;

        # Security headers (nginx child blocks don't inherit add_header)
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;

        # Long-lived cache for thumbnails — content is stable once generated
        expires 90d;
        add_header Cache-Control "public, immutable" always;

        access_log off;
    }
```

Note: `try_files` is intentionally omitted here. The `/thumb/` Flask route is the generation trigger; once a thumbnail is written to `static/thumbnails/`, nginx serves it on the next request via this location block (the URL returned to the browser after the first Flask-served response will be a `/static/thumbnails/` URL on a subsequent visit — **or** keep the template pointing to `/thumb/` and let Flask serve from disk; nginx acceleration is a future step). For now, nginx has this block ready for when the template is updated to use `/static/thumbnails/` URLs directly.

> **Future optimisation (not in this plan):** Change the template `<img src>` from `url_for('thumbnail', ...)` → a direct `/static/thumbnails/<dir>/<file>.jpg` URL. nginx then serves 100% of thumbnail requests directly, Flask is only the generator. Requires pre-generating or accepting a broken image on first visit before a warm-up script runs.

- [ ] **Step 3: Ruff + verify template is valid**

```bash
ruff format app.py && ruff check app.py
python -c "from app import app; print('import ok')"
```

- [ ] **Step 4: Run full test suite one final time**

```bash
python -m pytest tests/ -v
```
Expected: all pass.

- [ ] **Step 5: Commit and push**

```bash
git add .gitignore nginx/templates/default.conf.template
git commit -m "feat: nginx location for cached thumbnails; add .gitignore"
git push -u origin feature/thumbnails
```

---

## Deployment Notes

When deploying to the server after merging `feature/thumbnails`:

```bash
# 1. Pull the new code
git pull origin main

# 2. The first thumbnail for each image is generated on first browser request.
#    For a large library, you can warm the cache ahead of time:
docker compose exec webapp python -c "
from pathlib import Path
from thumbnailer import generate_thumbnail

media = Path('/mnt/web/photoshare/static/media')
thumbs = Path('/mnt/web/photoshare/static/thumbnails')
exts = {'.jpg', '.jpeg', '.png'}

for src in sorted(media.rglob('*')):
    if src.suffix.lower() in exts:
        dest = thumbs / src.relative_to(media)
        dest = dest.with_suffix('.jpg')
        if not dest.exists():
            print(f'  {src.name}', end='', flush=True)
            generate_thumbnail(src, dest)
            print(' ok')
print('done')
"

# 3. Rebuild and restart
docker compose up --build -d
```

## What This Does NOT Cover

- **Video thumbnails**: Generating a poster frame from MP4/MOV requires ffmpeg. Out of scope here — videos continue to render inline as before.
- **nginx try_files acceleration**: The plan lays the nginx groundwork but keeps the template pointing to `/thumb/` for simplicity. A follow-up task can switch the `<img src>` to `/static/thumbnails/` once the warm-up script is standard practice.
- **Thumbnail invalidation**: If a source photo is replaced with a different file at the same path, the cached thumbnail will be stale. Acceptable for this use case (immutable media archive). The warm-up script skips existing thumbnails (`if not dest.exists()`), so re-running it after an update won't refresh stale ones — delete the specific thumbnail manually if needed.
