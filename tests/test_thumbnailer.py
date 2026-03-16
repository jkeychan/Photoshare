from pathlib import Path
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
    src = tmp_path / "wide.jpg"
    Image.new("RGB", (1600, 400)).save(src, "JPEG")
    dest = tmp_path / "thumb.jpg"
    generate_thumbnail(src, dest, size=(400, 400))
    with Image.open(dest) as img:
        w, h = img.size
        assert w == 400
        assert h == 100  # 1600:400 = 4:1, scaled to 400×100
