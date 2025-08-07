#!/usr/bin/env bash

set -o errexit

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

PIPELINE="gh-release"

# Default values
GIT_BRANCH="${GIT_BRANCH:-main}"
IS_DRAFT="${IS_DRAFT:-false}"
IS_PRERELEASE="${IS_PRERELEASE:-false}"
DELETE_TAG="${DELETE_TAG:-false}"
CONTAINER_REPOSITORY="${CONTAINER_REPOSITORY:-ubuntu}"
CONTAINER_TAG="${CONTAINER_TAG:-22.04}"

# Initialize from environment variables if available
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
GIT_PRIVATE_KEY="${GIT_PRIVATE_KEY:-}"

usage() {
    cat <<EOF
Usage:
    $0 -t <target> [-p <pipeline_name>] [OPTIONS]

Required:
   -t <target>              Concourse target name

Options:
   -p <pipeline name>       Pipeline name [default: $PIPELINE]
   --params <file>          Path to params.yml file [default: ./params.yml]

   GitHub Configuration:
   --owner <owner>          GitHub repository owner
   --repository <repo>      GitHub repository name
   --github-token <token>   GitHub access token (or set GITHUB_TOKEN env var)
   --github-api-url <url>   GitHub API URL [default: https://api.github.com]

   Git Configuration:
   --git-uri <uri>          Git repository URI
   --git-branch <branch>    Git branch [default: $GIT_BRANCH]
   --git-key <key>          Git private key (or set GIT_PRIVATE_KEY env var)

   Release Configuration:
   --release-tag <tag>      Release tag
   --release-name <name>    Release name
   --release-body <body>    Release body/description
   --is-draft               Mark release as draft
   --is-prerelease          Mark as pre-release
   --delete-tag             Delete Git tag when deleting release

   Container Configuration:
   --container-repository <repo>  Container image repository [default: ubuntu]
   --container-tag <tag>    Container image tag [default: 22.04]

   -h, --help               Display this help message

Environment Variables:
   GITHUB_TOKEN             GitHub access token
   GITHUB_API_URL           GitHub API URL (for GitHub Enterprise)
   GIT_PRIVATE_KEY          Git private key for repository access

Examples:
   # Using params file
   $0 -t my-target --params ./my-params.yml

   # Using command line flags
   $0 -t my-target --owner myorg --repository myrepo --github-token \$GITHUB_TOKEN

   # GitHub Enterprise instance
   $0 -t my-target --github-api-url https://github.company.com/api/v3 --owner myorg --repository myrepo

   # Mix of params file and overrides
   $0 -t my-target --params ./params.yml --release-tag v1.0.0

EOF
}

# Initialize variables
TARGET=""
PIPELINE_NAME="$PIPELINE"
PARAMS_FILE=""
declare -a FLY_ARGS=()

# Track which parameters were set via command line (not environment)
declare -A CLI_OVERRIDES=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    -t | --target)
        TARGET="$2"
        shift 2
        ;;
    -p | --pipeline)
        PIPELINE_NAME="$2"
        shift 2
        ;;
    --params)
        PARAMS_FILE="$2"
        shift 2
        ;;
    --owner)
        OWNER="$2"
        CLI_OVERRIDES[owner]=1
        shift 2
        ;;
    --repository)
        REPOSITORY="$2"
        CLI_OVERRIDES[repository]=1
        shift 2
        ;;
    --github-token)
        GITHUB_TOKEN="$2"
        CLI_OVERRIDES[github_token]=1
        shift 2
        ;;
    --github-api-url)
        GITHUB_API_URL="$2"
        CLI_OVERRIDES[github_api_url]=1
        shift 2
        ;;
    --git-uri)
        GIT_URI="$2"
        CLI_OVERRIDES[git_uri]=1
        shift 2
        ;;
    --git-branch)
        GIT_BRANCH="$2"
        CLI_OVERRIDES[git_branch]=1
        shift 2
        ;;
    --git-key)
        GIT_PRIVATE_KEY="$2"
        CLI_OVERRIDES[git_private_key]=1
        shift 2
        ;;
    --release-tag)
        RELEASE_TAG="$2"
        CLI_OVERRIDES[release_tag]=1
        shift 2
        ;;
    --release-name)
        RELEASE_NAME="$2"
        CLI_OVERRIDES[release_name]=1
        shift 2
        ;;
    --release-body)
        RELEASE_BODY="$2"
        CLI_OVERRIDES[release_body]=1
        shift 2
        ;;
    --is-draft)
        IS_DRAFT="true"
        CLI_OVERRIDES[is_draft]=1
        shift
        ;;
    --is-prerelease)
        IS_PRERELEASE="true"
        CLI_OVERRIDES[is_prerelease]=1
        shift
        ;;
    --delete-tag)
        DELETE_TAG="true"
        CLI_OVERRIDES[delete_tag]=1
        shift
        ;;
    --container-repository)
        CONTAINER_REPOSITORY="$2"
        CLI_OVERRIDES[container_image_repository]=1
        shift 2
        ;;
    --container-tag)
        CONTAINER_TAG="$2"
        CLI_OVERRIDES[container_image_tag]=1
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

