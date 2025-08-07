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
Vault credential names instead of the default ones. It can also create or
regenerate the params.yml file from the enterprise template.

Usage:
    $0 [OPTIONS]

Options:
    --output <file>         Output file for customized pipeline [default: ci/pipelines/pipeline-enterprise-custom.yml]
    --interactive           Interactive mode (prompts for each credential)
    --batch                 Batch mode (uses command line flags or defaults)
    -h, --help              Display this help message

Credential Mapping Flags (batch mode):
    --github-token-path <path>      Vault path for GitHub token [default: vault-github-token]
    --ssh-key-path <path>           Vault path for SSH private key [default: vault-ssh-private-key]
    --s3-access-key-path <path>     Vault path for S3 access key [default: vault-s3-access-key]
    --s3-secret-key-path <path>     Vault path for S3 secret key [default: vault-s3-secret-key]

Examples:
    # Interactive setup (recommended) - will offer to create/regenerate params.yml
    $0 --interactive

    # Batch mode with custom credential paths
    $0 --batch \\
        --github-token-path "company/github/api-token" \\
        --ssh-key-path "company/ssh/deployment-key" \\
        --s3-access-key-path "company/s3/access-key" \\
        --s3-secret-key-path "company/s3/secret-key"

    # Use existing credential names and generate custom pipeline
    $0 --output ci/pipelines/my-custom-pipeline.yml --interactive

Note: Interactive mode will check for params.yml and offer to create it from
the enterprise template if it doesn't exist, or regenerate it if desired.

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
    echo -e "${RED}Error: Cannot use both --interactive and --batch modes${NC}"
    exit 1
fi

# Default to interactive mode if neither specified
if [[ "$INTERACTIVE_MODE" == "false" && "$BATCH_MODE" == "false" ]]; then
    INTERACTIVE_MODE=true
fi

print_header() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}GitHub Release Pipeline - Enterprise Setup${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo "This script will help you customize the enterprise pipeline to use"
    echo "your existing Vault credential names."
    echo ""
    echo -e "${YELLOW}Current default credential paths:${NC}"
    echo "  • GitHub Token: ((${DEFAULT_GITHUB_TOKEN}))"
    echo "  • SSH Private Key: ((${DEFAULT_SSH_KEY}))"
    echo "  • S3 Access Key: ((${DEFAULT_S3_ACCESS_KEY}))"
    echo "  • S3 Secret Key: ((${DEFAULT_S3_SECRET_KEY}))"
    echo ""
}

check_params_file() {
    echo ""
    echo -e "${BLUE}=== Parameter File Setup ===${NC}"
    echo ""
    
    if [[ -f "params.yml" ]]; then
        echo -e "${YELLOW}Warning: params.yml already exists.${NC}"
        echo ""
        echo "Would you like to:"
        echo "1) Keep existing params.yml file"
        echo "2) Regenerate params.yml from enterprise template"
        echo ""
        read -r -p "Choose option (1 or 2) [default: 1]: " choice
        choice=${choice:-1}
        
        if [[ "$choice" == "2" ]]; then
            create_params_file
        else
            echo ""
            echo -e "${GREEN}✓ Keeping existing params.yml${NC}"
        fi
    else
        echo -e "${YELLOW}No params.yml file found.${NC}"
        echo ""
        read -r -p "Create params.yml from enterprise template? (y/N): " create_params
        
        if [[ $create_params =~ ^[Yy]$ ]]; then
            create_params_file
        else
            echo ""
            echo -e "${YELLOW}Note: You'll need to create params.yml manually or run 'make example-params'${NC}"
        fi
    fi
    echo ""
}

create_params_file() {
    local template_file="params-github-enterprise.yml.example"
    
    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}Error: Template file not found: $template_file${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}Creating params.yml from enterprise template...${NC}"
    
    # Backup existing file if it exists
    if [[ -f "params.yml" ]]; then
        cp "params.yml" "params.yml.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Backed up existing params.yml${NC}"
    fi
    
    # Copy template to params.yml
    cp "$template_file" "params.yml"
    echo -e "${GREEN}✓ Created params.yml from enterprise template${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Edit params.yml to customize for your environment"
    echo "2. Update repository owner, name, and URLs"
    echo "3. Ensure all secrets use Vault credential references"
    echo ""
}

