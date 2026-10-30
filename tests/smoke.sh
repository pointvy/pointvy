#!/usr/bin/env bash
#
# Container smoke & security tests for Pointvy.
#
# Builds the image from the repo root, runs it, and exercises the HTTP API
# (/ and /scan/). Each check prints PASS, FAIL, XFAIL (known bug, still
# present) or XPASS (known bug no longer reproduces: update the test).
#
# Usage:  tests/smoke.sh
# Env:    IMAGE=pointvy:smoke  PORT=18080 (and PORT+1)  SKIP_BUILD=1  KEEP=1
# Needs:  docker, curl, network access (Trivy pulls images and its DB).
# Exit:   0 if no FAIL, 1 otherwise.

# Checks deliberately pass a test's $? straight to result().
# shellcheck disable=SC2319

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-pointvy:smoke}"
PORT="${PORT:-18080}"
NAME="pointvy-smoke-$$"
BASE="http://127.0.0.1:${PORT}"
TMP="$(mktemp -d)"
SCAN_TIMEOUT=300

# Expected versions, read from the sources rather than hard-coded.
EXP_TRIVY="$(sed -nE 's/^FROM aquasec\/trivy:([0-9.]+).*/\1/p' "$ROOT/Dockerfile")"
EXP_POINTVY="$(sed -nE 's/^ENV POINTVY_VERSION="([^"]+)"/\1/p' "$ROOT/Dockerfile")"
EXP_GUNICORN="$(awk '/^name = "gunicorn"/{getline; gsub(/[^0-9.]/,""); print; exit}' "$ROOT/app/uv.lock")"

PASS=0 FAIL=0 XFAIL=0 XPASS=0

cleanup() {
    if [ -z "${KEEP:-}" ]; then
        docker rm -f "$NAME" "$NAME-timeout" >/dev/null 2>&1
    else
        echo "KEEP set: container $NAME left running on port $PORT"
    fi
    rm -r "$TMP"
}
trap cleanup EXIT

# --- reporting --------------------------------------------------------------

# result <id> <description> <ok:0|1> [detail]
result() {
    if [ "$3" -eq 0 ]; then
        PASS=$((PASS + 1)); printf '  PASS   %-4s %s\n' "$1" "$2"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL   %-4s %s\n' "$1" "$2"
        [ -n "${4:-}" ] && printf '              -> %s\n' "$4"
    fi
}

# known_bug <id> <description> <reproduced:0|1> [detail]
# 0 = the bug still reproduces (XFAIL); non-zero = it no longer does (XPASS).
known_bug() {
    if [ "$3" -eq 0 ]; then
        XFAIL=$((XFAIL + 1)); printf '  XFAIL  %-4s %s\n' "$1" "$2"
        [ -n "${4:-}" ] && printf '              -> %s\n' "$4"
    else
        XPASS=$((XPASS + 1)); printf '  XPASS  %-4s %s (known bug fixed? update test)\n' "$1" "$2"
    fi
}

section() { printf '\n== %s\n' "$1"; }

# --- helpers ----------------------------------------------------------------

# get <out-file> <path> [curl args...]; prints the HTTP status code.
get() {
    local out="$1" path="$2"; shift 2
    curl -s -o "$out" -w '%{http_code}' --max-time "$SCAN_TIMEOUT" "$@" "${BASE}${path}"
}

# scan <out-file> <query> [extra curl args...]; GET /scan/?q=<query>
scan() {
    local out="$1" q="$2"; shift 2
    get "$out" /scan/ -G --data-urlencode "q=${q}" "$@"
}

in_ctr() { docker exec "$NAME" sh -c "$1"; }

# Jinja2 HTML-escapes output; undo the common entities for grepping.
unescape() { sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&#34;/"/g' -e 's/&#39;/'"'"'/g' -e 's/&amp;/\&/g' "$1"; }

first_total() { unescape "$1" | sed -nE 's/^Total: ([0-9]+).*/\1/p' | head -1; }

# --- 1. build ---------------------------------------------------------------

section "1. Build ($IMAGE)"
if [ -z "${SKIP_BUILD:-}" ]; then
    if docker build -q -t "$IMAGE" "$ROOT" >"$TMP/build.log" 2>&1; then
        result B1 "image builds (uv sync --locked)" 0
    else
        result B1 "image builds (uv sync --locked)" 1 "$(tail -3 "$TMP/build.log")"
        exit 1
    fi
else
    echo "  (SKIP_BUILD set, using existing $IMAGE)"
fi
user="$(docker image inspect "$IMAGE" --format '{{.Config.User}}')"
[ "$user" = "gunicorn" ]; result B2 "image USER is gunicorn" $? "got '$user'"

# --- 2. runtime -------------------------------------------------------------

section "2. Runtime"
docker run -d --name "$NAME" -e PORT=8080 -p "${PORT}:8080" "$IMAGE" >/dev/null
up=1
for _ in $(seq 1 30); do
    [ "$(get /dev/null /)" = "200" ] && { up=0; break; }
    sleep 1
done
result R1 "container serves HTTP within 30s" $up
[ $up -ne 0 ] && { docker logs "$NAME" 2>&1 | tail -20; exit 1; }

uid="$(in_ctr 'id -u')"
[ "$uid" = "1001" ]; result R2 "process runs as uid 1001" $? "got uid $uid"

got="$(in_ctr 'cd /app && uv run --no-sync python -c "import gunicorn; print(gunicorn.__version__)"')"
[ "$got" = "$EXP_GUNICORN" ]; result R3 "gunicorn is $EXP_GUNICORN (from uv.lock)" $? "got $got"

got="$(in_ctr '/app/trivy --version' | sed -nE 's/^Version: //p')"
[ "$got" = "$EXP_TRIVY" ]; result R4 "trivy is $EXP_TRIVY (from Dockerfile)" $? "got $got"

roots="$(in_ctr 'ps -o user | grep -cx root')"
[ "$roots" = "0" ]; result R5 "no process runs as root" $? "$roots root process(es)"

# --- 3. functional ----------------------------------------------------------

section "3. Functional"
code="$(get "$TMP/f1" /)"
[ "$code" = "200" ] && grep -q "Trivy version: $EXP_TRIVY" "$TMP/f1" && grep -q "Pointvy version: $EXP_POINTVY" "$TMP/f1"
result F1 "GET / shows Trivy $EXP_TRIVY / Pointvy $EXP_POINTVY" $? "HTTP $code"

code="$(scan "$TMP/f2" alpine:latest)"
[ "$code" = "200" ] && grep -q 'alpine:latest (alpine ' "$TMP/f2"
result F2 "scan alpine:latest returns a report" $? "HTTP $code"

code="$(scan "$TMP/f3" python:3.9-slim)"
t_all="$(first_total "$TMP/f3")"
[ "$code" = "200" ] && [ -n "$t_all" ]
result F3 "scan python:3.9-slim returns vulnerability totals" $? "HTTP $code, Total='$t_all'"

code="$(scan "$TMP/f4" python:3.9-slim --data-urlencode ignore-unfixed=true)"
t_fixed="$(first_total "$TMP/f4")"
[ "$code" = "200" ] && grep -q 'value="true" checked' "$TMP/f4" \
    && [ -n "$t_fixed" ] && [ -n "$t_all" ] && [ "$t_fixed" -le "$t_all" ]
result F4 "ignore-unfixed is honoured (Total $t_fixed <= $t_all)" $? "HTTP $code"

code="$(get /dev/null /scan/)"
[ "$code" = "302" ]; result F5 "/scan/ without q redirects" $? "HTTP $code"

code="$(scan "$TMP/f6" doesnotexist/nope:0)"
[ "$code" = "200" ] && grep -q 'alert-warning' "$TMP/f6" && ! grep -q 'Traceback' "$TMP/f6"
result F6 "unknown image gives a clean error" $? "HTTP $code"

# Every character is filtered out: rejected without running Trivy.
code="$(scan "$TMP/f7" '<>;|')"
[ "$code" = "200" ] && grep -q 'does not contain a valid image reference' "$TMP/f7"
result F7 "query that filters to nothing is rejected" $? "HTTP $code"

# --- 4. security ------------------------------------------------------------

section "4. Security"
s1=0
for q in 'alpine;id' 'alpine$(id)' 'alpine|id' 'alpine`id`' 'alpine&&id'; do
    code="$(scan "$TMP/s1" "$q")"
    if [ "$code" != "200" ] || unescape "$TMP/s1" | grep -q 'uid=[0-9]'; then
        s1=1; echo "              -> payload '$q' HTTP $code"
    fi
done
result S1 "shell metacharacters are not executed" $s1

scan "$TMP/s2" '<script>alert(1)</script>' >/dev/null
! grep -q '<script>alert' "$TMP/s2"; result S2 "query is not reflected as raw HTML" $?

marker="FORGED-$$"
scan /dev/null "alpine
${marker} - INFO - forged entry" >/dev/null
sleep 1
! docker logs "$NAME" 2>&1 | grep -q "^${marker}"
result S3 "newline in query cannot forge a log line" $? "a log line starts with '$marker'"

# Option injection: the filter keeps '-' and '/', so a query starting with
# '-' reaches Trivy as a flag rather than an image reference.
code="$(scan "$TMP/s4a" --help)"
! unescape "$TMP/s4a" | grep -q 'Usage:'
result S4a "query '--help' is not parsed as a Trivy flag" $? "Trivy printed its usage text"

scan "$TMP/s4b" -c/app/pointvy.py >/dev/null
! unescape "$TMP/s4b" | grep -qE 'bash_escape|import subprocess'
result S4b "'-c<file>' does not disclose local file content" $?

scan "$TMP/s4c" -i/etc/passwd >/dev/null
! unescape "$TMP/s4c" | grep -q 'root:x:0:0'
result S4c "'-i<file>' does not disclose local file content" $?

before="$(in_ctr 'sha256sum /app/templates/main.html')"
scan /dev/null -o/app/templates/main.html >/dev/null
scan /dev/null -o/tmp/smoke-written >/dev/null
after="$(in_ctr 'sha256sum /app/templates/main.html')"
written="$(in_ctr 'test -e /tmp/smoke-written && echo yes || echo no')"
[ "$before" = "$after" ] && [ "$written" = "no" ]
result S5 "'-o<path>' cannot write files in the container" $? "template changed or /tmp/smoke-written=$written"

long="$(head -c 10000 /dev/zero | tr '\0' a)"
code="$(scan /dev/null "$long")"
alive="$(get /dev/null /)"
case "$code" in 200|400|414) ok=0 ;; *) ok=1 ;; esac
[ $ok -eq 0 ] && [ "$alive" = "200" ]
result S6 "10k-char query is handled, app stays up" $? "HTTP $code, then / -> $alive"

# Spaces survive the filter: options after one must stay inside the single
# image-reference argument.
scan "$TMP/s7a" 'alpine:latest --help' >/dev/null
scan /dev/null 'alpine:latest -o/tmp/smoke-space' >/dev/null
written="$(in_ctr 'test -e /tmp/smoke-space && echo yes || echo no')"
! unescape "$TMP/s7a" | grep -q 'Usage:' && [ "$written" = "no" ]
result S7 "options after a space in the query are not parsed" $? "usage shown or /tmp/smoke-space=$written"

code="$(scan "$TMP/s8" alpine:latest --data-urlencode 'ignore-unfixed=true --debug')"
[ "$code" = "200" ] && ! grep -q 'value="true" checked' "$TMP/s8" && grep -q 'alpine:latest (alpine ' "$TMP/s8"
result S8 "ignore-unfixed accepts only the exact value 'true'" $? "HTTP $code"

code="$(get "$TMP/s9" '/scan/?q=alpine:latest&q=--help')"
[ "$code" = "200" ] && ! unescape "$TMP/s9" | grep -q 'Usage:' && grep -q 'alpine:latest (alpine ' "$TMP/s9"
result S9 "a second q parameter is ignored" $? "HTTP $code"

# --- 5. HTTP surface ----------------------------------------------------------

section "5. HTTP"
code="$(get /dev/null /scan/ -X POST -d q=alpine)"
[ "$code" = "405" ]; result H1 "POST /scan/ is rejected" $? "HTTP $code"

code="$(get /dev/null '/scan?q=alpine')"
[ "$code" = "308" ]; result H2 "/scan redirects to /scan/" $? "HTTP $code"

code="$(get /dev/null /console)"
[ "$code" = "404" ]; result H3 "no debugger console (/console is 404)" $? "HTTP $code"

curl -s -o /dev/null -D "$TMP/h4" --max-time 30 "${BASE}/"
missing=""
for h in Content-Security-Policy X-Content-Type-Options X-Frame-Options Referrer-Policy; do
    grep -qi "^$h:" "$TMP/h4" || missing="$missing $h"
done
[ -n "$missing" ]; known_bug H4 "security headers missing" $? "missing:$missing"

# --- 6. known image-reference bugs ------------------------------------------
# The filter strips '@' and '_', both valid in image references. The
# reflected query in the form shows what was actually passed to Trivy.

section "6. Image references"
scan "$TMP/k1" "alpine@sha256:$(printf '0%.0s' $(seq 64))" >/dev/null
! grep -q 'value="alpine@sha256:' "$TMP/k1"
known_bug K1 "digest reference loses its '@'" $?

scan "$TMP/k2" 'my_org/my_image:1_0' >/dev/null
! grep -q 'value="my_org/my_image:1_0"' "$TMP/k2"
known_bug K2 "reference loses its '_'" $?

# --- 7. robustness ----------------------------------------------------------

section "7. Robustness"
for i in 1 2 3; do
    ( scan /dev/null alpine:latest >"$TMP/x1.$i" ) &
done
wait
x1=0
for i in 1 2 3; do [ "$(cat "$TMP/x1.$i")" = "200" ] || x1=1; done
result X1 "3 concurrent scans all succeed (2 threads)" $x1 "codes: $(cat "$TMP"/x1.* | tr '\n' ' ')"

# Missing binary exercises the OSError branch.
in_ctr 'mv /app/trivy /app/trivy.smoke'
code="$(scan "$TMP/x2" alpine:latest)"
in_ctr 'mv /app/trivy.smoke /app/trivy'
[ "$code" = "200" ] && grep -q 'could not be started' "$TMP/x2" && ! grep -qE 'Errno|/app/' "$TMP/x2"
result X2 "missing scanner gives a generic error, no 500" $? "HTTP $code"

# A scanner that never returns, in a second container with SCAN_TIMEOUT=5:
# hung scans must be killed (with the shell's child, hence a non-exec
# script) and the app must keep answering.
T_NAME="${NAME}-timeout"
T_BASE="http://127.0.0.1:$((PORT + 1))"
docker run -d --name "$T_NAME" -e PORT=8080 -e SCAN_TIMEOUT=5 -p "$((PORT + 1)):8080" "$IMAGE" >/dev/null
for _ in $(seq 1 30); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "${T_BASE}/")" = "200" ] && break
    sleep 1
