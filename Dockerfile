# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm AS common
LABEL maintainer="Piero Toffanin <pt@masseranolabs.com>"

# Build-time variables
ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_MAJOR=20
ARG WORKDIR=/webodm

# Run-time variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=$WORKDIR

#### Common setup ####

# Create and change into working directory
WORKDIR $WORKDIR

# Allow multi-line runs, break on errors and output commands for debugging.
# The following does not work in Podman unless you build in Docker
# compatibility mode: <https://github.com/containers/podman/issues/8477>
# You can manually prepend every RUN script with `set -ex` too.
SHELL ["sh", "-exc"]

RUN <<EOT
    # Common system configuration, should change very infrequently
    # Set timezone to UTC
    echo "UTC" > /etc/timezone
EOT

FROM common AS build

# Install Python deps -- install & remove cleanup build-only deps in the process
COPY requirements.txt ./

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    <<EOT
    # Build-time dependencies
    apt-get -qq update
    apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg cmake g++ wget \
        libgeotiff-dev libgeos-dev libtiff-dev libcurl4-openssl-dev \
        libxml2-dev libsqlite3-dev sqlite3 pkg-config
    # Node.js deb source
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    # Update package list
    apt-get update
    # Install common deps, starting with NodeJS
    apt-get -qq install -y nodejs
    # Python dev tools, GDAL, nginx, letsencrypt, psql
    apt-get install -y --no-install-recommends \
        python3-dev libpq-dev build-essential git gdal-bin \
        libgdal-dev nginx certbot gettext-base cron postgresql-client gettext tzdata
    # Build PROJ from source (need modern version for new rasterio/rio-tiler)
    mkdir -p /staging && cd /staging
    wget -q https://download.osgeo.org/proj/proj-9.4.1.tar.gz
    tar xzf proj-9.4.1.tar.gz && cd proj-9.4.1
    mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/staging/proj/install -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF -DBUILD_PROJSYNC=OFF
    make -j6 && make install
    # Update environment to use our compiled PROJ
    export PKG_CONFIG_PATH=/staging/proj/install/lib/pkgconfig:$PKG_CONFIG_PATH
    export LD_LIBRARY_PATH=/staging/proj/install/lib:$LD_LIBRARY_PATH
    # Build PDAL from source (not available in Debian repos)
    cd /staging
    wget -q https://github.com/PDAL/PDAL/releases/download/2.6.3/PDAL-2.6.3-src.tar.bz2
    tar xjf PDAL-2.6.3-src.tar.bz2 && cd PDAL-2.6.3-src
    mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/staging/pdal/install -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_PLUGIN_PGPOINTCLOUD=OFF -DBUILD_PLUGIN_NITF=OFF -DBUILD_PLUGIN_ICEBRIDGE=OFF \
        -DBUILD_PLUGIN_HDF=OFF -DWITH_TESTS=OFF -DWITH_ZSTD=OFF
    make -j6 && make install
    # Note: Entwine build removed - incompatible with PDAL 2.6.3
    # Entwine is used for EPT (Entwine Point Tile) generation
    # WebODM can function without it for core photogrammetry tasks
    cd /webodm
EOT

RUN --mount=type=cache,target=/root/.cache/pip \
    <<EOT
    # Install Python dependencies
    # Set environment to use our compiled PROJ
    export PKG_CONFIG_PATH=/staging/proj/install/lib/pkgconfig:\$PKG_CONFIG_PATH
    export LD_LIBRARY_PATH=/staging/proj/install/lib:\$LD_LIBRARY_PATH
    export PROJ_LIB=/staging/proj/install/share/proj
    # Install pip
    pip install pip==24.0
    # Install Python requirements, including correct Python GDAL bindings.
    pip install -r requirements.txt "boto3==1.26.137" gdal[numpy]=="$(gdal-config --version).*"
EOT

# Install project Node dependencies
COPY package.json ./
RUN --mount=type=cache,target=/root/.npm \
    <<EOT
    npm install --quiet
    # Install webpack, webpack CLI
    npm install --quiet -g webpack@5.89.0
    npm install --quiet -g webpack-cli@5.1.4
EOT

# Copy remaining files
COPY . ./

# Defining this here allows for caching of previous layers.
ARG TEST_BUILD

RUN <<EOT
    # Final build steps (in one roll to prevent too many layers).
    # Setup cron
    chmod 0644 ./nginx/crontab
    ln -s ./nginx/crontab /var/spool/cron/crontabs/root
    # NodeODM setup
    chmod +x ./nginx/letsencrypt-autogen.sh
    ./nodeodm/setup.sh
    ./nodeodm/cleanup.sh
    # Run webpack build, Django setup and final cleanup
    webpack --mode production
    # Django setup
    python manage.py collectstatic --noinput
    python manage.py rebuildplugins
    python manage.py translate build --safe
    # Final cleanup
    # Remove stale temp files
    rm -rf /tmp/* /var/tmp/*
    # Remove auto-generated secret key (happens on import of settings when none is defined)
    rm /webodm/webodm/secret_key.py
EOT

FROM common AS app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.npm \
    <<EOT
    # Run-time dependencies
    apt-get -qq update
    apt-get install -y --no-install-recommends curl ca-certificates gnupg
    # Node.js deb source
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    # Update package list
    apt-get update
    # Install common deps, starting with NodeJS
    apt-get -qq install -y nodejs
    # GDAL, nginx, letsencrypt, psql, git + runtime deps
    # Note: PROJ will be copied from build stage (compiled version)
    apt-get install -y --no-install-recommends \
        gdal-bin nginx certbot gettext-base cron postgresql-client gettext tzdata git \
        libgeos-c1v5 libxml2 libcurl4 libsqlite3-0 libtiff6
    # Install webpack, webpack CLI
    npm install --quiet -g webpack@5.89.0
    npm install --quiet -g webpack-cli@5.1.4
    # Cleanup of build requirements
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    # Remove stale temp files
    rm -rf /tmp/* /var/tmp/*
EOT

# Copy Python packages and binaries from build stage
COPY --from=build /usr/local/lib/python3.12/site-packages/ /usr/local/lib/python3.12/site-packages/
COPY --from=build /usr/local/bin/ /usr/local/bin/
# Copy PROJ, PDAL and other compiled libraries
COPY --from=build /staging/proj/install/ /usr/local/
# Entwine removed - incompatible with PDAL 2.6.3
# COPY --from=build /staging/entwine/build/install/bin/entwine /usr/bin/entwine
# COPY --from=build /staging/entwine/build/install/lib/libentwine* /usr/lib/
COPY --from=build /staging/pdal/install/bin/pdal /usr/bin/pdal
COPY --from=build /staging/pdal/install/lib/libpdal* /usr/lib/
COPY --from=build /usr/lib/x86_64-linux-gnu/libgeotiff.so* /usr/lib/x86_64-linux-gnu/
# Copy WebODM application code
COPY --from=build $WORKDIR ./

# Set PROJ_LIB to point to our compiled PROJ data files
ENV PROJ_LIB=/usr/local/share/proj

RUN ldconfig

VOLUME /webodm/app/media
