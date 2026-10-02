# Pointvy - Claude Code Project Instructions

## Project Overview
Pointvy is a web interface for running the Trivy vulnerability scanner. It is
a small Flask application packaged as a container for serverless platforms
(GCP Cloud Run, Scaleway Serverless Containers).

Versions change often; read them from the source of truth instead of copying
them into docs:

| What | Where |
|---|---|
| Pointvy version | `Dockerfile` (`POINTVY_VERSION`) and `app/pyproject.toml` (keep in sync, then `uv lock`) |
| Trivy version | `Dockerfile` (`FROM aquasec/trivy:X.Y.Z`) |
| Python base image | `Dockerfile` (`FROM python:...-alpine...@sha256:...`, digest-pinned) |
| Python dependencies | `app/pyproject.toml` (ranges) and `app/uv.lock` (resolved) |
| uv version | `Dockerfile` (`UV_VERSION` and the `ghcr.io/astral-sh/uv` copy) |

## Architecture

- **Backend**: `app/pointvy.py`, Flask, two routes.
- **Frontend**: `app/templates/main.html`, single Jinja2 template (auto-escaped).
- **Scanner**: Trivy binary copied from the official image to `/app/trivy`.
- **Server**: Gunicorn, 1 worker, 2 threads, `--timeout 0`.
- **Dependencies**: managed with **uv** (`pyproject.toml` + `uv.lock`).
  Pipenv is no longer used.

### Routes
- `GET /` renders the form, the Trivy version and the Pointvy version.
- `GET /scan/?q=<image>[&ignore-unfixed=true]` runs
  `./trivy image --scanners vuln --no-progress [--ignore-unfixed] -- <query>`
  and renders stdout (or stderr as an error). No `q` redirects to `/`.

### Container (`Dockerfile`)
- Multi-stage: Trivy binary from `aquasec/trivy`, app on Alpine Python.
- Non-root user `gunicorn` (UID/GID 1001), home `/var/cache/gunicorn`.
  `/app` is owned by that user, so anything the app runs can write there.
- `uv sync --locked --no-dev`: the build **fails** if `uv.lock` does not
  match `pyproject.toml`. After changing `pyproject.toml` (including the
  project version), always run `cd app && uv lock` and commit the lock file.
- Gunicorn 26+ opens a control socket at
  `/var/cache/gunicorn/.gunicorn/gunicorn.ctl` (mode 0600, owner only).

## Repository Structure

```
.github/
  dependabot.yml              # pip, docker, github-actions; weekly, 7-day cooldown
  workflows/
    build.yml                 # push to main -> pointvy/pointvy:latest
    build-pr.yml              # PR -> build only, no push
    build-tag.yml             # tag v* -> pointvy/pointvy:<version>
    semgrep.yml               # SAST on PR, push to main, daily; blocking (--error)
    scorecards-analysis.yml   # OpenSSF Scorecard, weekly + push to main
app/
  pointvy.py                  # Flask app
  pyproject.toml              # project metadata and dependency ranges
  uv.lock                     # locked dependencies
  templates/main.html         # UI
tests/
  smoke.sh                    # container smoke & security tests (make smoke)
  README.md                   # test catalogue and result codes
Dockerfile, Makefile, README.md, SECURITY.md, SecurityManifesto.md
```

## Security Controls In Place

### Input handling (`app/pointvy.py`)
- **Character filter**: everything except `a-zA-Z0-9 : - . , /` and space is
  stripped from `q`. This is a *strip* filter, not a reject.
- **No shell**: the command is an argv list passed to `subprocess.Popen`
  (no `shell=True`); the query is always a single argument.
- **End of options (`--`)**: `--` is placed before the query. The filter
  allows `-` and `/`, so without it a query like `-c/app/pointvy.py` or
  `--download-db-only` was parsed as a Trivy flag. **Never remove `--`, and
  never append user input after it as more than one argument.**
- **ANSI stripping** on Trivy stdout/stderr before rendering.
- **Template auto-escaping** (Jinja2) for everything rendered.

### Logging
- The raw query is logged with `{query!r}` so CR/LF are escaped and cannot
  forge log lines. Keep `!r` (or equivalent escaping) for any user-controlled
  value written to logs.