# Validate required arguments
if [[ -z "$TARGET" ]]; then
    echo "Error: Target is required (-t <target>)"
    echo ""
    usage
    exit 1
fi

# Check if params file exists and add it to fly args
if [[ -n "$PARAMS_FILE" ]]; then
    if [[ -f "$PARAMS_FILE" ]]; then
        FLY_ARGS+=("-l" "$PARAMS_FILE")
    else
        echo "Warning: Params file not found: $PARAMS_FILE"
    fi
else
    # Check for default params.yml in current directory
    if [[ -f "./params.yml" ]]; then
        echo "Using default params.yml file"
        FLY_ARGS+=("-l" "./params.yml")
    fi
fi

# Auto-detect SSH key if not provided
if [[ -z "$GIT_PRIVATE_KEY" ]]; then
    if [[ -f ~/.ssh/id_ed25519 ]]; then
        GIT_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"
        echo "Using Ed25519 SSH key: ~/.ssh/id_ed25519"
    elif [[ -f ~/.ssh/id_rsa ]]; then
        GIT_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)"
        echo "Using RSA SSH key: ~/.ssh/id_rsa"
    else
        echo "Warning: No SSH key found in ~/.ssh/id_ed25519 or ~/.ssh/id_rsa"
        echo "You may need to provide git_private_key in params file or via --git-key flag"
    fi
fi

# Create temporary vars file for command line overrides (only if needed)
TEMP_VARS_FILE=""
OVERRIDE_COUNT=0

# Count how many parameters were overridden via command line (not environment)
OVERRIDE_COUNT=${#CLI_OVERRIDES[@]}

# Check if any environment variables are set that need to be passed through
ENV_VAR_COUNT=0
[[ -n "${GITHUB_TOKEN}" ]] && ENV_VAR_COUNT=$((ENV_VAR_COUNT + 1))
[[ -n "${GIT_PRIVATE_KEY}" ]] && ENV_VAR_COUNT=$((ENV_VAR_COUNT + 1))
[[ -n "${GITHUB_API_URL}" && "${GITHUB_API_URL}" != "https://api.github.com" ]] && ENV_VAR_COUNT=$((ENV_VAR_COUNT + 1))

# Create temp vars file if we have CLI overrides OR environment variables AND a params file
if [[ ($OVERRIDE_COUNT -gt 0 || $ENV_VAR_COUNT -gt 0) && -n "${PARAMS_FILE:-}" ]]; then
    TEMP_VARS_FILE=$(mktemp /tmp/gh-release-vars.XXXXXX.yml)
    trap 'rm -f $TEMP_VARS_FILE' EXIT

    echo "# Command line parameter overrides and environment variables" > "$TEMP_VARS_FILE"

    # Write CLI-overridden values and environment variables to temp file
    [[ -n "${CLI_OVERRIDES[owner]:-}" ]] && echo "owner: ${OWNER}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[repository]:-}" ]] && echo "repository: ${REPOSITORY}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[github_token]:-}" || (-n "${GITHUB_TOKEN}" && -z "${CLI_OVERRIDES[github_token]:-}") ]] && echo "github_token: ${GITHUB_TOKEN}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[github_api_url]:-}" || (-n "${GITHUB_API_URL}" && "${GITHUB_API_URL}" != "https://api.github.com") ]] && echo "github_api_url: ${GITHUB_API_URL}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[git_uri]:-}" ]] && echo "git_uri: ${GIT_URI}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[git_branch]:-}" ]] && echo "git_branch: ${GIT_BRANCH}" >> "$TEMP_VARS_FILE"
    if [[ -n "${CLI_OVERRIDES[git_private_key]:-}" || (-n "${GIT_PRIVATE_KEY}" && -z "${CLI_OVERRIDES[git_private_key]:-}") ]]; then
        echo "git_private_key: |" >> "$TEMP_VARS_FILE"
        printf "%s\n" "${GIT_PRIVATE_KEY}" | sed 's/^/  /' >> "$TEMP_VARS_FILE"
    fi
    [[ -n "${CLI_OVERRIDES[release_tag]:-}" ]] && echo "release_tag: ${RELEASE_TAG}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[release_name]:-}" ]] && echo "release_name: ${RELEASE_NAME}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[release_body]:-}" ]] && echo "release_body: \"${RELEASE_BODY}\"" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[is_draft]:-}" ]] && echo "is_draft: ${IS_DRAFT}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[is_prerelease]:-}" ]] && echo "is_prerelease: ${IS_PRERELEASE}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[delete_tag]:-}" ]] && echo "delete_tag: ${DELETE_TAG}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[container_image_repository]:-}" ]] && echo "container_image_repository: ${CONTAINER_REPOSITORY}" >> "$TEMP_VARS_FILE"
    [[ -n "${CLI_OVERRIDES[container_image_tag]:-}" ]] && echo "container_image_tag: ${CONTAINER_TAG}" >> "$TEMP_VARS_FILE"

