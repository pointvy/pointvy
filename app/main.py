import os
import re

from flask import Flask
from flask import request
from flask import render_template
from flask import url_for
from flask import redirect

app = Flask(__name__)

TRIVY_VERSION = os.environ.get("TRIVY_VERSION")
POINTVY_VERSION = os.environ.get("POINTVY_VERSION")

@app.route("/")
def landing():
    action = url_for("trivy_scan")
    return render_template('main.html', content="",
                           action=action, trivy_version=TRIVY_VERSION,
                           pointvy_version=POINTVY_VERSION)


@app.route("/scan/")
def trivy_scan():
    query = request.args.get("q")

    if query != "":

        # delete every char except a-z A-Z 0-9 : - . , / and space
        bash_escape = re.compile(r'[^a-zA-Z0-9\:\-\.\ \,\/]')
        query_sanitized = bash_escape.sub('', query)
        cmd = "./trivy image --no-progress " + format(query_sanitized)
        content = os.popen(cmd).read()  # nosec - user input is sanitized

        # remove colors special characters
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        result = ansi_escape.sub('', content)

    else:
        return redirect(url_for("landing"))

    action = url_for("trivy_scan")
    return render_template("main.html", content=result,
                           action=action, query=query_sanitized,
                           trivy_version=TRIVY_VERSION,
                           pointvy_version=POINTVY_VERSION)


if __name__ == "__main__":

    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))  # nosec // nosemgrep
