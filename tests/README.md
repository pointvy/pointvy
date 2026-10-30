# Tests

Two layers:

- `unit/`: pytest tests of `app/pointvy.py` with Trivy mocked. Fast, no
  Docker or network. Run on every PR touching `app/`, `tests/unit/` or the
  `Dockerfile` (`.github/workflows/unit.yml`).
- `smoke.sh`: end-to-end tests against the real container.

## Unit tests (`unit/`)

```bash
make unit                           # or: cd app && uv run --locked pytest
```

`subprocess.Popen` (scan) and `subprocess.run` (version check) are replaced
by fakes that record the argv and return canned output, so the tests assert
the exact Trivy command line (`--` immediately before a single query
argument), the character filter, `ignore-unfixed` handling, output escaping
and ANSI stripping, error paths and log escaping.

Known bugs are marked `@pytest.mark.xfail(strict=True)` (`xfail_strict` is
set in `app/pyproject.toml`): they report `XFAIL` while the bug reproduces
and turn into a failure once it is fixed, so the marker must be removed.

| Known bug (unit) | Test |
|---|---|
| `@` stripped: digest references break | `test_digest_reference_is_preserved` |
| `_` stripped: valid names break | `test_underscore_reference_is_preserved` |

## Container smoke tests (`smoke.sh`)

Builds the image, runs it, and checks the HTTP API end to end.

```bash
make smoke                          # build + run all checks
SKIP_BUILD=1 IMAGE=pointvy tests/smoke.sh   # reuse an existing image
KEEP=1 tests/smoke.sh               # leave the container running afterwards
```

CI runs it on every PR that touches `app/`, `Dockerfile`, `.dockerignore` or
`tests/` (`.github/workflows/smoke.yml`), and on demand via *Run workflow*.

Requires Docker, curl and network access (Trivy downloads its database and
pulls the scanned images). A full run takes a few minutes.

| Group | IDs | What it checks |
|---|---|---|
| Build | B1–B2 | Image builds with `uv sync --locked`, runs as `gunicorn` |
| Runtime | R1–R5 | App starts; uid 1001; gunicorn/Trivy versions match `uv.lock`/`Dockerfile`; nothing runs as root |
| Functional | F1–F7 | Landing page, real scans, `ignore-unfixed`, redirect, clean errors, a query that filters to nothing is rejected |
| Security | S1–S9 | Shell metacharacters, reflected HTML, log injection, Trivy option injection (`-c`, `-i`, `-o`, `--help`, options after a space), oversized query, `ignore-unfixed` values, duplicate `q` |
| HTTP | H1–H4 | `POST` rejected, `/scan` redirect, no debugger console, security headers |
| Image references | K1–K2 | Digest (`@`) and underscore references survive the filter |
| Robustness | X1–X4 | Concurrent scans, missing-binary error path, hung scans killed after `SCAN_TIMEOUT` (second container on `PORT+1`), app keeps answering |
| Shutdown | R6 | Container stops on SIGTERM within the grace period (skipped with `KEEP=1`) |

### Result codes

- `PASS` / `FAIL`: expected behaviour holds / does not. Any `FAIL` makes the script exit 1.
- `XFAIL`: a known bug that still reproduces (does not fail the run). Use
  `known_bug` in the script to track a bug before it is fixed.
- `XPASS`: a known bug no longer reproduces. Convert that check to a normal `result` test.

Known bugs currently tracked (`XFAIL`):

| ID | Bug |
|---|---|
| H4 | No `Content-Security-Policy`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` headers |
| K1 | `@` is stripped, so `image@sha256:...` references break |
| K2 | `_` is stripped, so names like `my_org/my_image` break |
