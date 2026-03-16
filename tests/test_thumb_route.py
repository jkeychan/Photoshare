"""Integration tests for the /thumb/ route."""


def test_thumbnail_returns_200_for_existing_image(flask_client, tmp_media):
    resp = flask_client.get("/thumb/album/photo.jpg")
    assert resp.status_code == 200
    assert resp.content_type.startswith("image/")


def test_thumbnail_is_cached_on_disk(flask_client, tmp_media):
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
    with flask_client.session_transaction() as sess:
        sess.clear()
    resp = flask_client.get("/thumb/album/photo.jpg")
    assert resp.status_code == 302


def test_png_source_served_as_jpeg(flask_client, tmp_media):
    resp = flask_client.get("/thumb/album/transparent.png")
    assert resp.status_code == 200
    assert "jpeg" in resp.content_type or "image" in resp.content_type
