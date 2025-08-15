# Pointvy - Claude Code Project Instructions

## Project Overview
Pointvy is a secure web interface for Trivy vulnerability scanner execution. It's designed as a Flask application that runs in containerized serverless environments like GCP Cloud Run or Scaleway Serverless Containers.

## Architecture
- **Backend**: Python Flask application (`app/pointvy.py`)
- **Scanner**: Aqua Security Trivy (bundled in container)
- **Frontend**: Simple HTML template (`app/templates/main.html`)
- **Deployment**: Docker container with Alpine Linux base

## Security Features Already Implemented
- Input sanitization with regex filtering for bash safety
- Query length limits (MAX_QUERY_LENGTH = 1000)
- ANSI escape sequence removal
- Subprocess timeout protection (30 seconds)
- Non-root container execution (UID/GID 1001)
- Comprehensive error handling and logging
- BadRequest exception handling for invalid inputs

## Key Files and Structure
```
pointvy/
├── app/
│   ├── pointvy.py              # Main Flask application
│   ├── templates/main.html     # Web interface template
│   ├── Pipfile & Pipfile.lock  # Python dependencies
│   └── pyproject.toml          # Python project config
├── Dockerfile                  # Container build configuration
├── .github/workflows/          # CI/CD pipelines
├── SecurityManifesto.md        # Security development guidelines
└── contrib/                    # Output format templates
```

## Development Guidelines

### Security-First Approach
- Follow the SecurityManifesto.md principles for all code changes
- Validate all external inputs before processing
- Use parameterized queries and safe subprocess execution
- Never expose system internals in error messages
- Maintain comprehensive security logging

### Code Standards
- Use Flask best practices with proper error handling
- Implement timeout protection for external processes
- Sanitize user inputs with allowlist validation
- Follow Python security guidelines (PEP 8, secure coding)

### Testing
- Test input validation thoroughly
- Verify subprocess execution safety
- Check timeout handling
- Validate error message safety (no information disclosure)

### Dependencies
- Keep Trivy scanner updated (currently 0.65.0)
- Maintain Python and Alpine base image updates
- Use Pipenv for dependency management
- Pin all dependency versions for reproducible builds

## Common Tasks

### Adding New Features
1. Implement input validation first
2. Add comprehensive error handling
3. Include security logging
4. Test timeout scenarios
5. Update SecurityManifesto.md if needed

### Security Updates
1. Check for Trivy scanner updates
2. Update base container images
3. Review and update input sanitization
4. Audit subprocess execution patterns

### Container Updates
1. Update FROM statements in Dockerfile
2. Test security scanner functionality
3. Verify non-root execution works
4. Check file permissions and ownership

## Environment Variables
- `PORT`: Application binding port (default: 8080)
- `TRIVY_VERSION`: Trivy scanner version
- `POINTVY_VERSION`: Application version (currently 1.15.0)

## Security Considerations
- Application runs as non-root user (gunicorn:1001)
- Input sanitization prevents command injection
- Subprocess timeouts prevent resource exhaustion
- Error handling prevents information disclosure
- Comprehensive logging for security monitoring

## Deployment Security
- Use secure container registries
- Enable authentication for production deployments
- Monitor resource usage and costs
- Implement proper network security (VPC, firewall rules)
- Set up monitoring and alerting for security events

## When Working on This Project
1. Always prioritize security over convenience
2. Test all input validation thoroughly
3. Never expose internal system details
4. Follow the principle of least privilege
5. Document security decisions in code comments
6. Update security documentation when adding features
