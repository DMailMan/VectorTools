# Flask web server to allow a remote user to browse files in /tmp
# Requires that Python Flask is installed and working as a pre-req.
# Just 'pip install Flask' if you have pip installed already.

# Intended to act as a development tool to assist with viewing files when there is no
# local GUI running.
# Relies on a template files called files.html which must live in a 'templates' folder
# in a child folder of this program's path.
# To execute, just run 'python file_browse.py'
# Or else use 
# export FLASK_APP=file_browse.py;flask run --host 0.0.0.0
# to run as an externally accessible service

import os
from flask import Flask, render_template, abort, redirect, url_for, send_file
app = Flask(__name__)

@app.route('/', defaults={'req_path': ''})
@app.route('/<path:req_path>')
def dir_listing(req_path):
    BASE_DIR = '/tmp'

    # Joining the base and the requested path
    abs_path = os.path.join(BASE_DIR, req_path)

    # Return 404 if path doesn't exist
    if not os.path.exists(abs_path):
        return abort(404)

    # Check if path is a file and serve
    if os.path.isfile(abs_path):
        return send_file(abs_path)

    # Show directory contents
    files = os.listdir(abs_path)
    return render_template('files.html', files=files)

if __name__ == "__main__":
    app.run()
