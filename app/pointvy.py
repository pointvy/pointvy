import os
import re
import signal
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
# seconds before a scan is killed; gunicorn runs with --timeout 0, so without
# it a hanging scan would hold one of the two threads forever
SCAN_TIMEOUT = int(os.environ.get("SCAN_TIMEOUT", "300"))


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
    version = re.findall(r"\d+\.\d+\.\d+", line)
    if not version:
        app.logger.error(f"No version in Trivy output: {line!r}")
        return "unknown"
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
    # !r escapes CR/LF so the raw query cannot forge log lines
    app.logger.info(f"Starting trivy scan with query: {query!r}")

    if query:

        # delete every char except a-z A-Z 0-9 : - . , / and space
        bash_escape = re.compile(r'[^a-zA-Z0-9\:\-\.\ \,\/]')
        query_sanitized = bash_escape.sub('', query)

        cmd = ["./trivy", "image", "--scanners", "vuln", "--no-progress"]

        checked_value = ""
        if request.args.get("ignore-unfixed") == "true":
            cmd.append("--ignore-unfixed")
            checked_value = "checked"

        # nothing left after filtering: do not run Trivy with an empty reference
        if not query_sanitized.strip():
            app.logger.info("Query is empty after filtering.")
            return render_template("main.html", content="",
                                   action=url_for("trivy_scan"), query="",
                                   trivy_version=get_trivy_version(),
                                   pointvy_version=POINTVY_VERSION,
                                   checked=checked_value,
                                   error="The query does not contain a valid image reference.")

        # "--" ends option parsing: a query starting with "-" (still allowed
        # by the filter above) is an image reference, never a Trivy flag
        cmd.append("--")
        cmd.append(format(query_sanitized))

        error = ""
        content = ""

        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

        try:
            app.logger.info(f"Executing command: {cmd}")
            # own process group, so a timeout kills Trivy and any child
            res = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, # nosemgrep
                start_new_session=True)
            try:
                output, error_handler = res.communicate(timeout=SCAN_TIMEOUT)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(res.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass  # ended between the timeout and the kill
                res.communicate()
                app.logger.error(f"Scan timed out after {SCAN_TIMEOUT}s.")
                output, error_handler = b"", b""
                error = "The scan timed out."
            if output:
                app.logger.info(f"Query successful.")
                content = output.decode('utf-8')
            elif error_handler:
                app.logger.error(f"Error> error {error_handler.strip()}")
                error = error_handler.strip().decode('utf-8')
                error = ansi_escape.sub('', error)
            elif not error:
                app.logger.error(f"Scan produced no output (exit code {res.returncode}).")
                error = "The scan returned no result."
        except OSError as e:
            app.logger.error(f"OSError > {e.errno} | {e.strerror} | {e.filename}")

            # generic message: do not expose system details to the client
            error = "The scanner could not be started."

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
