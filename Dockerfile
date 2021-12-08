FROM python:3.10-alpine3.15

ENV PYTHONUNBUFFERED True
ENV TRIVY_VERSION 0.21.2
ENV TRIVY_CHECKSUM 563d937db4febeafe6a318ee242eb7da940ff858650eec3864365b4745caab58
ENV APP_HOME /app
ENV USER_HOME /var/cache/gunicorn
ENV CURL_VERSION 7.80
ENV UID 1001
ENV GID 1001
ENV PORT 8080

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

WORKDIR ${APP_HOME}
COPY app/requirements.txt .

RUN set -eux; \
    addgroup -g $GID -S gunicorn; \
    adduser -S -D -H -u $UID -h ${USER_HOME} -G gunicorn -g gunicorn gunicorn; \
    apk add --no-cache curl~=${CURL_VERSION} && rm -rf /var/cache/apk/*; \
    mkdir -p ${USER_HOME}; \
    chown -R gunicorn:gunicorn ${APP_HOME}; \
    chown -R gunicorn:gunicorn ${USER_HOME}; \
    curl -L https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz \
    -o trivy.tar.gz; \
    echo "${TRIVY_CHECKSUM}  trivy.tar.gz" | sha256sum -c -; \
    tar xf trivy.tar.gz && rm trivy.tar.gz && chmod ugo+x trivy; \
    pip install --no-cache-dir -r requirements.txt; \
    apk del curl

COPY app/ ./

USER gunicorn

CMD gunicorn --bind :${PORT} --workers 1 --threads 2 --timeout 0 main:app
