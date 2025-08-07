#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$__DIR/.." && pwd)"

# Default values
IMAGE="${IMAGE:-ubuntu:22.04}"
TEST_MODE="${TEST_MODE:-basic}"

usage() {
    cat <<EOF
Usage:
    $0 [OPTIONS]

Options:
    -i, --image <image>          Container image to test [default: $IMAGE]
    -m, --mode <mode>           Test mode: basic, github, full [default: $TEST_MODE]
    -h, --help                  Show this help message

Test Modes:
    basic                       Test basic tools (curl, jq, bash, git)
    github                      Test GitHub API connectivity
    full                        Test full release creation workflow

Examples:
    # Test basic tools in default Ubuntu image
    $0 --image ubuntu:22.04 --mode basic

    # Test GitHub connectivity
    $0 --image ubuntu:22.04 --mode github

    # Test custom built image
    $0 --image gh-release-tools:latest --mode full

Environment Variables:
    GITHUB_TOKEN                GitHub access token (for github/full modes)
    GITHUB_API_URL              GitHub API URL
    IMAGE                       Container image to test
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    -i | --image)
        IMAGE="$2"
        shift 2
        ;;
    -m | --mode)
        TEST_MODE="$2"
        shift 2
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

echo "Testing container image: $IMAGE"
echo "Test mode: $TEST_MODE"
echo ""

# Basic test script
BASIC_TEST_SCRIPT='
echo "=== Container Environment Test ==="
echo "Distribution: $(cat /etc/os-release | grep PRETTY_NAME)"
echo "User: $(whoami)"
echo "Working directory: $(pwd)"
echo ""

echo "=== Tool Availability Test ==="
command -v bash && echo "✅ bash available" || echo "❌ bash missing"
command -v curl && echo "✅ curl available" || echo "❌ curl missing"  
command -v jq && echo "✅ jq available" || echo "❌ jq missing"
command -v git && echo "✅ git available" || echo "❌ git missing"
echo ""

echo "=== Tool Version Test ==="
echo "bash: $(bash --version | head -1)"
echo "curl: $(curl --version | head -1)"
echo "jq: $(jq --version)"
echo "git: $(git --version)"
echo ""

echo "=== Basic Tool Function Test ==="
echo "Testing curl..."
curl -s --max-time 5 https://httpbin.org/get > /dev/null && echo "✅ curl works" || echo "❌ curl failed"

echo "Testing jq..."
echo '\''{"test": "value"}'\'' | jq -r .test | grep -q "value" && echo "✅ jq works" || echo "❌ jq failed"

echo "Testing git..."
git --version > /dev/null && echo "✅ git works" || echo "❌ git failed"

echo ""
echo "=== Basic test completed ==="
'

# GitHub connectivity test
GITHUB_TEST_SCRIPT='
echo "=== GitHub Connectivity Test ==="
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "❌ GITHUB_TOKEN not set, skipping GitHub tests"
    exit 1
fi

API_URL="${GITHUB_API_URL:-https://api.github.com}"
echo "Testing GitHub API: $API_URL"

echo "Testing authenticated user endpoint..."
if curl -s --max-time 10 \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "$API_URL/user" | jq -r .login > /dev/null; then
    echo "✅ GitHub API authentication works"
else
    echo "❌ GitHub API authentication failed"
    exit 1
fi

echo ""
echo "=== GitHub connectivity test completed ==="
'

# Full workflow test
FULL_TEST_SCRIPT='
echo "=== Full Workflow Test ==="

# Run basic tests first
'"$BASIC_TEST_SCRIPT"'

# Run GitHub tests
'"$GITHUB_TEST_SCRIPT"'

echo "=== Testing Release Creation Script ==="
if [[ -f "/tmp/ci/tasks/create-release/task.sh" ]]; then
    echo "✅ Release creation script found"
    # Test script syntax
    bash -n /tmp/ci/tasks/create-release/task.sh && echo "✅ Script syntax valid" || echo "❌ Script syntax error"
else
    echo "❌ Release creation script not found"
fi

echo ""
echo "=== Full workflow test completed ==="
'

# Choose test script based on mode
case $TEST_MODE in
basic)
    TEST_SCRIPT="$BASIC_TEST_SCRIPT"
    ;;
github)
    TEST_SCRIPT="$BASIC_TEST_SCRIPT"$'\n'"$GITHUB_TEST_SCRIPT"
    ;;
full)
    TEST_SCRIPT="$FULL_TEST_SCRIPT"
    DOCKER_VOLUMES="-v $PROJECT_ROOT/ci:/tmp/ci:ro -v $PROJECT_ROOT/scripts:/tmp/scripts:ro"
    ;;
*)
    echo "Invalid test mode: $TEST_MODE"
    exit 1
    ;;
esac

# Run the test
echo "Starting container test..."
echo ""

if [[ "$TEST_MODE" == "basic" ]]; then
    # For basic tests, install tools first if needed
    docker run --rm -i \
        -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
        -e GITHUB_API_URL="${GITHUB_API_URL:-}" \
        "$IMAGE" \
        bash -c "
            # Install tools if not available
            if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
                if command -v apt-get &>/dev/null; then
                    apt-get update && apt-get install -y curl jq git ca-certificates
                elif command -v apk &>/dev/null; then
                    apk add --no-cache curl jq git bash ca-certificates
                elif command -v yum &>/dev/null; then
                    yum install -y curl jq git
                fi
            fi
            
            $TEST_SCRIPT
        "
else
    # For github/full tests, assume tools are available or install them
    # shellcheck disable=SC2086
    docker run --rm -i \
        ${DOCKER_VOLUMES:-} \
        -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
        -e GITHUB_API_URL="${GITHUB_API_URL:-}" \
        "$IMAGE" \
        bash -c "
            # Install tools if not available
            if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
                if command -v apt-get &>/dev/null; then
                    apt-get update && apt-get install -y curl jq git ca-certificates
                elif command -v apk &>/dev/null; then
                    apk add --no-cache curl jq git bash ca-certificates
                elif command -v yum &>/dev/null; then
                    yum install -y curl jq git
                fi
            fi
            
            $TEST_SCRIPT
        "
fi

echo ""
echo "Container test completed for: $IMAGE"