- Errors returned to the client are generic (e.g. "The scanner could not be
  started."); details (errno, paths) go to the logs only.

### Supply chain / CI
- Every GitHub Action is pinned by full commit SHA with a `# tag=vX.Y.Z`
  comment. **Keep the comment accurate**; verify a new SHA against the
  upstream tag (`gh api repos/<owner>/<repo>/git/ref/tags/<tag>`).
- Container images used in CI are pinned by digest (Semgrep image).
- Workflows declare least-privilege `permissions:` (the repo default token
  is **write**, so a workflow without a `permissions:` block gets write).
- `actions/checkout` uses `persist-credentials: false`.
- Dependabot has a 7-day cooldown and ignores Python *minor* bumps for the
  base image (3.x -> 3.y, including pre-releases); do those manually.
- Semgrep runs with `--error`, so any finding fails the check.

## Known Gaps

1. **No subprocess timeout on scans**: `Popen(...).communicate()` has no
   timeout and Gunicorn runs with `--timeout 0`; a hanging scan holds one of
   the two threads indefinitely. (`get_trivy_version()` does use a 10 s timeout.)
2. **Strip filter, not allowlist validation**: invalid characters are removed
   rather than rejected; an image reference format check would be stricter.
3. **No rate limiting and no authentication** in the app; rely on the
   platform (Cloud Run IAM, etc.) for production deployments.
4. **Not digest-pinned**: `aquasec/trivy` and `ghcr.io/astral-sh/uv` in the
   `Dockerfile` are pinned by tag only.
5. **Makefile**: `audit` and `lint` reference `app/main.py` (should be
   `app/pointvy.py`); `dockerfile` calls a non-existent `generate-dockerfile.sh`.
6. **No unit tests**: only the container-level `tests/smoke.sh`, which is
   not yet run in CI.

## Testing

`tests/smoke.sh` (or `make smoke`) builds the image, runs it and checks the
HTTP API: build, runtime (uid, versions read from `Dockerfile`/`uv.lock`, no
root), functional (real scans, `ignore-unfixed`, redirect, errors), security
(shell metacharacters, reflected HTML, log forging, Trivy option injection,
oversized query) and robustness (concurrent scans, missing binary).

- Requires Docker, curl and network access; takes a few minutes.
- Options: `SKIP_BUILD=1`, `IMAGE=...`, `PORT=...`, `KEEP=1`.
- Results: `PASS`/`FAIL` (exit 1 on any FAIL), `XFAIL`/`XPASS` for known bugs
  tracked with `known_bug`. See `tests/README.md`.
- **Run it before merging any change to `app/`, the `Dockerfile` or
  dependencies.** Add a check to it for every new input or security fix.

Other local checks:
```bash
pre-commit run --all-files          # file hygiene + yamllint
actionlint                          # workflow files
cd app && uv lock --check           # lock file in sync with pyproject.toml
semgrep scan --config auto --error  # same as CI
```

## Common Tasks

### Updating dependencies
- **Python packages**: edit the range in `app/pyproject.toml`, then
  `cd app && uv lock`. Dependabot pip PRs that only change `pyproject.toml`
  will fail the build; fix them by running `uv lock` on the PR branch and
  pushing the lock file.
- **Trivy**: bump `FROM aquasec/trivy:X.Y.Z`; check the release exists
  upstream; run `make smoke`.
- **Python base image**: bump tag *and* digest together; minor versions are
  manual (Dependabot ignores them).
- **GitHub Actions**: Dependabot; verify SHAs against upstream tags and read
  release notes for major versions (e.g. `actions/checkout` v7 refuses fork
  checkouts under `pull_request_target`/`workflow_run`; none are used here).

### Releasing
1. Bump `POINTVY_VERSION` in `Dockerfile` and `version` in
   `app/pyproject.toml`, then `cd app && uv lock`.
2. Merge to `main` (publishes `latest`).
3. Tag `vX.Y.Z` on the merge commit and push the tag (publishes
   `pointvy/pointvy:X.Y.Z` via `build-tag.yml`).
4. Create a GitHub release "Pointvy X.Y.Z" with notes grouped by
   Security / Python dependencies / Trivy scanner / Base image / GitHub
   Actions / Documentation.

### Adding a Trivy option
1. Validate the new parameter with an allowlist (exact values or a strict
   regex); reject, do not strip.
2. Append it to `cmd` **before** the `"--"` separator.
3. Log it with `!r`.
4. Add `tests/smoke.sh` checks for valid and malicious values.

## Git Workflow
- Never push to `main`; use feature branches (`<type>/<description>`, e.g.
  `fix/...`, `ci/...`, `chore/...`). Avoid a `test/` prefix: a stale
  `origin/test` ref conflicts with it.
- Squash-merge PRs; conventional-commit titles (`fix:`, `chore(deps):`, `ci:`).
- CI on PRs: Docker build, Semgrep (blocking), GitGuardian.

## Security Checklist for Changes
- [ ] User input validated (allowlist) and passed as a single argv element after `--`
- [ ] No `shell=True`; subprocess calls have a timeout where possible
- [ ] Errors shown to users are generic; details only in logs
- [ ] User-controlled values logged with escaping (`!r`)
- [ ] `uv.lock` updated if `pyproject.toml` changed
- [ ] Actions pinned by SHA with an accurate tag comment; workflows have `permissions:`
- [ ] `make smoke`, `pre-commit run --all-files` and Semgrep pass
- [ ] `SecurityManifesto.md` principles respected

## Resources
- Trivy: https://trivy.dev/
- uv: https://docs.astral.sh/uv/
- Flask: https://flask.palletsprojects.com/
- Gunicorn: https://gunicorn.org/
- OpenSSF Scorecard: https://securityscorecards.dev/
- Repository: https://github.com/pointvy/pointvy (security reports: see `SECURITY.md`)
