FROM --platform=$BUILDPLATFORM docker.io/node:20-bookworm-slim AS compile-frontend

COPY ./src-ui /src/src-ui

WORKDIR /src/src-ui
RUN set -eux \
  && npm update npm -g \
  && npm ci

ARG PNGX_TAG_VERSION=
# Add the tag to the environment file if its a tagged dev build
RUN set -eux && \
case "${PNGX_TAG_VERSION}" in \
  dev|beta|fix*|feature*) \
    sed -i -E "s/version: '([0-9\.]+)'/version: '\1 #${PNGX_TAG_VERSION}'/g" /src/src-ui/src/environments/environment.prod.ts \
    ;; \
esac

RUN set -eux \
  && ./node_modules/.bin/ng build --configuration production

# Stage: s6-overlay-base 
FROM docker.io/python:3.12-slim-bookworm AS main-app

WORKDIR /usr/src/paperless/

COPY --chown=1000:1000 gunicorn.conf.py /usr/src/paperless/gunicorn.conf.py

WORKDIR /usr/src/paperless/src/

RUN apt-get update --fix-missing && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    curl \
    gosu \
    tzdata \
    fonts-liberation \
    gettext \
    ghostscript \
    gnupg \
    icc-profiles-free \
    imagemagick \
    postgresql-client \
    mariadb-client \
    tesseract-ocr \
    tesseract-ocr-eng \
    tesseract-ocr-deu \
    tesseract-ocr-fra \
    tesseract-ocr-ita \
    tesseract-ocr-spa \
    unpaper \
    pngquant \
    jbig2dec \
    libxml2 \
    libxslt1.1 \
    qpdf \
    file \
    libmagic1 \
    media-types \
    zlib1g \
    libzbar0 \
    poppler-utils

RUN set -eux \
  && echo "Setting up user/group" \
    && addgroup --gid 1000 paperless \
    && useradd --uid 1000 --gid paperless --home-dir /usr/src/paperless paperless \
  && echo "Creating volume directories" \
    && mkdir --parents --verbose /usr/src/paperless/data \
    && mkdir --parents --verbose /usr/src/paperless/media \
    && mkdir --parents --verbose /usr/src/paperless/consume \
    && mkdir --parents --verbose /usr/src/paperless/export \
  && echo "Creating gnupg directory" \
    && mkdir -m700 --verbose /usr/src/paperless/.gnupg \
  && echo "Adjusting all permissions" \
    && chown --from root:root --changes --recursive paperless:paperless /usr/src/paperless

COPY requirements.txt .
RUN pip install -r requirements.txt
RUN pip install pymysql
# copy backend
COPY --chown=1000:1000 ./src ./

# copy frontend
# COPY --from=compile-frontend --chown=1000:1000 /src/src/documents/static/frontend/ ./documents/static/frontend/
COPY --from=compile-frontend --chown=1000:1000 /src/src/documents/static/frontend/ /usr/src/paperless/static/frontend/

RUN set -eux \
  && echo "Creating volume directories" \
    && mkdir --parents --verbose /usr/src/paperless/data \
    && mkdir --parents --verbose /usr/src/paperless/media \
    && mkdir --parents --verbose /usr/src/paperless/consume \
    && mkdir --parents --verbose /usr/src/paperless/export \
  && echo "Creating gnupg directory" \
    && mkdir -p -m700 --verbose /usr/src/paperless/.gnupg \
  && echo "Adjusting all permissions" \
    && chown --from root:root --changes --recursive paperless:paperless /usr/src/paperless  
#  && echo "Collecting static files" \
#     && DJANGO_SETTINGS_MODULE=paperless.settings python3 manage.py collectstatic --clear --no-input --link \
#     && DJANGO_SETTINGS_MODULE=paperless.settings python3 manage.py compilemessages


VOLUME ["/usr/src/paperless/data", \
        "/usr/src/paperless/media", \
        "/usr/src/paperless/consume", \
        "/usr/src/paperless/export"]

# ENTRYPOINT ["/init"]
EXPOSE 8000
CMD python3 manage.py runserver 0.0.0.0:8000 & \
    python3 manage.py document_consumer & \
    celery --app paperless worker -l DEBUG
# CMD ["tail", "-f", "/dev/null"]

# HEALTHCHECK --interval=30s --timeout=10s --retries=5 CMD [ "curl", "-fs", "-S", "--max-time", "2", "http://localhost:8000" ]