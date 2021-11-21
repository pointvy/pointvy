FROM python:3.10-alpine

ENV PYTHONUNBUFFERED True
ENV TRIVY_VERSION 0.21.0
ENV TRIVY_CHECKSUM 5503390316751a1a932e334ef14ec057f4976addec32ff0145273c7c06a160bc
ENV APP_HOME /app
ENV USER_HOME /var/cache/gunicorn
ENV CURL_VERSION 7.79
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
    > trivy.tar.gz; \
    echo "${TRIVY_CHECKSUM}  trivy.tar.gz" | sha256sum -c -; \
    tar xf trivy.tar.gz && rm trivy.tar.gz && chmod ugo+x trivy; \
    pip install --no-cache-dir -r requirements.txt;

COPY app/ ./

USER gunicorn

CMD gunicorn --bind :${PORT} --workers 1 --threads 2 --timeout 0 main:app
