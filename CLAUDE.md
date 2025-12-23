# Pointvy - Claude Code Project Instructions

## Project Overview
Pointvy is a secure web interface for Trivy vulnerability scanner execution. It's designed as a Flask application that runs in containerized serverless environments like GCP Cloud Run or Scaleway Serverless Containers.

**Current Version**: 1.15.0
**Repository Size**: ~842 KB
**Primary Language**: Python 3.13.1
**Container Base**: Alpine Linux 3.19
**Trivy Scanner**: 0.68.1

## Architecture

### Core Components
- **Backend**: Python Flask application (`app/pointvy.py`) - 114 lines
- **Scanner**: Aqua Security Trivy 0.68.1 (bundled in container)
- **Frontend**: Simple HTML template (`app/templates/main.html`) - 65 lines
- **Deployment**: Docker container with Alpine Linux base
- **Server**: Gunicorn (1 worker, 2 threads, no timeout)

### Technology Stack
- **Python**: 3.13.1 (Alpine 3.19 base)
- **Flask**: 2.3.3
- **Werkzeug**: 3.1.4
- **Gunicorn**: ~23.0.0
- **Jinja2**: 3.1.6
- **Pipenv**: 2024.1.0 for dependency management
- **Pip**: 24.2

## Repository Structure

```
pointvy/
├── .github/
│   └── workflows/              # 9 CI/CD workflow files
│       ├── build.yml              # Build & push on main (latest tag)
│       ├── build-pr.yml           # PR build verification
│       ├── build-tag.yml          # Tagged release builds
│       ├── security-review.yml    # Claude Code security review
│       ├── claude-code-review.yml # Claude PR review
│       ├── claude.yml             # Claude Code execution (@claude)
│       ├── semgrep.yml            # SAST scanning
│       ├── scorecards-analysis.yml# OpenSSF supply chain security
│       └── dependabot.yml         # Dependency updates config
├── app/
│   ├── pointvy.py              # Main Flask application (114 lines)
│   ├── Pipfile                 # Python dependency manifest
│   ├── Pipfile.lock            # Locked dependencies (9 packages)
│   └── templates/
│       └── main.html           # Web interface (65 lines)
├── img/
│   └── pointvy-screenshot.png  # Documentation screenshot
├── .dockerignore               # Docker build exclusions
├── .gitignore                  # Python-specific ignores
├── .pre-commit-config.yaml     # Pre-commit hooks config
├── .yamllint                   # YAML linting rules
├── Dockerfile                  # Alpine-based container (40 lines)
├── Makefile                    # Build, deploy, audit targets
├── LICENSE                     # Project license
├── README.md                   # Comprehensive user documentation
├── CLAUDE.md                   # This file - AI assistant instructions
├── SECURITY.md                 # Security policy
└── SecurityManifesto.md        # Security development guidelines
```

## Security Features Already Implemented

### Input Validation & Sanitization
- Regex filtering for bash safety: `[^a-zA-Z0-9\:\-\.\ \,\/]` (`app/pointvy.py:60`)
- Query length limits (enforced at HTTP level)
- ANSI escape sequence removal (`app/pointvy.py:75,96`)
- Blocklist approach for special character filtering

### Process & Runtime Security
- Non-root container execution (UID/GID 1001, user: gunicorn)
- Subprocess execution with Popen (`app/pointvy.py:79`)
- ⚠️ **Note**: No timeout on subprocess execution (security consideration)
- Comprehensive error handling and logging
- BadRequest exception handling for invalid inputs

### Container Security
- Alpine Linux base (minimal attack surface)
- Multi-stage build (Trivy extracted from official image)
- Non-root user created before app files copied
- Proper file permissions and ownership
- No unnecessary packages installed

### CI/CD Security
- Semgrep SAST scanning (daily + on PR/main push)
- OpenSSF Scorecard analysis (weekly)
- Claude Code security review on PRs
- Dependabot automated security updates
- Pre-commit hooks for code quality

## Application Details

### Flask Application (`app/pointvy.py`)

**Routes**:
- `/` - Landing page with scan form
- `/scan/` - Trivy execution endpoint

**Key Functions**:
- `get_trivy_version()` - Retrieves Trivy version with timeout (10s) and error handling
- `landing()` - Renders main template with form
- `trivy_scan()` - Processes scan requests with input sanitization

**Security Implementation**:
```python
# Input sanitization (line 60)
bash_escape = re.compile(r'[^a-zA-Z0-9\:\-\.\ \,\/]')
query_sanitized = bash_escape.sub('', query)

# ANSI escape removal (line 75, 96)
ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

# Subprocess execution (line 79)
res = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
```

