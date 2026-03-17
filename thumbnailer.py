"""Thumbnail generation utilities.

No Flask dependency — safe to import in tests and management scripts.
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

    Scales down to fit within *size* (width, height) preserving aspect ratio.
    Images smaller than *size* are not enlarged. Parent dirs created automatically.
    Output is always JPEG regardless of source format.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as img:
        img.thumbnail(size, Image.LANCZOS)
        img.convert("RGB").save(dest, "JPEG", quality=85, optimize=True)