done
docker exec "$T_NAME" sh -c 'mv /app/trivy /app/trivy.real && printf "#!/bin/sh\nsleep 600\n" >/app/trivy && chmod +x /app/trivy'
for i in 1 2; do
    ( curl -s -o "$TMP/x3.$i" -w '%{http_code} %{time_total}' --max-time 60 "${T_BASE}/scan/?q=alpine" >"$TMP/x3.$i.code" ) &
done
sleep 1
# GET / waits for a free thread, then ~10s for its own version check.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 40 "${T_BASE}/")"
wait
x3=0
for i in 1 2; do
    read -r c t <"$TMP/x3.$i.code"
    { [ "$c" = "200" ] && grep -q 'The scan timed out.' "$TMP/x3.$i" && [ "${t%.*}" -lt 30 ]; } || x3=1
done
result X3 "hung scans are killed after SCAN_TIMEOUT with a generic error" $x3 "$(cat "$TMP"/x3.*.code | tr '\n' ' ')"
[ "$code" = "200" ]; result X4 "app keeps answering while scans hang" $? "GET / -> HTTP $code"
docker rm -f "$T_NAME" >/dev/null

# --- 8. shutdown --------------------------------------------------------------
# Cloud Run and Docker send SIGTERM, then SIGKILL after a grace period.

if [ -z "${KEEP:-}" ]; then
    section "8. Shutdown"
    start="$(date +%s)"
    docker stop -t 10 "$NAME" >/dev/null
    elapsed=$(( $(date +%s) - start ))
    [ "$elapsed" -lt 8 ]; result R6 "container stops on SIGTERM before the 10s kill" $? "took ${elapsed}s"
fi

# --- summary ----------------------------------------------------------------

printf '\n== Summary: %d pass, %d fail, %d xfail, %d xpass\n' "$PASS" "$FAIL" "$XFAIL" "$XPASS"
[ "$FAIL" -eq 0 ]
