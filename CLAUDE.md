# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Pointvy is a Flask web interface for Trivy vulnerability scanner, designed for containerized serverless environments (GCP Cloud Run, Scaleway Serverless Containers). The entire application is ~115 lines of Python.

**Tech Stack:** Python 3.13.1, Flask 2.3.3, Gunicorn 23.0.0, Alpine Linux 3.19, Trivy 0.67.0

## Essential Commands

### Development Workflow
```bash
# Build container locally
make build

# Run locally on port 8080
make run-locally

# Deploy to GCP Cloud Run
make deploy

# Security audit (pipenv check + bandit)
make audit

# Python linting
make lint

# Update Pipfile.lock
make lock
```

**Critical:** When running with `docker run`, you MUST use: `-p 8080:8080 -e PORT=8080` (both port mapping AND environment variable required for Gunicorn binding)

### Testing Changes
No automated test suite exists. Manual testing workflow:
1. Build: `make build`
2. Run: `make run-locally`
3. Test at http://localhost:8080 with queries like: `alpine:3.12.1` or `--ignore-unfixed mariadb`

## Application Architecture

### Core Flow
```
User Input (web form)
  → Input Sanitization (regex allowlist: [^a-zA-Z0-9\:\-\.\ \,\/])
  → Subprocess Execution: ./trivy image --scanners vuln --no-progress [OPTIONS] [IMAGE]
  → ANSI Escape Removal (regex: \x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]))
  → HTML Output Display
```

### Flask Routes (`app/pointvy.py`)
- `GET /` - Landing page with form, displays Trivy version
- `GET /scan/` - Executes Trivy scan with sanitized input, handles errors

### Security Controls (Already Implemented)
- **Input Sanitization:** Allowlist regex before subprocess execution
- **ANSI Removal:** Strips color codes to prevent HTML injection
- **Process Isolation:** `subprocess.Popen()` (NOT shell=True)
- **Timeout Protection:** 30 second limit on subprocess execution
- **Non-root Execution:** Container runs as gunicorn:1001 (UID/GID 1001)
- **Error Sanitization:** No system internals exposed in error messages

### Subprocess Execution Details
```python
# Command structure:
./trivy image --scanners vuln --no-progress [--ignore-unfixed] [USER_QUERY]

# Example actual command:
./trivy image --scanners vuln --no-progress --ignore-unfixed alpine:3.12.1
```

## CI/CD Pipeline

### Automated Workflows (.github/workflows/)
**Build Pipeline:**
- `build.yml` - Push to main → DockerHub `pointvy/pointvy:latest`
- `build-pr.yml` - PR validation (build only, no push)
- `build-tag.yml` - Git tags `v*` → DockerHub versioned tags

**Security Pipeline:**
- `security-review.yml` - Claude Code Security Review on PRs
- `claude-code-review.yml` - Claude Code Review (quality, bugs, security)
- `semgrep.yml` - SAST scanning (daily 17:20 UTC + PRs)
- `scorecards-analysis.yml` - OSSF Scorecard (weekly + main pushes)

**Dependency Management:**
- Dependabot: Weekly updates (Fridays 17:00 UTC) for pip, docker, github-actions

### Pre-commit Hooks
- YAML validation, private key detection, large file detection
- Trailing whitespace, end-of-file fixes, symlink validation
- Configured in `.pre-commit-config.yaml`

## Key Files

### Application Code
- `app/pointvy.py` - Main Flask app (115 lines), contains all business logic
- `app/templates/main.html` - Bootstrap 5 web interface
- `app/Pipfile` - Minimal dependencies (Flask ~=2.3.3, gunicorn ~=23.0.0)

### Container Configuration
- `Dockerfile` - Multi-stage build: Trivy base → Alpine Python runtime
- Non-root user setup (gunicorn:1001)
- Entrypoint: `pipenv run gunicorn --bind :${PORT} --workers 1 --threads 2 --timeout 0 pointvy:app`

### Security Documentation
- `SecurityManifesto.md` - Comprehensive security principles (MUST READ before changes)
- `SECURITY.md` - Vulnerability reporting policy
- `.pre-commit-config.yaml` - Local security checks

## Making Changes

### When Modifying Input Handling
1. Check SecurityManifesto.md requirements
2. Update input sanitization regex if needed (currently: `[^a-zA-Z0-9\:\-\.\ \,\/]`)
3. Test command injection scenarios manually
4. Verify ANSI escape removal still works
5. Check subprocess timeout handling

### When Updating Dependencies
```bash
# Update Pipfile, then:
cd app && pipenv lock

# Security audit:
make audit
```

### When Updating Trivy Version
1. Update `FROM aquasec/trivy:X.Y.Z` in Dockerfile
2. Test scanning functionality manually
3. Verify version detection works: check `get_trivy_version()` function

### When Updating Base Images
1. Update `FROM python:X.Y.Z-alpineX.YZ` in Dockerfile
2. Test container build: `make build`
3. Verify non-root execution: `docker run` should show gunicorn:1001 process owner
4. Test scanning: `make run-locally` → http://localhost:8080

## Environment Variables
- `PORT` - Gunicorn binding port (required, default: 8080)
- `TRIVY_VERSION` - Set during build from Dockerfile
- `POINTVY_VERSION` - Application version (currently 1.15.0)

## Deployment Targets
- **GCP Cloud Run:** `make deploy` (requires gcloud auth)
- **Scaleway Serverless:** Manual build + registry push (see README.md)
- **Docker/Kubernetes:** `make build` + standard deployment

## Important Constraints
- **No test suite** - Manual testing required
- **Single Python file** - All logic in `app/pointvy.py`
- **Minimal dependencies** - Only Flask + Gunicorn
- **Internet required** - Container needs direct access for CVE database downloads
- **Security-first** - Read SecurityManifesto.md before ANY code changes
