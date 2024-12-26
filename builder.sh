#!/bin/bash

set -e

REBUILD=false
INTERACTIVE=false
VOLUME_TYPE="bind"  # bind, sparse, docker
VOLUME_NAME="librescoot-yocto-build"
SPARSE_IMAGE="YoctoBuild.sparseimage"
SPARSE_SIZE="200g"

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
uid=$(id -u)
gid=$(id -g)

function usage() {
   cat >&2 <<EOF
Usage: $0 [options] <command> [target]
Commands:
    build <target>   - Build specified target (mdb dbc)
    interactive      - Start interactive shell in builder container
Options:
    --rebuild        - Force rebuilding the builder container
    --volume TYPE    - Volume type: bind (default), sparse (macOS only), docker (named volume)
EOF
   exit 1
}

function check_filesystem() {
   if [[ "$OSTYPE" == "darwin"* ]] && [[ "$VOLUME_TYPE" == "bind" ]]; then
       if ! mount | grep -q "on $source_dir.*case-sensitive"; then
           echo "Warning: Running on case-insensitive filesystem. This may cause issues." >&2
           echo "Consider using --volume sparse for better compatibility." >&2
       fi
   fi
}

function setup_sparse_volume() {
   local MOUNTED=false
   local EXISTS=false
   
   [[ -f "$SPARSE_IMAGE" ]] && EXISTS=true
   mount | grep -q "/Volumes/YoctoBuild" && MOUNTED=true
   
   if [[ "$EXISTS" == "false" ]]; then
       echo "Creating sparse image of size $SPARSE_SIZE..."
       hdiutil create -size $SPARSE_SIZE -type SPARSE -fs 'Case-sensitive APFS' \
           -volname YoctoBuild "$SPARSE_IMAGE"
   fi
   
   if [[ "$MOUNTED" == "false" ]]; then
       echo "Mounting sparse image..."
       hdiutil attach "$SPARSE_IMAGE" -mountpoint ./yocto
   else
       echo "Sparse image already mounted at ./yocto"
   fi
}

function cleanup_sparse_volume() {
   if mount | grep -q "/Volumes/YoctoBuild"; then
       echo "Unmounting sparse image..."
       hdiutil detach ./yocto
   fi
}

# Add trap for cleanup
if [[ "$VOLUME_TYPE" == "sparse" ]]; then
   trap cleanup_sparse_volume EXIT
fi

function setup_docker() {
   COMMIT_ID=$(git rev-parse --short HEAD)
   IMAGE_NAME="yocto-librescoot:${COMMIT_ID}"
   
   if [[ "$VOLUME_TYPE" == "docker" ]]; then
       docker volume inspect $VOLUME_NAME >/dev/null 2>&1 || docker volume create $VOLUME_NAME
   elif [[ "$VOLUME_TYPE" == "sparse" ]]; then
       setup_sparse_volume
   else
       mkdir -p "${source_dir}/yocto"
   fi

   if [ "$REBUILD" = true ] || ! docker images "${IMAGE_NAME}" | grep -q "${COMMIT_ID}"; then
       [ "$REBUILD" = true ] && echo "Forcing rebuild!"
       docker build --build-arg UID=$uid --build-arg GID=$gid -t "${IMAGE_NAME}" ./docker
   fi
}

function get_volume_mount() {
   case "$VOLUME_TYPE" in
       docker)  echo "${VOLUME_NAME}:/yocto" ;;
       sparse)  echo "./yocto:/yocto" ;;
       bind)    echo "${source_dir}/yocto:/yocto" ;;
   esac
}

while [[ $# -gt 0 ]]; do
   case "$1" in
        --help|-h)
            usage
            exit 1
            ;;    
        --rebuild)
            REBUILD=true
            shift
            ;;
        --volume|-v)
            VOLUME_TYPE="$2"
            shift 2
            ;;
        build|interactive)
            COMMAND="$1"
            shift
            ;;
        *)
            TARGET="$1"
            shift ;;
   esac
done

[ -z "$COMMAND" ] && usage
[ "$VOLUME_TYPE" == "sparse" ] && [[ ! "$OSTYPE" == "darwin"* ]] && \
   echo "Sparse volumes only supported on macOS" && exit 1

check_filesystem
setup_docker
VOLUME_MOUNT=$(get_volume_mount)

case "$COMMAND" in
   build)
       [ -z "$TARGET" ] && usage
       docker run -it --rm \
           -v "$VOLUME_MOUNT" \
           --name yocto-build \
           -e TARGET="${TARGET}" \
           "${IMAGE_NAME}" ;;
   interactive)
       docker run -it --rm \
           -v "$VOLUME_MOUNT" \
           --name yocto-build-interactive \
           --entrypoint /bin/bash \
           "${IMAGE_NAME}" ;;
esac
