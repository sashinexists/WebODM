#!/bin/bash
set -eo pipefail

# Get the toolbox container IP for host access
TOOLBOX_IP=$(hostname -I | awk '{print $1}')
echo "Toolbox IP: $TOOLBOX_IP"
echo "WebODM will be accessible at: http://$TOOLBOX_IP:8000"
echo "Or from host at: http://localhost:8000 (if port forwarding is set up)"

# Set environment variables for host access
export WO_HOST=0.0.0.0  # Allow connections from any IP
export WO_PORT=8000

# Use host's Docker socket if available, otherwise use podman
if [ -S /var/run/docker.sock ]; then
    export DOCKER_HOST=unix:///var/run/docker.sock
else
    export DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock
fi

# Export COMPOSE_FILE to include toolbox-specific overrides
# docker-compose.toolbox.yml adds SELinux labels needed for Fedora/Podman
export COMPOSE_FILE=docker-compose.yml:docker-compose.toolbox.yml

# Fix SELinux context on db/init.sql for Fedora/SELinux compatibility
# This allows the PostgreSQL container to read the initialization script
if [ -f db/init.sql ] && command -v chcon &> /dev/null; then
    echo "Setting SELinux context on db/init.sql..."
    chcon -t container_file_t db/init.sql 2>/dev/null || true
fi

# Run the original webodm.sh with podman
exec ./webodm.sh "$@"
