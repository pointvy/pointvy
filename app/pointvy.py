import os
import re
import subprocess

from flask import Flask
from flask import request
from flask import render_template
from flask import url_for
from flask import redirect
import logging

app = Flask(__name__)

handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
app.logger.addHandler(handler)
app.logger.setLevel(logging.INFO)

TRIVY_VERSION = os.environ.get("TRIVY_VERSION")
POINTVY_VERSION = os.environ.get("POINTVY_VERSION")


def get_trivy_version():
    try:
        result = subprocess.run(
            ["./trivy", "--version"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10
        )
        line = result.stdout
    except subprocess.CalledProcessError as e:
        app.logger.error(f"Trivy version check failed: {e.stderr}")
        return "unknown"
    except Exception as e:
        app.logger.error(f"Error getting Trivy version: {str(e)}")
        return "unknown"
    version = re.findall(r"\d+\.\d+\.\d", line)
    app.logger.info(f"Trivy version: {version[0]}")
    return version[0]


@app.route("/")
def landing():
    action = url_for("trivy_scan")
    return render_template('main.html', content="",
                           action=action, trivy_version=get_trivy_version(),
                           pointvy_version=POINTVY_VERSION, checked="checked")


@app.route("/scan/")
def trivy_scan():
    query = request.args.get("q")
    app.logger.info(f"Starting trivy scan with query: {query}")

    if query:

        # delete every char except a-z A-Z 0-9 : - . , / and space
        bash_escape = re.compile(r'[^a-zA-Z0-9\:\-\.\ \,\/]')
        query_sanitized = bash_escape.sub('', query)

        cmd = ["./trivy", "image", "--scanners", "vuln", "--no-progress"]

        checked_value = ""
        if request.args.get("ignore-unfixed") == "true":
            cmd.append("--ignore-unfixed")
            checked_value = "checked"

        cmd.append(format(query_sanitized))

        error = ""
        content = ""

        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

        try:
            app.logger.info(f"Executing command: {cmd}")
            res = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE) # nosemgrep
            output, error_handler = res.communicate()
            if output:
                app.logger.info(f"Query successful.")
                content = output.decode('utf-8')
            else:
                if error_handler:
                    app.logger.error(f"Error> error {error_handler.strip()}")
                    error = error_handler.strip().decode('utf-8')
                    error = ansi_escape.sub('', error)
        except OSError as e:
            app.logger.error(f"OSError > {e.errno} | {e.strerror} | {e.filename}")

            error = e.strerror.decode('utf-8')

        # remove colors special characters
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        result = ansi_escape.sub('', content)

    else:
        return redirect(url_for("landing"))

    action = url_for("trivy_scan")

    return render_template("main.html", content=result,
                           action=action, query=query_sanitized,
                           trivy_version=get_trivy_version(),
                           pointvy_version=POINTVY_VERSION,
                           checked=checked_value, error=error)


if __name__ == "__main__":

    # nosemgrep
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
