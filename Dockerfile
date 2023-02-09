FROM python:3.11.2-alpine3.17

ENV PYTHONUNBUFFERED True
ENV TRIVY_VERSION 0.35.0
ENV TRIVY_CHECKSUM ebc1dd4d4c0594028d6a501dfc1a73d56add20b29d3dee5ab6e64aac94b1d526
ENV APP_HOME /app
ENV USER_HOME /var/cache/gunicorn
ENV UID 1001
ENV GID 1001
ENV PORT 8080
ENV PENV_VERSION 2022.11.30
ENV PIP_VERSION 22.3.1
ENV POINTVY_VERSION 1.10.0

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

WORKDIR ${APP_HOME}
COPY app/Pipfile .
COPY app/Pipfile.lock .

# pinning the curl version is non-relevant as Alpine already fixes it
# hadolint ignore=DL3018
RUN set -eux; \
    addgroup -g $GID -S gunicorn; \
    adduser -S -D -H -u $UID -h ${USER_HOME} -G gunicorn -g gunicorn gunicorn; \
    apk add --no-cache curl && rm -rf /var/cache/apk/*; \
    mkdir -p ${USER_HOME}; \
    chown -R gunicorn:gunicorn ${APP_HOME}; \
    chown -R gunicorn:gunicorn ${USER_HOME}; \
    curl -sSL https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz \
    -o trivy.tar.gz; \
    echo "${TRIVY_CHECKSUM}  trivy.tar.gz" | sha256sum -c -; \
    tar xf trivy.tar.gz && rm trivy.tar.gz && chmod ugo+x trivy; \
    apk del curl; \
    pip install --no-cache-dir -U pip=="$PIP_VERSION" pipenv=="$PENV_VERSION";

COPY app/ ./

USER gunicorn

RUN pipenv install --deploy --ignore-pipfile

CMD pipenv run gunicorn --bind :${PORT} --workers 1 --threads 2 --timeout 0 main:app
