FROM aquasec/trivy:0.71.0 AS base

FROM python:3.14.3-alpine3.23@sha256:faee120f7885a06fcc9677922331391fa690d911c020abb9e8025ff3d908e510

ENV PYTHONUNBUFFERED="True"
ENV APP_HOME="/app"
ENV USER_HOME="/var/cache/gunicorn"
ENV UID="1001"
ENV GID="1001"
ENV PORT="8080"
ENV UV_VERSION="0.10.10"
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV POINTVY_VERSION="1.17.0"

SHELL ["/bin/sh", "-eo", "pipefail", "-c"]

WORKDIR ${APP_HOME}
COPY app/pyproject.toml .
COPY app/uv.lock .

COPY --from=base /usr/local/bin/trivy ${APP_HOME}/
COPY --from=ghcr.io/astral-sh/uv:0.10.10 /uv /usr/local/bin/uv

# pinning the curl version is non-relevant as Alpine already fixes it
# hadolint ignore=DL3018
RUN set -eux; \
    addgroup -g $GID -S gunicorn; \
    adduser -S -D -H -u $UID -h ${USER_HOME} -G gunicorn -g gunicorn gunicorn; \
    mkdir -p ${USER_HOME}; \
    chown -R gunicorn:gunicorn ${APP_HOME}; \
    chown -R gunicorn:gunicorn ${USER_HOME}; \
    chmod +x /usr/local/bin/uv;

COPY app/pointvy.py ${APP_HOME}
COPY app/templates/* ${APP_HOME}/templates/

USER gunicorn

RUN uv sync --frozen --no-dev

CMD uv run gunicorn --bind :${PORT} --workers 1 --threads 2 --timeout 0 pointvy:app
