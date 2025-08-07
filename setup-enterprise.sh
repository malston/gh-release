#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
GitHub Release Management - Enterprise Pipeline Setup

This script helps you customize the enterprise pipeline to use your existing
Vault credential names instead of the default ones.

Usage:
    $0 [OPTIONS]

Options:
    --output <file>          Output file for customized pipeline [default: ci/pipelines/pipeline-enterprise-custom.yml]
    --interactive           Interactive mode (prompts for each credential)
    --batch                 Batch mode (uses command line flags or defaults)
    -h, --help              Display this help message

Credential Mapping Flags (batch mode):
    --github-token-path <path>      Vault path for GitHub token [default: vault-github-token]
    --ssh-key-path <path>           Vault path for SSH private key [default: vault-ssh-private-key]
    --s3-access-key-path <path>     Vault path for S3 access key [default: vault-s3-access-key]
    --s3-secret-key-path <path>     Vault path for S3 secret key [default: vault-s3-secret-key]

Examples:
    # Interactive setup (recommended)
    $0 --interactive

    # Batch mode with custom credential paths
    $0 --batch \\
        --github-token-path "company/github/api-token" \\
        --ssh-key-path "company/ssh/deployment-key" \\
        --s3-access-key-path "company/s3/access-key" \\
        --s3-secret-key-path "company/s3/secret-key"

    # Use existing credential names and generate custom pipeline
    $0 --output ci/pipelines/my-custom-pipeline.yml --interactive

EOF
}

# Default credential paths
DEFAULT_GITHUB_TOKEN="vault-github-token"
DEFAULT_SSH_KEY="vault-ssh-private-key"
DEFAULT_S3_ACCESS_KEY="vault-s3-access-key"
DEFAULT_S3_SECRET_KEY="vault-s3-secret-key"

# User-provided credential paths
GITHUB_TOKEN_PATH=""
SSH_KEY_PATH=""
S3_ACCESS_KEY_PATH=""
S3_SECRET_KEY_PATH=""

# Script configuration
OUTPUT_FILE="ci/pipelines/pipeline-enterprise-custom.yml"
INTERACTIVE_MODE=false
BATCH_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        --batch)
            BATCH_MODE=true
            shift
            ;;
        --github-token-path)
            GITHUB_TOKEN_PATH="$2"
            shift 2
            ;;
        --ssh-key-path)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --s3-access-key-path)
            S3_ACCESS_KEY_PATH="$2"
            shift 2
            ;;
        --s3-secret-key-path)
            S3_SECRET_KEY_PATH="$2"
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

# Validate mode selection
if [[ "$INTERACTIVE_MODE" == "true" && "$BATCH_MODE" == "true" ]]; then
    printf "${RED}Error: Cannot use both --interactive and --batch modes${NC}\n"
    exit 1
fi

# Default to interactive mode if neither specified
if [[ "$INTERACTIVE_MODE" == "false" && "$BATCH_MODE" == "false" ]]; then
    INTERACTIVE_MODE=true
fi

print_header() {
    printf "${BLUE}=========================================${NC}\n"
    printf "${BLUE}GitHub Release Pipeline - Enterprise Setup${NC}\n"
    printf "${BLUE}=========================================${NC}\n"
    echo ""
    echo "This script will help you customize the enterprise pipeline to use"
    echo "your existing Vault credential names."
    echo ""
    printf "${YELLOW}Current default credential paths:${NC}\n"
    echo "  • GitHub Token: ((${DEFAULT_GITHUB_TOKEN}))"
    echo "  • SSH Private Key: ((${DEFAULT_SSH_KEY}))"
    echo "  • S3 Access Key: ((${DEFAULT_S3_ACCESS_KEY}))"
    echo "  • S3 Secret Key: ((${DEFAULT_S3_SECRET_KEY}))"
    echo ""
}

prompt_for_credentials() {
    printf "${BLUE}=== Credential Path Configuration ===${NC}\n"
    echo ""

    # GitHub Token
    printf "${YELLOW}GitHub Token:${NC}\n"
    echo "Enter the Vault path for your GitHub access token."
    echo "Examples: 'company/github/api-token', 'secrets/gh-token', 'vault-github-token'"
    echo ""
    read -p "GitHub Token path [default: ${DEFAULT_GITHUB_TOKEN}]: " input
    GITHUB_TOKEN_PATH="${input:-$DEFAULT_GITHUB_TOKEN}"
    echo ""

    # SSH Private Key
    printf "${YELLOW}SSH Private Key:${NC}\n"
    echo "Enter the Vault path for your SSH private key (for Git access)."
    echo "Examples: 'company/ssh/deploy-key', 'secrets/ssh-key', 'vault-ssh-private-key'"
    echo ""
    read -p "SSH Private Key path [default: ${DEFAULT_SSH_KEY}]: " input
    SSH_KEY_PATH="${input:-$DEFAULT_SSH_KEY}"
    echo ""

    # S3 Access Key
    printf "${YELLOW}S3 Access Key:${NC}\n"
    echo "Enter the Vault path for your S3 access key ID."
    echo "Examples: 'company/s3/access-key', 'secrets/s3-access', 'vault-s3-access-key'"
    echo ""
    read -p "S3 Access Key path [default: ${DEFAULT_S3_ACCESS_KEY}]: " input
    S3_ACCESS_KEY_PATH="${input:-$DEFAULT_S3_ACCESS_KEY}"
    echo ""

    # S3 Secret Key
    printf "${YELLOW}S3 Secret Key:${NC}\n"
    echo "Enter the Vault path for your S3 secret access key."
    echo "Examples: 'company/s3/secret-key', 'secrets/s3-secret', 'vault-s3-secret-key'"
    echo ""
    read -p "S3 Secret Key path [default: ${DEFAULT_S3_SECRET_KEY}]: " input
    S3_SECRET_KEY_PATH="${input:-$DEFAULT_S3_SECRET_KEY}"
    echo ""
}

