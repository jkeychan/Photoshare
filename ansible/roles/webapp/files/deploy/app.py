import os
import logging
from urllib.parse import unquote

from flask import (Flask, render_template, request, redirect, url_for, flash,
                   abort, session, send_from_directory)
from flask_bcrypt import Bcrypt
from flask_wtf import FlaskForm
from wtforms import PasswordField, SubmitField
from wtforms.validators import DataRequired
from config import Config
from functools import wraps

app = Flask(__name__, static_url_path='/static',
            static_folder='/mnt/web/photoshare/static')
app.config.from_object(Config)
app.logger.setLevel(logging.DEBUG)
bcrypt = Bcrypt(app)

# app.debug = True


# ------------------- HELPER FUNCTIONS --------------------

def join_static_path(*path_segments):
    """
    Join the given path segments to the static folder path.

    Args:
    *path_segments (str): Path segments to be joined.

    Returns:
    str: Full path joined with the static folder path.
    """
    return os.path.join(app.static_folder, *path_segments)


def get_forwarded_address():
    """
    Get the forwarded IP address from the request headers.

    Returns:
    str: The forwarded IP address or the remote address of the request.
    """
    return request.headers.get('X-Forwarded-For', request.remote_addr)


def is_media_file(filename):
    """
    Check if the given filename is a media file.

    Args:
    filename (str): Name of the file to check.

    Returns:
    bool: True if the file is a media file, otherwise False.
    """
    media_extensions = ('.jpg', '.jpeg', '.png', '.mov', '.mp4')
    return os.path.splitext(filename)[1].lower() in media_extensions


# ------------------- ROUTES & CONTROLLERS --------------------

@app.route('/favicon.ico')
def favicon():
    """Serve the favicon.ico file."""
    return send_from_directory(join_static_path(), 'favicon.ico', mimetype='image/vnd.microsoft.icon')


@app.route('/', methods=['GET', 'POST'])
def index():
    """
    Index route to display the main page or login page.

    Returns:
    Response: Rendered template.
    """
    if session.get('logged_in'):
        directories = [d for d in os.listdir(join_static_path(
            'media')) if os.path.isdir(join_static_path('media', d))]
        if 'downloads' in request.args:
            return render_template('downloads.html', files=os.listdir(join_static_path('downloads')))
        return render_template('index.html', directories=directories)

    form = LoginForm()
    if form.validate_on_submit():
        password_hash = app.config.get('PASSWORD_HASH')
        if bcrypt.check_password_hash(password_hash, form.password.data):
            session['logged_in'] = True
            return redirect(url_for('index'))
        flash('Login Failed.', 'error')

    return render_template('login.html', form=form)


@app.route('/logout')
def logout():
    """Log out the user and redirect to the index page."""
    session.pop('logged_in', None)
    return redirect(url_for('index'))


@app.route('/photo/<path:directory>/<filename>')
def show_photo(directory, filename):
    """
    Serve a specific photo from the given directory.

    Args:
    directory (str): Directory containing the photo.
    filename (str): Name of the photo file.

    Returns:
    Response: Served photo or 404 error if not found.
    """
    directory, filename = unquote(directory), unquote(filename)
    photo_path = join_static_path('media', directory, filename)
    if not os.path.exists(photo_path):
        abort(404, description="Photo not found.")
    return send_from_directory(os.path.dirname(photo_path), os.path.basename(photo_path))


@app.route('/directory/<path:directory>/', defaults={'page': 1}, methods=['GET'])
@app.route('/directory/<path:directory>/<int:page>/', methods=['GET'])
def show_directory(directory, page=1):
    """
    Display files and subdirectories of a given directory.

    Args:
    directory (str): Name of the directory to display.
    page (int): Current page number.

    Returns:
    Response: Rendered template showing the directory contents.
    """
    directory = unquote(directory)
    local_path = join_static_path('media', directory)
    files = sorted([f for f in os.listdir(local_path) if os.path.isfile(
        join_static_path('media', directory, f))])
    subdirs = sorted([d for d in os.listdir(local_path) if os.path.isdir(
        join_static_path('media', directory, d))])

    per_page = 10
    paginated_files = files[(page - 1) * per_page:page * per_page]

    return render_template('directory.html',
                           directory=directory,
                           subdirs=(subdirs if page == 1 else []),
                           files=paginated_files,
                           total_pages=(len(files) + per_page - 1) // per_page,
                           current_page=page)


@app.route('/download/<filename>/', methods=['GET'])
def download_file(filename):
    """
    Serve a file for download from the downloads directory.

    Args:
    filename (str): Name of the file to download.

    Returns:
    Response: Served file for download or 404 error if not found.
    """
    file_path = join_static_path('downloads', filename)
    if os.path.exists(file_path):
        return send_from_directory(join_static_path('downloads'), filename, as_attachment=True)
    abort(404, description="File not found.")


@app.errorhandler(429)
def ratelimit_handler(e):
    """Handle rate limiting error with a custom response."""
    return render_template('error.html'), 429


# ------------------- MODELS & FORMS --------------------

class LoginForm(FlaskForm):
    """
    Form for logging into the application.

    Attributes:
    password (PasswordField): Field to input password.
    submit (SubmitField): Button to submit the form.
    """
    password = PasswordField('Password', validators=[DataRequired()])
    submit = SubmitField('Login')


# ------------------- DECORATORS --------------------

def login_required(f):
    """
    Decorator to ensure a route requires user to be logged in.

    Args:
    f (function): The function to decorate.

    Returns:
    function: The decorated function.
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('logged_in'):
            flash('You need to log in to access this page.', 'error')
            return redirect(url_for('index'))
        return f(*args, **kwargs)

    return decorated_function


# ------------------- MAIN --------------------

if __name__ == '__main__':
    app.run()