**Logging**:
- INFO level for successful scans
- ERROR level for failures and exceptions
- All queries logged for security monitoring

### Docker Configuration (`Dockerfile`)

**Multi-stage Build**:
1. **Stage 1**: Extract Trivy binary from `aquasec/trivy:0.68.1`
2. **Stage 2**: Alpine Python base with application setup

**Key Configuration**:
```dockerfile
FROM aquasec/trivy:0.68.1 AS base
FROM python:3.13.1-alpine3.19

ENV PYTHONUNBUFFERED="True"
ENV PORT="8080"
ENV POINTVY_VERSION="1.15.0"

# Non-root user setup
RUN addgroup -g 1001 -S gunicorn; \
    adduser -S -D -H -u 1001 -h /var/cache/gunicorn -G gunicorn gunicorn

USER gunicorn

# Server command
CMD pipenv run gunicorn --bind :${PORT} --workers 1 --threads 2 --timeout 0 pointvy:app
```

## CI/CD Pipelines

### Build Workflows

| Workflow | Trigger | Purpose | Outputs |
|----------|---------|---------|---------|
| **build.yml** | Push to `main` | Production build | `pointvy/pointvy:latest` on DockerHub |
| **build-pr.yml** | PR to `main` | Build verification | Build only, no push |
| **build-tag.yml** | Git tag `v*` | Release build | `pointvy/pointvy:<version>` on DockerHub |

**Build Features**:
- Docker Buildx with QEMU support (multi-arch capability)
- SHA256-pinned GitHub Actions
- DockerHub authentication via secrets
- Provenance disabled (Cloud Run multi-arch workaround)

### Security & Analysis Workflows

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| **security-review.yml** | On PR | Claude Code security review |
| **claude-code-review.yml** | On PR | Claude PR review with custom prompt |
| **claude.yml** | @claude mention | Claude Code execution trigger |
| **semgrep.yml** | Daily + PR/Push | SAST scanning |
| **scorecards-analysis.yml** | Weekly | OpenSSF supply chain security |

**Permissions Model**:
- Minimal read-only defaults
- Specific write permissions for security review PRs
- ID token for OIDC workflows

### Dependency Management

**Dependabot Configuration**:
- **Schedule**: Weekly on Friday at 17:00 UTC
- **Ecosystems**:
  - `pip` (directory: `/app`)
  - `docker` (directory: `/`)
  - `github-actions` (directory: `/.github/workflows`)
- **Auto-merge**: Not configured
- **Versioning**: Semantic versioning strategy

## Development Workflows

### Pre-commit Hooks (`.pre-commit-config.yaml`)

**Enabled Hooks**:
1. **pre-commit/pre-commit-hooks** (v4.1.0):
   - YAML validation
   - File formatting checks
   - Large file detection
   - Private key detection
   - Merge conflict checking
   - Trailing whitespace removal

2. **yamllint** (v1.26.3):
   - YAML linting with custom config (`.yamllint`)
   - Enforces consistent YAML formatting

**Setup**:
```bash
pip install pre-commit
pre-commit install
```

### Makefile Targets

| Target | Command | Purpose |
|--------|---------|---------|
| `build` | `docker build . -t pointvy` | Build Docker image locally |
| `run-locally` | `docker run -e PORT=8080 -p 8080:8080 pointvy` | Run container locally |
| `deploy` | `gcloud run deploy pointvy --source .` | Deploy to GCP Cloud Run |
| `audit` | `pipenv check + bandit` | Security audit |
| `lock` | `pipenv lock` | Update Pipfile.lock |
| `lint` | `flake8 app/main.py` | Lint Python code |
| `dockerfile` | `./generate-dockerfile.sh` | Generate Dockerfile |

⚠️ **Known Issues**:
- `audit` and `lint` targets reference `app/main.py` but actual file is `app/pointvy.py`
- `dockerfile` target references non-existent `generate-dockerfile.sh` script

### Git Branch Strategy

**Branch Naming Convention**:
- Feature branches: `claude/<feature-description>-<session-id>`
- Example: `claude/add-claude-documentation-x7KPJ`

**Git Operations**:
- Always push to feature branches (not `main`)
- Use `git push -u origin <branch-name>`
- Retry network failures up to 4 times with exponential backoff (2s, 4s, 8s, 16s)
- Create PRs against main branch when ready

### Testing

⚠️ **CRITICAL GAP**: No automated test suite exists
- No pytest configuration
- No unittest files
- No test coverage tools
- No integration tests

