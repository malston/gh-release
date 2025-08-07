#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$__DIR/.." && pwd)"

# Default values
REGISTRY="${REGISTRY:-docker.io}"
REPOSITORY="${REPOSITORY:-gh-release-tools}"
TAG="${TAG:-latest}"
PLATFORM="${PLATFORM:-linux/amd64,linux/arm64}"

usage() {
    cat <<EOF
Usage:
    $0 [OPTIONS]

Options:
    -r, --registry <registry>     Container registry [default: $REGISTRY]
    -n, --repository <repo>       Repository name [default: $REPOSITORY]
    -t, --tag <tag>              Image tag [default: $TAG]
    -p, --platform <platforms>   Build platforms [default: $PLATFORM]
    --push                       Push image to registry
    --load                       Load image locally (single platform only)
    -h, --help                   Show this help message

Examples:
    # Build locally
    $0 --load

    # Build and push to registry
    $0 --push --registry myregistry.com --repository myorg/gh-release-tools

    # Build for specific platform
    $0 --platform linux/amd64 --load

Environment Variables:
    REGISTRY                     Container registry
    REPOSITORY                   Repository name
    TAG                          Image tag
    PLATFORM                     Build platforms
EOF
}

# Parse arguments
PUSH=false
LOAD=false

while [[ $# -gt 0 ]]; do
    case $1 in
    -r | --registry)
        REGISTRY="$2"
        shift 2
        ;;
    -n | --repository)
        REPOSITORY="$2"
        shift 2
        ;;
    -t | --tag)
        TAG="$2"
        shift 2
        ;;
    -p | --platform)
        PLATFORM="$2"
        shift 2
        ;;
    --push)
        PUSH=true
        shift
        ;;
    --load)
        LOAD=true
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

# Build image name
IMAGE_NAME="$REGISTRY/$REPOSITORY:$TAG"

echo "Building container image..."
echo "  Registry: $REGISTRY"
echo "  Repository: $REPOSITORY"
echo "  Tag: $TAG"
echo "  Platform: $PLATFORM"
echo "  Full name: $IMAGE_NAME"
echo ""

# Change to project root
cd "$PROJECT_ROOT"

# Build arguments
BUILD_ARGS=(
    "--file" "Dockerfile"
    "--tag" "$IMAGE_NAME"
    "--platform" "$PLATFORM"
)

if [[ "$PUSH" == "true" ]]; then
    BUILD_ARGS+=("--push")
    echo "Building and pushing image..."
elif [[ "$LOAD" == "true" ]]; then
    BUILD_ARGS+=("--load")
    echo "Building and loading image locally..."
    # For load, we can only build single platform
    if [[ "$PLATFORM" == *","* ]]; then
        echo "Warning: --load only supports single platform, using linux/amd64"
        BUILD_ARGS=("${BUILD_ARGS[@]/--platform $PLATFORM/--platform linux/amd64}")
    fi
else
    echo "Building image (no push/load)..."
fi

# Use buildx for multi-platform support
if command -v docker &>/dev/null; then
    if docker buildx version &>/dev/null; then
        docker buildx build "${BUILD_ARGS[@]}" .
    else
        echo "Warning: docker buildx not available, falling back to regular docker build"
        docker build --tag "$IMAGE_NAME" .
    fi
else
    echo "Error: docker command not found"
    exit 1
fi

echo ""
if [[ "$PUSH" == "true" ]]; then
    echo "✅ Image built and pushed: $IMAGE_NAME"
elif [[ "$LOAD" == "true" ]]; then
    echo "✅ Image built and loaded locally: $IMAGE_NAME"
    echo ""
    echo "Test the image:"
    echo "  docker run --rm -it $IMAGE_NAME"
else
    echo "✅ Image built: $IMAGE_NAME"
fi