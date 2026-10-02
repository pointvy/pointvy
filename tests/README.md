# Tests

## Container smoke tests (`smoke.sh`)

Builds the image, runs it, and checks the HTTP API end to end.

```bash
make smoke                          # build + run all checks
SKIP_BUILD=1 IMAGE=pointvy tests/smoke.sh   # reuse an existing image
KEEP=1 tests/smoke.sh               # leave the container running afterwards
```

Requires Docker, curl and network access (Trivy downloads its database and
pulls the scanned images). A full run takes a few minutes.

| Group | IDs | What it checks |
|---|---|---|
| Build | B1–B2 | Image builds with `uv sync --locked`, runs as `gunicorn` |
| Runtime | R1–R5 | App starts; uid 1001; gunicorn/Trivy versions match `uv.lock`/`Dockerfile`; nothing runs as root |
| Functional | F1–F6 | Landing page, real scans, `ignore-unfixed`, redirect, clean errors |
| Security | S1–S6 | Shell metacharacters, reflected HTML, log injection, Trivy option injection (`-c`, `-i`, `-o`, `--help`), oversized query |
| Robustness | X1–X2 | Concurrent scans, missing-binary error path |

### Result codes

- `PASS` / `FAIL`: expected behaviour holds / does not. Any `FAIL` makes the script exit 1.
- `XFAIL`: a known bug that still reproduces (does not fail the run). Use
  `known_bug` in the script to track a bug before it is fixed.
- `XPASS`: a known bug no longer reproduces. Convert that check to a normal `result` test.

No known bugs are currently tracked.
