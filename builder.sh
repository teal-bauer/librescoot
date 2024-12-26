#!/bin/bash

set -e

REBUILD=false
INTERACTIVE=false

VOLUME_NAME="librescoot-yocto-build"

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
uid=$(id -u)
gid=$(id -g)

echo $source_dir

mkdir -p "${source_dir}/yocto"

function usage() {
    (
        echo "Usage: $0 [--rebuild] <command> [target]"
        echo "Commands:"
        echo "  build <target>   - Build specified target (mdb dbc)"
        echo "  interactive      - Start interactive shell in builder container"
        echo "Options:"
        echo "  --rebuild        - Force rebuilding the builder container"
    ) >&2
    exit 1
}

function setup_docker() {
    COMMIT_ID=$(git rev-parse --short HEAD)
    IMAGE_NAME="yocto-librescoot:${COMMIT_ID}"
    
    docker volume inspect $VOLUME_NAME >/dev/null 2>&1 || docker volume create $VOLUME_NAME

    if [ "$REBUILD" = true ] || ! docker images "${IMAGE_NAME}" | grep -q "${COMMIT_ID}"; then
        [ "$REBUILD" = true ] && echo "Forcing rebuild!"
        echo "Building Docker image ${IMAGE_NAME}..."

        docker build \
            --build-arg UID=$uid \
            --build-arg GID=$gid \
            -t "${IMAGE_NAME}" \
            ./docker
    else
        echo "Using existing Docker image ${IMAGE_NAME}."
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild)
            REBUILD=true
            shift
            ;;
        build)
            COMMAND=build
            shift
            ;;
        interactive|shell)
            COMMAND=interactive
            shift
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

[ -z "$COMMAND" ] && usage

setup_docker

case "$COMMAND" in
    build)
        [ -z "$TARGET" ] && usage
        docker run -it --rm \
            -v "${VOLUME_NAME}:/yocto" \
            --name yocto-build \
            -e TARGET="${TARGET}" \
            "${IMAGE_NAME}"
        ;;
    interactive)
        docker run -it --rm \
            -v "${VOLUME_NAME}:/yocto" \
            --name yocto-build-interactive \
            --entrypoint /bin/bash \
            "${IMAGE_NAME}"
        ;;
esac
