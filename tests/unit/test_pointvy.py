"""Unit tests for app/pointvy.py.

Trivy is never executed: subprocess.run (version check) and
subprocess.Popen (scan) are replaced by fakes that record the argv and
return canned output. Run with:  cd app && uv run pytest

Known bugs are marked xfail(strict=True) (xfail_strict in pyproject.toml):
they pass while the bug reproduces and fail once it is fixed, so the marker
has to be removed, like XPASS in tests/smoke.sh.
"""

import subprocess

import pytest

import pointvy

BASE_CMD = ["./trivy", "image", "--scanners", "vuln", "--no-progress"]


class FakePopen:
    """Stands in for subprocess.Popen; records every call."""

    calls = []
    stdout = b""
    stderr = b""
    raise_on_start = None

    def __init__(self, cmd, **kwargs):
        if FakePopen.raise_on_start:
            raise FakePopen.raise_on_start
        self.cmd = cmd
        self.kwargs = kwargs
        self.communicate_kwargs = None
        FakePopen.calls.append(self)

    def communicate(self, **kwargs):
        self.communicate_kwargs = kwargs
        return FakePopen.stdout, FakePopen.stderr


@pytest.fixture(autouse=True)
def fake_trivy(monkeypatch):
    FakePopen.calls = []
    FakePopen.stdout = b"alpine:latest (alpine 3.22.0)\nTotal: 0\n"
    FakePopen.stderr = b""
    FakePopen.raise_on_start = None
    monkeypatch.setattr(pointvy.subprocess, "Popen", FakePopen)
    set_version_output(monkeypatch, "Version: 0.76.1\n")
    monkeypatch.setattr(pointvy, "POINTVY_VERSION", "9.9.9")
    return FakePopen


def set_version_output(monkeypatch, stdout=None, exc=None):
    def fake_run(cmd, **kwargs):
        if exc:
            raise exc
        return subprocess.CompletedProcess(cmd, 0, stdout=stdout, stderr="")
    monkeypatch.setattr(pointvy.subprocess, "run", fake_run)


@pytest.fixture
def client():
    # TESTING stays off: an unhandled exception must surface as a 500,
    # the way users would see it, not be re-raised into the test.
    return pointvy.app.test_client()


def scan(client, **params):
    return client.get("/scan/", query_string=params)


def last_cmd():
    assert FakePopen.calls, "Trivy was not started"
    return FakePopen.calls[-1].cmd


def body(resp):
    return resp.get_data(as_text=True)


# --- landing page ------------------------------------------------------------