**Testing Requirements for New Code**:
- Manual testing required for all changes
- Test input validation thoroughly
- Verify subprocess execution safety
- Check timeout handling
- Validate error message safety (no information disclosure)
- Test with malicious inputs (XSS, command injection attempts)

## Development Guidelines

### Security-First Approach
1. **Follow SecurityManifesto.md** - 10 core security principles
2. **Validate ALL external inputs** before processing
3. **Use safe subprocess execution** with timeouts when possible
4. **Never expose system internals** in error messages
5. **Maintain comprehensive security logging**
6. **Apply principle of least privilege**
7. **Prefer allowlists over blocklists** for input validation

### Code Standards
- **PEP 8** compliance for Python code
- **Flask best practices** with proper error handling
- **Timeout protection** for external processes
- **Sanitize user inputs** with regex validation
- **Logging** at appropriate levels (INFO for success, ERROR for failures)
- **Type hints** where applicable (not currently used)
- **Docstrings** for functions (not currently implemented)

### Security Checklist for Changes

Before committing code, verify:
- [ ] All user inputs validated with allowlist approach
- [ ] No command injection vulnerabilities
- [ ] No path traversal vulnerabilities
- [ ] Subprocess calls use timeouts
- [ ] Error messages don't leak system information
- [ ] Security-relevant actions logged
- [ ] No secrets in code or config files
- [ ] Dependencies pinned to specific versions
- [ ] Pre-commit hooks pass
- [ ] Semgrep scan passes (run locally: `semgrep --config=auto .`)

### Common Security Pitfalls to Avoid

1. **Command Injection**: Never use `shell=True` with subprocess
2. **ANSI Injection**: Always strip ANSI codes from untrusted output
3. **Path Traversal**: Validate file paths if added
4. **Information Disclosure**: Generic error messages only
5. **DoS via Timeout**: Add timeouts to ALL subprocess calls
6. **Log Injection**: Sanitize data before logging
7. **XSS**: Flask auto-escapes templates, but verify custom outputs

## Common Tasks

### Adding New Features

**Process**:
1. **Read SecurityManifesto.md** - Understand security requirements
2. **Implement input validation FIRST** - Allowlist approach
3. **Add comprehensive error handling** - No information leakage
4. **Include security logging** - Log security-relevant events
5. **Test timeout scenarios** - Prevent resource exhaustion
6. **Manual testing** - No automated tests exist
7. **Update documentation** - SecurityManifesto.md, CLAUDE.md, README.md
8. **Create PR** - Security review will run automatically

**Example: Adding a new Trivy option**:
```python
# 1. Add input validation
option_value = request.args.get("new_option")
if option_value and not re.match(r'^[a-zA-Z0-9\-]+$', option_value):
    app.logger.error(f"Invalid option value: {option_value}")
    return error_response()

# 2. Add to command safely
if option_value:
    cmd.extend(["--new-option", option_value])
    app.logger.info(f"Using new option: {option_value}")

# 3. Add error handling
try:
    # ... execution ...
except Exception as e:
    app.logger.error(f"New option failed: {str(e)}")
    return error_response()
```

### Updating Dependencies

**Python Dependencies** (`app/Pipfile`):
```bash
cd app
pipenv update <package>  # Update specific package
pipenv update           # Update all packages
pipenv lock             # Generate new lock file
```

**Trivy Scanner**:
1. Update `FROM aquasec/trivy:X.Y.Z` in `Dockerfile:1`
2. Test scan functionality
3. Update version references in documentation

**Base Container Images**:
1. Update `FROM python:X.Y.Z-alpineX.YZ` in `Dockerfile:3`
2. Test application startup
3. Verify all dependencies still work
4. Check for breaking changes

**GitHub Actions**:
- Dependabot handles automatically
- Review and merge Dependabot PRs weekly

### Security Updates

**Process**:
1. **Check for Trivy updates** - Visit https://github.com/aquasecurity/trivy/releases
2. **Update base images** - Check Alpine and Python releases
3. **Review input sanitization** - Ensure regex patterns are comprehensive
4. **Audit subprocess execution** - Verify timeouts and safe execution
5. **Run security scans** - Semgrep, Scorecard
6. **Review dependencies** - `pipenv check`, Dependabot alerts
7. **Update SecurityManifesto.md** - Document new security measures

**Security Tools**:
```bash
# Local security scanning
semgrep --config=auto .
pipenv check
bandit app/pointvy.py
```

### Container Updates

**Process**:
1. Update `FROM` statements in `Dockerfile`
2. Test build: `make build`
3. Test locally: `make run-locally`
4. Verify scanner works: Visit http://localhost:8080
5. Test scan: Try scanning `alpine:latest`
6. Verify non-root execution: Check container user
7. Check file permissions: Ensure gunicorn owns files
8. Commit and push: Security workflows run automatically

