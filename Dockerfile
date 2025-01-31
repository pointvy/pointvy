FROM aquasec/trivy:0.59.0 AS base

FROM python:3.13.1-alpine3.19

ENV PYTHONUNBUFFERED="True"
ENV APP_HOME="/app"
ENV USER_HOME="/var/cache/gunicorn"
ENV UID="1001"
ENV GID="1001"
ENV PORT="8080"
ENV PENV_VERSION="2024.1.0"
ENV PIP_VERSION="24.2   "
ENV POINTVY_VERSION="1.15.0"

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

WORKDIR ${APP_HOME}
COPY app/Pipfile .
COPY app/Pipfile.lock .

COPY --from=base /usr/local/bin/trivy ${APP_HOME}/

# pinning the curl version is non-relevant as Alpine already fixes it
# hadolint ignore=DL3018
RUN set -eux; \
    addgroup -g $GID -S gunicorn; \
    adduser -S -D -H -u $UID -h ${USER_HOME} -G gunicorn -g gunicorn gunicorn; \
    mkdir -p ${USER_HOME}; \
    chown -R gunicorn:gunicorn ${APP_HOME}; \
    chown -R gunicorn:gunicorn ${USER_HOME}; \
    pip install --no-cache-dir -U pip=="$PIP_VERSION" pipenv=="$PENV_VERSION";

COPY app/pointvy.py ${APP_HOME}
COPY app/templates/* ${APP_HOME}/templates/

USER gunicorn

RUN pipenv install --deploy --ignore-pipfile

CMD pipenv run gunicorn --bind :${PORT} --workers 1 --threads 2 --timeout 0 pointvy:app
