FROM aquasec/trivy:0.48.2 as base

FROM python:3.12.1-alpine3.18

ENV PYTHONUNBUFFERED True
ENV APP_HOME /app
ENV USER_HOME /var/cache/gunicorn
ENV UID 1001
ENV GID 1001
ENV PORT 8080
ENV PENV_VERSION 2023.07.11
ENV PIP_VERSION 23.1.2
ENV POINTVY_VERSION 1.14.0

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
