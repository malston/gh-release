#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Install required packages if not available
if ! command -v curl &> /dev/null; then
    echo "Installing required packages..."
    apt-get update -qq
    apt-get install -y -qq curl jq git ca-certificates
fi

function main() {
    local github_token="${GITHUB_TOKEN:?}"
    local owner="${OWNER:?}"
    local repository="${REPOSITORY:?}"
    local release_tag="${RELEASE_TAG:?}"
    local release_name="${RELEASE_NAME:-$release_tag}"
    local release_body="${RELEASE_BODY:-Release $release_tag}"
    local is_draft="${IS_DRAFT:-false}"
    local is_prerelease="${IS_PRERELEASE:-false}"
    local github_api_url="${GITHUB_API_URL:-https://api.github.com}"

    echo "Creating GitHub release for $owner/$repository"
    echo "  API URL: $github_api_url"
    echo "  Tag: $release_tag"
    echo "  Name: $release_name"
    echo "  Draft: $is_draft"
    echo "  Pre-release: $is_prerelease"

    # Create JSON payload using jq to ensure proper formatting
    local json_payload
    json_payload=$(jq -n \
        --arg tag_name "$release_tag" \
        --arg name "$release_name" \
        --arg body "$release_body" \
        --argjson draft "$is_draft" \
        --argjson prerelease "$is_prerelease" \
        '{
            tag_name: $tag_name,
            name: $name,
            body: $body,
            draft: $draft,
            prerelease: $prerelease
        }')

    echo "JSON payload:"
    echo "$json_payload"

    local response
    response=$(curl -sL -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/json" \
        "$github_api_url/repos/$owner/$repository/releases" \
        -d "$json_payload")

    if echo "$response" | grep -q '"id"'; then
        echo "✓ Release created successfully"
        echo "$response" | jq -r '.html_url // empty' || true
    else
        echo "✗ Failed to create release"
        echo "$response"
        exit 1
    fi
}

main "$@"
