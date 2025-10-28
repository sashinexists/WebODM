# syntax=docker/dockerfile:1
FROM python:3.12-alpine3.22 AS builder
LABEL maintainer="Piero Toffanin <pt@masseranolabs.com>"

# Build-time variables
ARG WORKDIR=/webodm

# Run-time variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=$WORKDIR
ENV PROJ_LIB=/usr/share/proj

# Create and change into working directory
WORKDIR $WORKDIR

# Allow multi-line runs, break on errors and output commands for debugging
SHELL ["sh", "-exc"]

RUN echo "UTC" > /etc/timezone

#### BUILD STAGE ####

# Install build dependencies and runtime dependencies
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    <<EOT
    # Enable community and testing repos for PDAL
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/main" > /etc/apk/repositories
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories

    # Update package index
    apk update

    # Build dependencies
    apk add --no-cache \
        build-base \
        cmake \
        ninja \
        git \
        curl \
        ca-certificates \
        bash \
        coreutils

    # Install libexecinfo from Alpine 3.16 (removed in 3.17+)
    apk add --no-cache --update --repository=https://dl-cdn.alpinelinux.org/alpine/v3.16/main/ \
        libexecinfo-dev \
        libexecinfo

    # Geospatial libraries
    apk add --no-cache \
        gdal \
        gdal-dev \
        gdal-tools \
        gdal-driver-png \
        gdal-driver-jpeg \
        gdal-driver-webp \
        pdal \
        pdal-dev \
        proj \
        proj-dev \
        proj-util \
        geos \
        geos-dev \
        sqlite \
        sqlite-dev \
        py3-shapely

    # PostgreSQL
    apk add --no-cache \
        postgresql-dev \
        postgresql-client

    # Python development
    apk add --no-cache \
        python3-dev

    # Image libraries for Pillow
    apk add --no-cache \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        zlib-dev \
        tiff-dev

    # System utilities
    apk add --no-cache \
        nginx \
        dcron \
        tzdata \
        gettext \
        gettext-dev

    # Node.js and npm
    apk add --no-cache \
        nodejs \
        npm
EOT

# Build Entwine from source (using latest version for PDAL 2.8+ compatibility)
RUN --mount=type=cache,target=/root/.cache,sharing=locked \
    <<EOT
    mkdir /staging && cd /staging
    git clone https://github.com/connormanning/entwine && cd entwine
    git checkout 3.2.1
    mkdir build && cd build
    cmake .. \
        -G Ninja \
        -DWITH_TESTS=OFF \
        -DCMAKE_INSTALL_PREFIX=/staging/entwine/build/install \
        -DCMAKE_BUILD_TYPE=Release
    ninja -j$(nproc)
    ninja install
    cd $WORKDIR
EOT

# Create virtualenv
RUN python3 -m venv $WORKDIR/venv

# Modify PATH to prioritize venv, effectively activating venv
ENV PATH="$WORKDIR/venv/bin:$PATH"

# Copy requirements first for better caching
COPY requirements.txt ./

# Upgrade pip and install Python dependencies
RUN --mount=type=cache,target=/root/.cache/pip \
    <<EOT
    pip install --upgrade pip setuptools wheel

    # Install GDAL Python bindings matching system GDAL version
    GDAL_VERSION=$(gdal-config --version)
    pip install "gdal[numpy]==${GDAL_VERSION}.*"

    # Install requirements (will be updated separately)
    pip install -r requirements.txt

    # Install additional geospatial packages
    pip install "boto3>=1.34.0"
EOT

# Install project Node dependencies
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    <<EOT
    npm install --quiet
    # Install webpack and webpack CLI globally
    npm install --quiet -g webpack@5.89.0 webpack-cli@5.1.4
EOT

# Copy remaining files
COPY . ./

# Defining this here allows for caching of previous layers
ARG TEST_BUILD

# Final build steps
RUN <<EOT
    # Setup cron
    chmod 0644 ./nginx/crontab
    mkdir -p /var/spool/cron/crontabs
    ln -sf $WORKDIR/nginx/crontab /var/spool/cron/crontabs/root

    # NodeODM setup
    chmod +x ./nginx/letsencrypt-autogen.sh
    ./nodeodm/setup.sh
    ./nodeodm/cleanup.sh

    # Run webpack build
    webpack --mode production

    # Django setup
    python manage.py collectstatic --noinput
    python manage.py rebuildplugins
    python manage.py translate build --safe

    # Remove auto-generated secret key
    rm -f /webodm/webodm/secret_key.py
EOT

#### RUNTIME STAGE ####

FROM python:3.12-alpine3.22 AS runtime

ARG WORKDIR=/webodm

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=$WORKDIR
ENV PROJ_LIB=/usr/share/proj
ENV PATH="$WORKDIR/venv/bin:$PATH"

WORKDIR $WORKDIR

SHELL ["sh", "-exc"]

# Install only runtime dependencies
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    <<EOT
    echo "UTC" > /etc/timezone

    # Enable community repo
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/main" > /etc/apk/repositories
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories

    apk update

    # Runtime dependencies only
    apk add --no-cache \
        bash \
        coreutils \
        curl \
        ca-certificates \
        gdal \
        gdal-tools \
        gdal-driver-png \
        gdal-driver-jpeg \
        gdal-driver-webp \
        pdal \
        proj \
        proj-util \
        geos \
        sqlite \
        postgresql-client \
        nginx \
        dcron \
        tzdata \
        gettext \
        nodejs \
        npm \
        git \
        libjpeg-turbo \
        libpng \
        libwebp \
        tiff \
        py3-shapely

    # Install libexecinfo from Alpine 3.16 (removed in 3.17+)
    apk add --no-cache --update --repository=https://dl-cdn.alpinelinux.org/alpine/v3.16/main/ \
        libexecinfo

    # Install webpack globally (needed for dev mode)
    npm install --quiet -g webpack@5.89.0 webpack-cli@5.1.4

    # Cleanup
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*
EOT

# Copy virtualenv from builder
COPY --from=builder $WORKDIR/venv $WORKDIR/venv

# Make system packages (py3-shapely) accessible to venv
RUN echo "/usr/lib/python3.12/site-packages" > $WORKDIR/venv/lib/python3.12/site-packages/system-packages.pth

# Copy Entwine binary and libraries
COPY --from=builder /staging/entwine/build/install/bin/entwine /usr/bin/entwine
COPY --from=builder /staging/entwine/build/install/lib/libentwine* /usr/lib/

# Copy application code and built assets
COPY --from=builder $WORKDIR $WORKDIR

VOLUME /webodm/app/media