set_batch_defaults() {
    GITHUB_TOKEN_PATH="${GITHUB_TOKEN_PATH:-$DEFAULT_GITHUB_TOKEN}"
    SSH_KEY_PATH="${SSH_KEY_PATH:-$DEFAULT_SSH_KEY}"
    S3_ACCESS_KEY_PATH="${S3_ACCESS_KEY_PATH:-$DEFAULT_S3_ACCESS_KEY}"
    S3_SECRET_KEY_PATH="${S3_SECRET_KEY_PATH:-$DEFAULT_S3_SECRET_KEY}"
}

confirm_configuration() {
    printf "${BLUE}=== Configuration Summary ===${NC}\n"
    echo ""
    printf "${YELLOW}Your credential mappings:${NC}\n"
    echo "  • GitHub Token: (($GITHUB_TOKEN_PATH))"
    echo "  • SSH Private Key: (($SSH_KEY_PATH))"
    echo "  • S3 Access Key: (($S3_ACCESS_KEY_PATH))"
    echo "  • S3 Secret Key: (($S3_SECRET_KEY_PATH))"
    echo ""
    printf "${YELLOW}Output file:${NC} $OUTPUT_FILE\n"
    echo ""

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        read -p "Continue with this configuration? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Setup cancelled"
            exit 0
        fi
    fi
}

generate_custom_pipeline() {
    local template_file="$__DIR/ci/pipelines/pipeline-enterprise.yml"

    if [[ ! -f "$template_file" ]]; then
        printf "${RED}Error: Template file not found: $template_file${NC}\n"
        exit 1
    fi

    printf "${BLUE}Generating customized pipeline...${NC}\n"

    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT_FILE")"

    # Create the customized pipeline by replacing credential references
    sed \
        -e "s/((concourse_s3_access_key_id))/(($S3_ACCESS_KEY_PATH))/g" \
        -e "s/((concourse_s3_secret_access_key))/(($S3_SECRET_KEY_PATH))/g" \
        -e "s/((git_private_key))/(($SSH_KEY_PATH))/g" \
        -e "s/((github_token))/(($GITHUB_TOKEN_PATH))/g" \
        "$template_file" > "$OUTPUT_FILE"

    # Add header comment to the generated file
    local temp_file=$(mktemp)
    cat > "$temp_file" <<EOF
# GitHub Release Pipeline - Enterprise (Customized)
# Generated by setup-enterprise.sh on $(date)
#
# Customized credential mappings:
#   GitHub Token: (($GITHUB_TOKEN_PATH))
#   SSH Private Key: (($SSH_KEY_PATH))
#   S3 Access Key: (($S3_ACCESS_KEY_PATH))
#   S3 Secret Key: (($S3_SECRET_KEY_PATH))
#
# To use this pipeline:
#   fly -t my-target set-pipeline -p my-pipeline -c $OUTPUT_FILE --load-vars-from params.yml
#

EOF

    cat "$OUTPUT_FILE" >> "$temp_file"
    mv "$temp_file" "$OUTPUT_FILE"
}

print_completion_message() {
    echo ""
    printf "${GREEN}✓ Custom enterprise pipeline generated successfully!${NC}\n"
    echo ""
    printf "${YELLOW}Next steps:${NC}\n"
    echo ""
    echo "1. Review the generated pipeline:"
    printf "   ${BLUE}cat $OUTPUT_FILE${NC}\n"
    echo ""
    echo "2. Ensure your credentials exist in Vault:"
    printf "   ${BLUE}• (($GITHUB_TOKEN_PATH)) - GitHub access token${NC}\n"
    printf "   ${BLUE}• (($SSH_KEY_PATH)) - SSH private key${NC}\n"
    printf "   ${BLUE}• (($S3_ACCESS_KEY_PATH)) - S3 access key ID${NC}\n"
    printf "   ${BLUE}• (($S3_SECRET_KEY_PATH)) - S3 secret access key${NC}\n"
    echo ""
    echo "3. Deploy the customized pipeline:"
    printf "   ${BLUE}./ci/fly-enterprise.sh -t my-target --params params.yml${NC}\n"
    echo ""
    echo "4. To use the custom pipeline file specifically:"
    printf "   ${BLUE}fly -t my-target set-pipeline -p my-pipeline -c $OUTPUT_FILE -l params.yml${NC}\n"
    echo ""
    printf "${YELLOW}Note: You can always re-run this setup script to update your credential mappings.${NC}\n"
}

main() {
    print_header

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        prompt_for_credentials
    else
        set_batch_defaults
    fi

    confirm_configuration
    generate_custom_pipeline
    print_completion_message
}

main "$@"
