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
    local delete_tag="${DELETE_TAG:-false}"
    local github_api_url="${GITHUB_API_URL:-https://api.github.com}"

    echo "Deleting GitHub release for $owner/$repository"
    echo "  API URL: $github_api_url"
    echo "  Tag: $release_tag"
    echo "  Delete tag: $delete_tag"

    # First, get the release ID by tag
    local release_info
    release_info=$(curl -sL \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$github_api_url/repos/$owner/$repository/releases/tags/$release_tag")

    local release_id
    release_id=$(echo "$release_info" | jq -r '.id // empty')

    if [[ -z "$release_id" ]]; then
        echo "✗ Release with tag '$release_tag' not found"
        exit 1
    fi

    echo "Found release ID: $release_id"

    # Delete the release
    local response
    response=$(curl -sL -X DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -w "\n%{http_code}" \
        "$github_api_url/repos/$owner/$repository/releases/$release_id")

    local http_code
    http_code=$(echo "$response" | tail -n 1)
    local body
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" == "204" ]]; then
        echo "✓ Release deleted successfully"

        # Optionally delete the Git tag
        if [[ "$delete_tag" == "true" ]]; then
            echo "Deleting Git tag: $release_tag"
            local tag_response
            tag_response=$(curl -sL -X DELETE \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer $github_token" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                -w "\n%{http_code}" \
                "$github_api_url/repos/$owner/$repository/git/refs/tags/$release_tag")

            local tag_http_code
            tag_http_code=$(echo "$tag_response" | tail -n 1)
            local tag_body
            tag_body=$(echo "$tag_response" | head -n -1)

            if [[ "$tag_http_code" == "204" ]]; then
                echo "✓ Git tag deleted successfully"
            else
                echo "⚠ Warning: Failed to delete Git tag (HTTP $tag_http_code)"
                [[ -n "$tag_body" ]] && echo "$tag_body"
                # Don't exit on tag deletion failure, release deletion was successful
            fi
        fi
    else
        echo "✗ Failed to delete release (HTTP $http_code)"
        [[ -n "$body" ]] && echo "$body"
        exit 1
    fi
}

main "$@"
