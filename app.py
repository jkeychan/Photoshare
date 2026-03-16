import logging
import os
from functools import lru_cache, wraps
from pathlib import Path
from urllib.parse import unquote

from config import Config
from flask import (
    Flask,
    abort,
    flash,
    redirect,
    render_template,
    send_from_directory,
    session,
    url_for,
)
from flask_bcrypt import Bcrypt
from flask_wtf import FlaskForm
from wtforms import PasswordField
from wtforms.validators import DataRequired

_static_folder = os.environ.get("STATIC_FOLDER", "/mnt/web/photoshare/static")
app = Flask(__name__, static_url_path="/static", static_folder=_static_folder)
app.config.from_object(Config)
app.logger.setLevel(logging.DEBUG)
bcrypt = Bcrypt(app)

_STATIC_ROOT = Path(app.static_folder)
_MEDIA_ROOT = _STATIC_ROOT / "media"
_DOWNLOADS_ROOT = _STATIC_ROOT / "downloads"

# Resolved once at startup — passed to _safe_path so Path.resolve() is not
# re-issued on every request (avoids a realpath(3) syscall per call).
_MEDIA_ROOT_R = _MEDIA_ROOT.resolve()
_DOWNLOADS_ROOT_R = _DOWNLOADS_ROOT.resolve()

_PAGE_SIZE = 10


# ------------------- HELPERS --------------------


def _safe_path(base_r: Path, *parts: str) -> Path:
    """Resolve a joined path and abort 400 if it escapes *base_r* (path traversal guard).

    *base_r* must already be a canonical absolute path; pass one of the
    module-level ``_*_ROOT_R`` constants so ``Path.resolve()`` is not
    re-issued on every request.
    """
    resolved = base_r.joinpath(*parts).resolve()
    if not resolved.is_relative_to(base_r):
        abort(400)
    return resolved


def _list_dir(
    path: Path, *, dirs_only: bool = False, files_only: bool = False
) -> list[str]:
    """Return a sorted list of entry names in *path*.

    Returns an empty list if the directory does not exist.  Pass *dirs_only*
    or *files_only* to filter by entry type.
    """
    try:
        entries = path.iterdir()
        if dirs_only:
            return sorted(e.name for e in entries if e.is_dir())
        if files_only:
            return sorted(e.name for e in entries if e.is_file())
        return sorted(e.name for e in entries)
    except FileNotFoundError:
        return []


@lru_cache(maxsize=256)
def _list_directory_cached(
    dir_path: Path, _mtime: float
) -> tuple[list[str], list[str]]:
    """Return (files, subdirs) for *dir_path*, sorted, in a single iterdir() pass.

    *_mtime* is the directory's modification time and acts as a cache-bust key —
    the cache is invalidated automatically when the directory contents change.
    Results are cached across pagination requests for the same album state,
    avoiding a full O(n log n) sort on every page flip.
    """
    entries = list(dir_path.iterdir())
    return (
        sorted(e.name for e in entries if e.is_file()),
        sorted(e.name for e in entries if e.is_dir()),
    )


# ------------------- DECORATORS --------------------


def login_required(f):
    """Redirect unauthenticated requests to the login page."""

    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("index"))
        return f(*args, **kwargs)

    return decorated


# ------------------- FORMS --------------------


class LoginForm(FlaskForm):
    password = PasswordField("Password", validators=[DataRequired()])


# ------------------- ROUTES --------------------


@app.route("/favicon.ico")
def favicon():
    return send_from_directory(
        _STATIC_ROOT, "favicon.ico", mimetype="image/vnd.microsoft.icon"
    )


@app.route("/", methods=["GET", "POST"])
def index():
    if session.get("logged_in"):
        return render_template(
            "index.html",
            directories=_list_dir(_MEDIA_ROOT, dirs_only=True),
        )

    form = LoginForm()
    if form.validate_on_submit():
        if bcrypt.check_password_hash(app.config["PASSWORD_HASH"], form.password.data):
            session["logged_in"] = True
            session.permanent = True
            return redirect(url_for("index"))
        flash("Login failed.", "error")
    return render_template("login.html", form=form)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


@app.route("/downloads/")
@login_required
def downloads():
    return render_template(
        "downloads.html",
        files=_list_dir(_DOWNLOADS_ROOT, files_only=True),
    )


@app.route("/directory/<path:directory>/", defaults={"page": 1})
@app.route("/directory/<path:directory>/<int:page>/")
@login_required
def show_directory(directory: str, page: int = 1):
    directory = unquote(directory)
    dir_path = _safe_path(_MEDIA_ROOT_R, directory)
    if not dir_path.is_dir():
        abort(404)
    mtime = dir_path.stat().st_mtime
    all_files, subdirs = _list_directory_cached(dir_path, mtime)
    total_pages = max(1, (len(all_files) + _PAGE_SIZE - 1) // _PAGE_SIZE)
    return render_template(
        "directory.html",
        directory=directory,
        subdirs=subdirs if page == 1 else [],
        files=all_files[(page - 1) * _PAGE_SIZE : page * _PAGE_SIZE],
        total_pages=total_pages,
        current_page=page,
    )


@app.route("/download/<filename>/")
@login_required
def download_file(filename: str):
    filename = unquote(filename)
    file_path = _safe_path(_DOWNLOADS_ROOT_R, filename)
    if not file_path.is_file():
        abort(404)
    return send_from_directory(_DOWNLOADS_ROOT, filename, as_attachment=True)


# ------------------- ERROR HANDLERS --------------------


@app.errorhandler(400)
def bad_request(e):
    return render_template("error.html", error_message="Bad request."), 400


@app.errorhandler(404)
def not_found(e):
    return render_template("error.html", error_message="Page not found."), 404


@app.errorhandler(429)
def ratelimit_handler(e):
    return (
        render_template(
            "error.html", error_message="Too many requests. Please slow down."
        ),
        429,
    )


# ------------------- MAIN --------------------

if __name__ == "__main__":
    app.run()