prompt_for_credentials() {
    echo -e "${BLUE}=== Credential Path Configuration ===${NC}"
    echo ""

    # GitHub Token
    echo -e "${YELLOW}GitHub Token:${NC}"
    echo "Enter the Vault path for your GitHub access token."
    echo "Examples: 'company/github/api-token', 'secrets/gh-token', 'vault-github-token'"
    echo ""
    read -r -p "GitHub Token path [default: ${DEFAULT_GITHUB_TOKEN}]: " input
    GITHUB_TOKEN_PATH="${input:-$DEFAULT_GITHUB_TOKEN}"
    echo ""

    # SSH Private Key
    echo -e "${YELLOW}SSH Private Key:${NC}"
    echo "Enter the Vault path for your SSH private key (for Git access)."
    echo "Examples: 'company/ssh/deploy-key', 'secrets/ssh-key', 'vault-ssh-private-key'"
    echo ""
    read -r -p "SSH Private Key path [default: ${DEFAULT_SSH_KEY}]: " input
    SSH_KEY_PATH="${input:-$DEFAULT_SSH_KEY}"
    echo ""

    # S3 Access Key
    echo -e "${YELLOW}S3 Access Key:${NC}"
    echo "Enter the Vault path for your S3 access key ID."
    echo "Examples: 'company/s3/access-key', 'secrets/s3-access', 'vault-s3-access-key'"
    echo ""
    read -r -p "S3 Access Key path [default: ${DEFAULT_S3_ACCESS_KEY}]: " input
    S3_ACCESS_KEY_PATH="${input:-$DEFAULT_S3_ACCESS_KEY}"
    echo ""

    # S3 Secret Key
    echo -e "${YELLOW}S3 Secret Key:${NC}"
    echo "Enter the Vault path for your S3 secret access key."
    echo "Examples: 'company/s3/secret-key', 'secrets/s3-secret', 'vault-s3-secret-key'"
    echo ""
    read -r -p "S3 Secret Key path [default: ${DEFAULT_S3_SECRET_KEY}]: " input
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
    echo -e "${BLUE}=== Configuration Summary ===${NC}"
    echo ""
    echo -e "${YELLOW}Your credential mappings:${NC}"
    echo "  • GitHub Token: (($GITHUB_TOKEN_PATH))"
    echo "  • SSH Private Key: (($SSH_KEY_PATH))"
    echo "  • S3 Access Key: (($S3_ACCESS_KEY_PATH))"
    echo "  • S3 Secret Key: (($S3_SECRET_KEY_PATH))"
    echo ""
    echo -e "${YELLOW}Output file:${NC} $OUTPUT_FILE"
    echo ""

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        read -r -p "Continue with this configuration? (y/N): " -n 1 REPLY
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
        echo -e "${RED}Error: Template file not found: $template_file${NC}"
        exit 1
    fi

    echo -e "${BLUE}Generating customized pipeline...${NC}"

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
    local temp_file
    temp_file=$(mktemp)
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
    echo -e "${GREEN}✓ Custom enterprise pipeline generated successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo ""
    echo "1. Review the generated pipeline:"
    echo -e "   ${BLUE}cat $OUTPUT_FILE${NC}"
    echo ""
    echo "2. Ensure your credentials exist in Vault:"
    echo -e "   ${BLUE}• (($GITHUB_TOKEN_PATH)) - GitHub access token${NC}"
    echo -e "   ${BLUE}• (($SSH_KEY_PATH)) - SSH private key${NC}"
    echo -e "   ${BLUE}• (($S3_ACCESS_KEY_PATH)) - S3 access key ID${NC}"
    echo -e "   ${BLUE}• (($S3_SECRET_KEY_PATH)) - S3 secret access key${NC}"
    echo ""
    echo "3. Deploy the customized pipeline:"
    echo -e "   ${BLUE}./ci/fly-enterprise.sh -t my-target --params params.yml${NC}"
    echo ""
    echo "4. To use the custom pipeline file specifically:"
    echo -e "   ${BLUE}fly -t my-target set-pipeline -p my-pipeline -c $OUTPUT_FILE -l params.yml${NC}"
    echo ""
    echo -e "${YELLOW}Note: You can always re-run this setup script to update your credential mappings.${NC}"
}

main() {
    print_header

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        check_params_file
        prompt_for_credentials
    else
        set_batch_defaults
    fi

    confirm_configuration
    generate_custom_pipeline
    print_completion_message
}

main "$@"