elif [[ $OVERRIDE_COUNT -gt 0 && -z "${PARAMS_FILE:-}" ]]; then
    # No params file, create complete vars file from command line + defaults
    TEMP_VARS_FILE=$(mktemp /tmp/gh-release-vars.XXXXXX.yml)
    trap 'rm -f $TEMP_VARS_FILE' EXIT

    cat > "$TEMP_VARS_FILE" <<EOF
# GitHub Configuration
owner: ${OWNER:-REQUIRED_OWNER}
repository: ${REPOSITORY:-REQUIRED_REPOSITORY}
github_api_url: ${GITHUB_API_URL:-https://api.github.com}

# Git Configuration
git_uri: ${GIT_URI:-REQUIRED_GIT_URI}
git_branch: ${GIT_BRANCH}

# Release Configuration
release_tag: ${RELEASE_TAG:-REQUIRED_RELEASE_TAG}
release_name: ${RELEASE_NAME:-REQUIRED_RELEASE_NAME}
release_body: "${RELEASE_BODY:-Release notes}"
is_draft: ${IS_DRAFT}
is_prerelease: ${IS_PRERELEASE}
delete_tag: ${DELETE_TAG}

# Container Configuration
container_image_repository: ${CONTAINER_REPOSITORY}
container_image_tag: ${CONTAINER_TAG}
EOF
fi

# Display configuration summary
echo "========================================="
echo "GitHub Release Pipeline Configuration"
echo "========================================="
echo "Target: $TARGET"
echo "Pipeline: $PIPELINE_NAME"

if [[ -n "$PARAMS_FILE" && -f "$PARAMS_FILE" ]]; then
    echo "Params File: $PARAMS_FILE"
    if [[ $OVERRIDE_COUNT -gt 0 ]]; then
        echo "Command Line Overrides: $OVERRIDE_COUNT parameters"
    fi
    if [[ $ENV_VAR_COUNT -gt 0 ]]; then
        echo "Environment Variables: $ENV_VAR_COUNT parameters"
    fi
elif [[ -n "$PARAMS_FILE" ]]; then
    echo "Params File: $PARAMS_FILE (not found - using command line only)"
else
    echo "Configuration: Command line parameters only"
fi

if [[ -n "$OWNER" ]]; then
    echo "Owner: $OWNER"
fi

if [[ -n "$REPOSITORY" ]]; then
    echo "Repository: $REPOSITORY"
fi

if [[ -n "${GITHUB_API_URL:-}" && "${GITHUB_API_URL}" != "https://api.github.com" ]]; then
    echo "GitHub API URL: $GITHUB_API_URL"
fi

echo "Git Branch: $GIT_BRANCH"
echo "Container: $CONTAINER_REPOSITORY:$CONTAINER_TAG"

if [[ -n "$RELEASE_TAG" ]]; then
    echo "Release Tag: $RELEASE_TAG"
fi

if [[ "$IS_DRAFT" == "true" ]]; then
    echo "Draft Release: Yes"
fi

if [[ "$IS_PRERELEASE" == "true" ]]; then
    echo "Pre-release: Yes"
fi

if [[ "$DELETE_TAG" == "true" ]]; then
    echo "Delete Git tag: Yes"
fi

echo "========================================="
echo ""

# Ask for confirmation
read -p "Deploy pipeline? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Pipeline deployment cancelled"
    exit 0
fi

# Deploy the pipeline
echo "Deploying pipeline..."
FLY_CMD=(fly -t "$TARGET" set-pipeline -p "$PIPELINE_NAME" -c "$__DIR/pipelines/pipeline.yml" "${FLY_ARGS[@]}")

# Only add temp vars file if it was created
if [[ -n "$TEMP_VARS_FILE" ]]; then
    FLY_CMD+=(-l "$TEMP_VARS_FILE")
fi

"${FLY_CMD[@]}"

# Order pipelines alphabetically
fly -t "$TARGET" order-pipelines -a &>/dev/null

echo ""
echo "Pipeline '$PIPELINE_NAME' deployed successfully!"
echo ""
echo "To trigger a job:"
echo "  fly -t $TARGET trigger-job -j $PIPELINE_NAME/create-release"
echo "  fly -t $TARGET trigger-job -j $PIPELINE_NAME/delete-release"