### Fixing the Makefile Bug

⚠️ **Known Issue**: Makefile references `app/main.py` (doesn't exist)
**Actual File**: `app/pointvy.py`

**Fix Required**:
```makefile
# Line 16 - Change from:
bandit app/main.py

# To:
bandit app/pointvy.py

# Line 24 - Change from:
flake8 app/main.py

# To:
flake8 app/pointvy.py
```

## Environment Variables

### Runtime Variables
- `PORT`: Application binding port (default: `8080`)
- `TRIVY_VERSION`: Trivy scanner version (read-only, set in Dockerfile)
- `POINTVY_VERSION`: Application version (read-only, currently `1.15.0`)
- `PYTHONUNBUFFERED`: Force unbuffered output (set to `True`)

### Build-time Variables
- `APP_HOME`: Application directory (`/app`)
- `USER_HOME`: Gunicorn cache directory (`/var/cache/gunicorn`)
- `UID`: User ID for non-root execution (`1001`)
- `GID`: Group ID for non-root execution (`1001`)
- `PENV_VERSION`: Pipenv version (`2024.1.0`)
- `PIP_VERSION`: Pip version (`24.2`)

### Deployment Variables (GCP Cloud Run)
- `DOCKERHUB_USERNAME`: DockerHub username (secret)
- `DOCKERHUB_TOKEN`: DockerHub access token (secret)

## Security Considerations

### Current Security Measures
- **Non-root execution**: Application runs as `gunicorn:1001`
- **Input sanitization**: Regex blocklist for special characters
- **ANSI stripping**: Prevents terminal injection attacks
- **Process isolation**: Container-based deployment
- **Minimal attack surface**: Alpine Linux base, minimal packages
- **Security logging**: Comprehensive logging at INFO/ERROR levels
- **Error handling**: Generic error messages prevent information disclosure

### Known Security Gaps

1. **No Subprocess Timeout** (`app/pointvy.py:79`):
   - Subprocess.Popen called without timeout
   - Could lead to resource exhaustion
   - **Recommendation**: Add timeout parameter or use `subprocess.run()` with timeout

2. **Blocklist Input Validation**:
   - Current approach removes bad characters
   - **Recommendation**: Use allowlist approach (define what's allowed)

3. **No Rate Limiting**:
   - No protection against DoS via repeated scans
   - **Recommendation**: Add rate limiting middleware

4. **No Authentication**:
   - Web interface is publicly accessible
   - **Recommendation**: Add authentication for production deployments

5. **No Test Coverage**:
   - No automated security testing
   - **Recommendation**: Add pytest with security test cases

### Security Best Practices

**For Production Deployments**:
1. **Enable Authentication**: Use Cloud Run IAM, API keys, or OAuth
2. **Configure Rate Limiting**: Prevent abuse and resource exhaustion
3. **Set up Monitoring**: Alert on suspicious patterns, errors, high usage
4. **Use Private Networks**: VPC, firewall rules, service mesh
5. **Enable Audit Logging**: Track all access and scan requests
6. **Set Resource Limits**: CPU, memory, request timeout limits
7. **Regular Security Updates**: Weekly dependency updates, monthly security reviews
8. **Vulnerability Scanning**: Regular container and dependency scans

## Deployment

### Local Development
```bash
# Build container
make build

# Run locally
make run-locally

# Access at http://localhost:8080
# Test with: alpine:latest
```

### GCP Cloud Run
```bash
# Deploy (requires gcloud CLI)
make deploy

# Or manually:
gcloud run deploy pointvy \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated  # Add authentication for production!
```

### Docker Hub
```bash
# Pull latest image
docker pull pointvy/pointvy:latest

# Run container
docker run -e PORT=8080 -p 8080:8080 pointvy/pointvy:latest
```

### Scaleway Serverless Containers
- Use `pointvy/pointvy:latest` from DockerHub
- Set port to 8080
- Configure min/max instances
- Add authentication
- Enable custom domain (optional)

## Documentation Files

### README.md
- User-facing documentation
- Deployment guides (GCP, Scaleway, Docker)
- Usage examples with Trivy options
- Contributing guidelines
- Project disclaimer

### CLAUDE.md (This File)
- AI assistant instructions
- Codebase structure and conventions
- Development workflows
- Security guidelines
- Common tasks and procedures

### SecurityManifesto.md
- 10 core security principles
- Technology-specific security requirements
- Secure coding guidelines
- Security testing requirements
- Compliance considerations

### SECURITY.md
- Security policy
- Supported versions
- Vulnerability reporting

## When Working on This Project

### Core Principles
1. **Security ALWAYS comes first** - No exceptions
2. **Test input validation thoroughly** - Assume all input is malicious
3. **Never expose internal details** - Generic error messages only
4. **Follow least privilege** - Minimal permissions, non-root execution
5. **Document security decisions** - Explain security choices in comments
6. **Update documentation** - Keep CLAUDE.md, SecurityManifesto.md current

### Before Making Changes
1. **Read the relevant code** - Understand existing patterns
2. **Check SecurityManifesto.md** - Ensure compliance
3. **Review recent commits** - Understand recent changes
4. **Create feature branch** - Use `claude/<description>-<session-id>` format

### During Development
1. **Input validation first** - Implement before functionality
2. **Add error handling** - Comprehensive exception handling
3. **Include logging** - Security-relevant events
4. **Test manually** - No automated tests exist
5. **Run pre-commit hooks** - `pre-commit run --all-files`
6. **Run security scans** - Semgrep, bandit locally

### Before Committing
1. **Security checklist** - Review all items above
2. **Code review** - Self-review for security issues
3. **Test edge cases** - Malicious inputs, timeouts, errors
4. **Update docs** - If adding features or changing behavior
5. **Clear commit messages** - Explain what and why

### After Pushing
1. **Monitor CI/CD** - Ensure all workflows pass
2. **Review security findings** - Address Semgrep/Claude findings
3. **Create PR** - Against main branch
4. **Respond to reviews** - Address feedback promptly

## Claude Code Integration

### Workflows Using Claude

1. **security-review.yml**: Automated security review on PRs
2. **claude-code-review.yml**: General PR review with custom prompt
3. **claude.yml**: Manual Claude execution via @claude mentions

### Working with Claude Code

**Triggering Reviews**:
- PRs automatically trigger security and code reviews
- Mention @claude in PR comments for ad-hoc assistance
- Claude follows SecurityManifesto.md principles

**Review Focus Areas**:
- Input validation implementation
- Subprocess execution safety
- Error handling completeness
- Information disclosure risks
- Security logging coverage
- Dependency security

## Known Issues & Limitations

### Code Issues
1. **Makefile Bug**: References `app/main.py` instead of `app/pointvy.py` (lines 16, 24)
2. **No Subprocess Timeout**: `subprocess.Popen()` without timeout (`app/pointvy.py:79`)
3. **Blocklist Validation**: Should use allowlist approach instead

### Missing Features
1. **No Automated Tests**: No pytest, unittest, or integration tests
2. **No Test Coverage**: No coverage reports or requirements
3. **No Type Hints**: Python code lacks type annotations
4. **No Docstrings**: Functions lack documentation strings
5. **No Rate Limiting**: No DoS protection
6. **No Authentication**: Public access by default

### Documentation Gaps
1. **No API Documentation**: No formal API spec
2. **No Architecture Diagrams**: Visual documentation missing
3. **No Deployment Examples**: Limited deployment scenarios documented

### Recommendations for Improvement
1. **Add pytest test suite** - Start with input validation tests
2. **Fix Makefile** - Update file references
3. **Add subprocess timeout** - Prevent resource exhaustion
4. **Switch to allowlist validation** - More secure approach
5. **Add type hints** - Better code clarity and IDE support
6. **Add docstrings** - Improve code documentation
7. **Implement rate limiting** - Prevent abuse
8. **Add authentication** - Secure production deployments

## Version History

- **1.15.0** (Current): Latest stable release
- **Base Images**:
  - Python 3.13.1 on Alpine 3.19
  - Trivy 0.68.1
  - Pipenv 2024.1.0

## Additional Resources

- **Trivy Documentation**: https://aquasecurity.github.io/trivy/
- **Flask Documentation**: https://flask.palletsprojects.com/
- **Gunicorn Documentation**: https://gunicorn.org/
- **Alpine Linux**: https://alpinelinux.org/
- **OpenSSF Scorecard**: https://securityscorecards.dev/
- **Semgrep Rules**: https://semgrep.dev/explore

## Contact & Support

- **Repository**: https://github.com/pointvy/pointvy
- **Issues**: Report bugs and security issues via GitHub Issues
- **Security**: Follow SECURITY.md for vulnerability disclosure
- **Contributing**: See README.md for contribution guidelines

---

**Last Updated**: 2025-12-23
**Trivy Version**: 0.68.1
**Pointvy Version**: 1.15.0
**Documentation Version**: 2.0