def test_landing_shows_versions(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert "Trivy version: 0.76.1" in body(resp)
    assert "Pointvy version: 9.9.9" in body(resp)
    assert 'value="true" checked' in body(resp)
    assert FakePopen.calls == []


@pytest.mark.parametrize("exc", [
    FileNotFoundError(2, "No such file or directory", "./trivy"),
    subprocess.CalledProcessError(1, ["./trivy"], stderr="boom"),
    subprocess.TimeoutExpired(["./trivy"], 10),
])
def test_landing_version_unknown_when_trivy_fails(client, monkeypatch, exc):
    set_version_output(monkeypatch, exc=exc)
    resp = client.get("/")
    assert resp.status_code == 200
    assert "Trivy version: unknown" in body(resp)


@pytest.mark.xfail(reason="known bug: IndexError when --version output has no version")
def test_landing_survives_unexpected_version_output(client, monkeypatch):
    set_version_output(monkeypatch, "something unexpected\n")
    resp = client.get("/")
    assert resp.status_code == 200
    assert "Trivy version: unknown" in body(resp)


@pytest.mark.xfail(reason=r"known bug: regex \d+\.\d+\.\d keeps one patch digit")
def test_landing_version_with_two_digit_patch(client, monkeypatch):
    set_version_output(monkeypatch, "Version: 0.76.12\n")
    assert "Trivy version: 0.76.12<" in body(client.get("/"))


# --- routing ------------------------------------------------------------------

@pytest.mark.parametrize("params", [{}, {"q": ""}])
def test_scan_without_query_redirects(client, params):
    resp = scan(client, **params)
    assert resp.status_code == 302
    assert resp.headers["Location"].endswith("/")
    assert FakePopen.calls == []


def test_scan_without_trailing_slash_redirects(client):
    resp = client.get("/scan?q=alpine")
    assert resp.status_code == 308
    assert FakePopen.calls == []


def test_post_scan_not_allowed(client):
    assert client.post("/scan/", data={"q": "alpine"}).status_code == 405
    assert FakePopen.calls == []


def test_unknown_path_is_404(client):
    assert client.get("/console").status_code == 404


# --- command construction ---------------------------------------------------

def test_scan_command(client):
    resp = scan(client, q="alpine:latest")
    assert resp.status_code == 200
    assert last_cmd() == BASE_CMD + ["--", "alpine:latest"]


def test_scan_runs_without_shell(client):
    scan(client, q="alpine")
    assert not FakePopen.calls[-1].kwargs.get("shell")
    assert isinstance(last_cmd(), list)


def test_ignore_unfixed(client):
    resp = scan(client, q="alpine", **{"ignore-unfixed": "true"})
    assert last_cmd() == BASE_CMD + ["--ignore-unfixed", "--", "alpine"]
    assert 'value="true" checked' in body(resp)


@pytest.mark.parametrize("value", ["TRUE", "1", "on", "", "--debug", "true --debug", "true\n"])
def test_ignore_unfixed_other_values_are_ignored(client, value):
    resp = scan(client, q="alpine", **{"ignore-unfixed": value})
    assert last_cmd() == BASE_CMD + ["--", "alpine"]
    assert 'value="true" checked' not in body(resp)


@pytest.mark.parametrize("query", [
    "--help",
    "--download-db-only",
    "-c/app/pointvy.py",
    "-o/app/templates/main.html",
    "alpine -o/tmp/x",
    "alpine:latest --format json",
])
def test_option_like_query_is_a_single_argument_after_separator(client, query):
    scan(client, q=query)
    cmd = last_cmd()
    assert cmd == BASE_CMD + ["--", query]


def test_duplicate_query_uses_first_value(client):
    client.get("/scan/?q=alpine&q=--help")
    assert last_cmd() == BASE_CMD + ["--", "alpine"]


def test_duplicate_ignore_unfixed_uses_first_value(client):
    client.get("/scan/?q=alpine&ignore-unfixed=no&ignore-unfixed=true")
    assert "--ignore-unfixed" not in last_cmd()


# --- character filter ---------------------------------------------------------

@pytest.mark.parametrize("query, expected", [
    ("alpine;id", "alpineid"),
    ("alpine$(id)", "alpineid"),
    ("alpine|id", "alpineid"),
    ("alpine`id`", "alpineid"),
    ("alpine&&id", "alpineid"),
    ("alpine>/tmp/x", "alpine/tmp/x"),
    ("alpine\nid", "alpineid"),
    ("<script>alert(1)</script>", "scriptalert1/script"),
    ('alpine" onfocus="x', "alpine onfocusx"),
])
def test_filter_strips_disallowed_characters(client, query, expected):
    scan(client, q=query)
    assert last_cmd()[-1] == expected


def test_filter_keeps_allowed_characters(client):
    query = "ghcr.io/Org-1/img.name:v1.2-rc,x y"
    scan(client, q=query)
    assert last_cmd()[-1] == query


@pytest.mark.xfail(reason="known bug: '@' is stripped, digest references break")
def test_digest_reference_is_preserved(client):
    query = "alpine@sha256:" + "a" * 64
    scan(client, q=query)
    assert last_cmd()[-1] == query


@pytest.mark.xfail(reason="known bug: '_' is stripped, valid names break")
def test_underscore_reference_is_preserved(client):
    query = "my_org/my_image:1_0"
    scan(client, q=query)
    assert last_cmd()[-1] == query


@pytest.mark.xfail(reason="known bug: a query that filters to '' still runs Trivy")
def test_query_that_filters_to_empty_is_rejected(client):
    resp = scan(client, q="<>;|")
    assert FakePopen.calls == []
    assert "alert-warning" in body(resp)


# --- output handling ----------------------------------------------------------

def test_report_is_rendered(client):
    resp = scan(client, q="alpine")
    assert "Total: 0" in body(resp)
    assert "alert-warning" not in body(resp)


def test_stderr_ignored_when_stdout_present(client, fake_trivy):
    fake_trivy.stderr = b"INFO some log line"
    resp = scan(client, q="alpine")
    assert "Total: 0" in body(resp)
    assert "some log line" not in body(resp)


def test_stderr_shown_as_error_when_no_stdout(client, fake_trivy):
    fake_trivy.stdout = b""
    fake_trivy.stderr = b"FATAL image not found\n"
    resp = scan(client, q="nope")
    assert resp.status_code == 200
    assert "alert-warning" in body(resp)
    assert "FATAL image not found" in body(resp)


def test_ansi_codes_are_stripped(client, fake_trivy):
    fake_trivy.stdout = b"\x1b[31mCRITICAL\x1b[0m Total: 1"
    text = body(scan(client, q="alpine"))
    assert "\x1b" not in text
    assert "CRITICAL Total: 1" in text

    fake_trivy.stdout = b""
    fake_trivy.stderr = b"\x1b[1mFATAL\x1b[0m failed"
    text = body(scan(client, q="alpine"))
    assert "\x1b" not in text
    assert "FATAL failed" in text


def test_scanner_output_is_html_escaped(client, fake_trivy):
    fake_trivy.stdout = b"<script>alert(1)</script>"
    text = body(scan(client, q="alpine"))
    assert "<script>alert(1)</script>" not in text
    assert "&lt;script&gt;" in text


def test_scanner_error_is_html_escaped(client, fake_trivy):
    fake_trivy.stdout = b""
    fake_trivy.stderr = b"<img src=x onerror=alert(1)>"
    text = body(scan(client, q="alpine"))
    assert "<img src=x" not in text
    assert "&lt;img" in text


def test_missing_scanner_gives_generic_error(client, fake_trivy):
    fake_trivy.raise_on_start = FileNotFoundError(2, "No such file or directory", "./trivy")
    resp = scan(client, q="alpine")
    text = body(resp)
    assert resp.status_code == 200
    assert "The scanner could not be started." in text
    assert "Errno" not in text
    assert "No such file" not in text
    assert "./trivy" not in text


@pytest.mark.xfail(reason="known bug: no stdout and no stderr renders a blank result")
def test_silent_scanner_failure_shows_an_error(client, fake_trivy):
    fake_trivy.stdout = b""
    fake_trivy.stderr = b""
    assert "alert-warning" in body(scan(client, q="alpine"))


@pytest.mark.xfail(reason="known gap: scans have no timeout")
def test_scan_has_a_timeout(client):
    scan(client, q="alpine")
    assert FakePopen.calls[-1].communicate_kwargs.get("timeout")


# --- logging ------------------------------------------------------------------

def test_query_newlines_are_escaped_in_logs(client, caplog):
    caplog.set_level("INFO", logger=pointvy.app.logger.name)
    scan(client, q="alpine\nFORGED - INFO - fake entry")
    messages = [r.getMessage() for r in caplog.records]
    assert any("'alpine\\nFORGED" in m for m in messages)
    assert not any("\n" in m for m in messages)
