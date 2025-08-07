#!/usr/bin/env bash

# Color definitions
export GREEN='\033[0;32m'
export CYAN='\033[0;36m'
export RED='\033[0;31m'
export YELLOW='\033[0;33m'
export NOCOLOR='\033[0m'

function info() {
    printf "${CYAN}%s\n${NOCOLOR}" "$@"
}

function warn() {
    printf "${YELLOW}%s\n${NOCOLOR}" "$@"
}

function error() {
    printf "${RED}%s\n${NOCOLOR}" "$@"
}

function completed() {
    printf "${GREEN}%s\n${NOCOLOR}" "$@"
}

function get_latest_release_tag() {
    git pull -q --all
    if ! GIT_RELEASE_TAG=$(git describe --tags "$(git rev-list --tags --max-count=1)" 2>/dev/null); then
        echo "No release tags found. Make sure to fly the release pipeline."
        exit 1
    fi
    echo "${GIT_RELEASE_TAG}"
}

function get_latest_release() {
    GIT_RELEASE_TAG=$(get_latest_release_tag)
    echo "${GIT_RELEASE_TAG##*release-v}"
}

function validate_release_param() {
    local param="$1"
    local release_prefix="release-v"

    if [ -z "$param" ]; then
        error "Error: Parameter is required"
        info "Example: release-v1.0.0"
        return 1
    fi

    if [[ ! "$param" =~ ^$release_prefix ]]; then
        error "Error: Parameter must start with '$release_prefix'"
        info "Example: release-v1.0.0"
        return 1
    fi

    # Extract the version part (remove "release-v" prefix)
    local version_part="${param#"$release_prefix"}"

    if [[ ! "$version_part" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        error "Error: Invalid semantic version format after '$release_prefix'"
        error "The version must follow the MAJOR.MINOR.PATCH format"
        info "Example: release-v1.0.0"
        return 1
    fi

    # If we've reached here, the parameter is valid
    # info "Valid release parameter: $param"

    # local major="${BASH_REMATCH[1]}"
    # local minor="${BASH_REMATCH[2]}"
    # local patch="${BASH_REMATCH[3]}"

    # info "Version breakdown: Major=$major, Minor=$minor, Patch=$patch"

    return 0
}

function compare_versions() {
    # Split versions into arrays
    IFS='.' read -ra VER1 <<<"$1"
    IFS='.' read -ra VER2 <<<"$2"

    # Compare each component
    for ((i = 0; i < ${#VER1[@]} && i < ${#VER2[@]}; i++)); do
        # Convert to integers for numeric comparison
        v1=$((10#${VER1[i]}))
        v2=$((10#${VER2[i]}))

        if [[ $v1 -gt $v2 ]]; then
            echo 1 # Version 1 is greater
            return
        elif [[ $v1 -lt $v2 ]]; then
            echo -1 # Version 2 is greater
            return
        fi
    done

    # If we get here, all components so far were equal
    # Check if one version has more components
    if [[ ${#VER1[@]} -gt ${#VER2[@]} ]]; then
        echo 1
    elif [[ ${#VER1[@]} -lt ${#VER2[@]} ]]; then
        echo -1
    else
        echo 0 # Versions are equal
    fi
}

function create_github_release() {
    local repo=$1
    local owner=${2:-Utilities-tkgieng}
    local github_token=$3
    local release_tag=$4
    local release_body=${5:-"Release $release_tag"}
    local github_api_url=${6:-"https://api.github.com"}

    curl -sL -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$github_api_url/repos/$owner/$repo/releases" \
        -d '{
            "tag_name": "'"$release_tag"'",
            "name": "'"$release_tag"'",
            "body": "'"$release_body"'",
            "draft": true,
            "prerelease": false
        }'
}

function delete_github_release() {
    local repo=$1
    local owner=${2:-Utilities-tkgieng}
    local github_token=$3
    local release_tag=$4
    local delete_release_tag=${5:-false}
    local github_api_url=${6:-"https://api.github.com"}
    local release_id
    release_id=$(curl -sL -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$github_api_url/repos/$owner/$repo/releases/tags/$release_tag" |
        jq -r '.id // empty')
    if [[ -z $release_id ]]; then
        error "Release tag: $release_tag not found in releases"
        return 1
    fi
    curl -L -X DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $github_token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$github_api_url/repos/$owner/$repo/releases/$release_id"
    if [[ "$delete_release_tag" == "true" ]]; then
        git pull --all -q
        git tag --delete "$release_tag" &>/dev/null
        git push --delete origin "$release_tag" &>/dev/null
    fi
}

function get_params_release_tags() {
    local params_repo=$1
    pushd ~/git/"$params_repo" &>/dev/null || exit
    params_release_tags=$(git tag -l)
    popd &>/dev/null || exit
    echo "${params_release_tags[@]}"
}

function validate_params_release_tag() {
    local release_tag=$1
    local params_repo=${2:-"params"}
    local params_release_tags
    for tag in $(get_params_release_tags "$params_repo"); do
        if [[ $release_tag = "$tag" ]]; then
            return 0
        fi
    done

    return 1
}

function print_valid_params_release_tags() {
    local repo=$1
    local params_repo=${2:-"params"}
    local params_release_tags
    for tag in $(get_params_release_tags "$params_repo"); do
        if [[ "$tag" =~ ^$repo ]]; then
            printf "${CYAN}> %s\n${NOCOLOR}" "${tag##*"$repo-"}"
        fi
    done
}

function update_git_release_tag() {
    local repo=$1
    local params_repo=${2:-"params"}
    local owner=${3:-"Utilities-tkgieng"}

    pushd ~/git/"$repo"/ci &>/dev/null || exit 1
    git pull -q || exit 1

    # Remove owner off repo name
    repo=${repo%%"-$owner"}

    local last_release current_release
    last_release=$(git tag -l | grep release-v | sort -V | tail -2 | head -1)
    local last_version="${last_release##*release-v}"
    current_release=$(git tag -l | grep release-v | sort -V | tail -1)
    local current_version="${current_release##*release-v}"

    info "Updating the params for the tkgi-$repo pipeline from $last_version to $current_version"
    read -rp "Do you want to continue? (y/N): " answer

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        pushd ~/git/"$params_repo" &>/dev/null || exit

        local from_version="v${last_version}"
        local to_version="v${current_version}"

        if [[ -n $(git status --porcelain) ]]; then
            read -rp "Please commit or stash your changes to params, then hit return to continue"
            if [[ -n $(git status --porcelain) ]]; then
                echo "You must commit or stash your changes to params in order to continue"
                exit 1
            fi
        fi
        git pull -q || exit 1

        # Update the git_release_tag value in params to the release that was created by the release pipeline
        find ~/git/"$params_repo" -type f \( -name "*-${repo}.yml" -o -name "*.${repo}.yaml" \) -exec grep -l "git_release_tag: release-${from_version}" {} \; -exec sed -i "s/git_release_tag: release-${from_version}/git_release_tag: release-${to_version}/g" {} \;
        git status
        git diff
        read -rp "Do you want to continue with these commits? (y/n): " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            # Commit your change to a branch and tag it (in case you ever need to rollback). Then, merge it into master.
            git checkout -b "${repo}-release-${to_version}"
            git add .
            git commit -m "Update git_release_tag from release-${from_version} to release-${to_version}

NOTICKET"
        else
            git checkout .
            return 1
        fi

        git checkout master
        git pull origin master
        git rebase "${repo}-release-${to_version}"
        git push origin master
        git branch -D "${repo}-release-${to_version}"

        # Create tag and push it
        git tag -a "${repo}-release-${to_version}" -m "Version ${repo}-release-${to_version}" || exit
        git push origin "${repo}-release-${to_version}" || exit
        popd &>/dev/null || exit
    fi

    popd &>/dev/null || exit

    return 1
}

function run_release_pipeline() {
    local foundation=$1
    local repo=$2
    local pipeline=$3
    local message_body=$4

    info "Running $pipeline pipeline..."
    read -rp "Do you want to continue? (y/n): " answer

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        pushd ~/git/"$repo"/ci &>/dev/null || exit 1
        echo "y" | ./fly.sh -f "$foundation" -r "$message_body"
        fly -t tkgi-pipeline-upgrade unpause-pipeline -p "$pipeline"
        fly -t tkgi-pipeline-upgrade trigger-job -j "$pipeline/create-final-release"
        fly -t tkgi-pipeline-upgrade watch -j "$pipeline/create-final-release"
        read -rp "Press enter to continue"
        git pull -q || exit 1
        popd &>/dev/null || exit
        return 0
    fi

    return 1
}

function run_set_pipeline() {
    local foundation=$1
    local repo=$2
    local pipeline="tkgi-$repo-$foundation-set-release-pipeline"

    info "Running $pipeline pipeline..."
    read -rp "Do you want to continue? (y/N): " answer

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        pushd ~/git/"$repo"/ci &>/dev/null || exit 1
        echo "y" | ./fly.sh -f "$foundation" -s
        fly -t "$foundation" unpause-pipeline -p "$pipeline"
        fly -t "$foundation" trigger-job -j "$pipeline/set-release-pipeline" -w
        read -rp "Press enter to continue"
        popd &>/dev/null || exit
        return 0
    fi

    return 1
}
