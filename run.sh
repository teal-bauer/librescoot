#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No target specified."
    echo "Usage: $0 <target>"
    echo "Example: $0 mdb"
    echo "         $0 dbc"
    exit 1
fi

TARGET=$1
COMMIT_ID=$(git rev-parse --short HEAD)

IMAGE_NAME="yocto-librescoot:${COMMIT_ID}"

mkdir -p yocto
sudo chown 999:999 yocto

if ! sudo docker images | grep -q "${COMMIT_ID}"; then
    echo "Building Docker image ${IMAGE_NAME}..."
    sudo docker build -t "${IMAGE_NAME}" ./docker
else
    echo "Using existing Docker image ${IMAGE_NAME}."
fi

echo "Building target: ${TARGET}"

sudo docker run -it --rm \
    -v "$(pwd)/yocto:/yocto" \
    --name yocto-build \
    -e TARGET="${TARGET}" \
    "${IMAGE_NAME}"

