# GitHub Release Management

A comprehensive GitHub release management tool that provides Concourse CI/CD pipelines and helper scripts for creating and managing GitHub releases via API. Supports both GitHub.com and GitHub Enterprise instances.

## Features

- ✅ **GitHub.com & GitHub Enterprise Support** - Works with public GitHub and on-premises instances
- 🔄 **Two Pipeline Options**:
  - **Basic Pipeline** - Flexible configuration for development/testing
  - **Enterprise Pipeline** - Strict configuration management with mandatory Vault integration
- 🛠️ **Flexible Configuration** - Support for params files, command-line flags, and environment variables (basic pipeline)
- 🔒 **Enterprise Security** - Mandatory Vault integration for secrets, locked infrastructure configuration (enterprise pipeline)
- 📦 **Container Support** - Optional S3-backed container image management
- 🔧 **Helper Scripts** - Standalone utilities for release management
- ✨ **Interactive Setup** - Enterprise credential mapping tool for existing Vault structures

## Which Pipeline Should I Use?

| Use Case | Recommended Pipeline | Deploy Script |
|----------|---------------------|---------------|
| **Production Releases** | Enterprise Pipeline | `fly-enterprise.sh` |
| **Regulated Environments** | Enterprise Pipeline | `fly-enterprise.sh` |
| **Development/Testing** | Basic Pipeline | `fly.sh` |
| **Quick Prototypes** | Basic Pipeline | `fly.sh` |
| **Strict Compliance** | Enterprise Pipeline | `fly-enterprise.sh` |
| **GitHub Enterprise** | Enterprise Pipeline | `fly-enterprise.sh` |

## Quick Start

### 1. Choose Your Pipeline

#### Basic Pipeline (Recommended)

For simple release workflows without container dependencies:

```bash
# Copy and customize configuration
cp params-simple.yml.example params.yml

# Deploy pipeline
./ci/fly.sh -t my-concourse-target --params ./params.yml
```

#### S3 Container Pipeline

For advanced workflows with container image management:

```bash
# Copy and customize configuration  
cp params.yml.example params.yml

# Deploy pipeline
./ci/fly-s3.sh -t my-concourse-target --params ./params.yml
```

### 2. GitHub Enterprise Setup

**📘 For comprehensive GitHub Enterprise setup, see [GITHUB-ENTERPRISE-SETUP.md](GITHUB-ENTERPRISE-SETUP.md)**

#### Quick Start for Enterprise Users

**Option 1: Enterprise Pipeline (Production)**

```bash
# Setup with your existing Vault credentials
./setup-enterprise.sh --interactive

# Deploy with strict configuration management
./ci/fly-enterprise.sh -t production --params ./params.yml
```

**Option 2: Basic Pipeline (Development)**

```bash
# Copy enterprise template
cp params-github-enterprise.yml.example params.yml
# Edit and deploy
./ci/fly.sh -t my-target --params ./params.yml
```

## Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `owner` | GitHub repository owner/organization | `myorg` |
| `repository` | GitHub repository name | `myrepo` |
| `github_token` | GitHub access token | `ghp_xxxx` or `((vault-token))` |
| `git_uri` | Git repository URI | `git@github.com:org/repo.git` |
| `git_private_key` | SSH private key for git access | `-----BEGIN RSA PRIVATE KEY-----...` |

### GitHub Enterprise Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `github_api_url` | GitHub API base URL | `https://api.github.com` |

**Examples:**

- GitHub.com: `https://api.github.com`
- GitHub Enterprise: `https://github3.company.com/api/v3`
- Generic Enterprise: `https://github.acme.com/api/v3`

### Optional Release Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `release_tag` | Git tag for release | `v1.0.0` |
| `release_name` | Display name for release | Same as tag |
| `release_body` | Release description/notes | `Release {tag}` |
| `is_draft` | Create as draft release | `false` |
| `is_prerelease` | Mark as pre-release | `false` |

### Container Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `container_image_repository` | Container image repository | `ubuntu` |
| `container_image_tag` | Container image tag | `22.04` |

**Container Options:**

- **Ubuntu**: `ubuntu:22.04` (recommended - LTS with package manager)
- **Alpine**: `alpine:latest` (minimal, requires apk packages)
- **Custom**: Build your own using provided `Dockerfile`

## Usage Examples

### Command Line Deployment

```bash
# Basic deployment with flags
./ci/fly.sh -t my-target \
  --owner myorg \
  --repository myrepo \
  --github-token $GITHUB_TOKEN \
  --git-uri git@github.com:myorg/myrepo.git

# GitHub Enterprise deployment
./ci/fly.sh -t my-target \
  --github-api-url https://github3.company.com/api/v3 \
  --owner myorg \
  --repository myrepo \
  --github-token $GITHUB_TOKEN

# Override specific parameters
./ci/fly.sh -t my-target \
  --params ./params.yml \
  --release-tag v2.0.0 \
  --is-prerelease
```

### Environment Variables

```bash
# Set environment variables
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
export GITHUB_API_URL=https://github3.company.com/api/v3
export GIT_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)"

# Deploy with environment variables
./ci/fly.sh -t my-target --params ./params.yml
```

### Pipeline Jobs

Once deployed, trigger pipeline jobs:

```bash
# Create a release
fly -t my-target trigger-job -j gh-release/create-release

# Delete a release  
fly -t my-target trigger-job -j gh-release/delete-release
```

## Container Management

### Building Custom Container

```bash
# Build locally
./scripts/build-container.sh --load

# Build and push to registry
./scripts/build-container.sh --push --registry myregistry.com

# Test container functionality
./scripts/test-container.sh --image ubuntu:22.04 --mode basic
```

### Using Custom Container

```bash
# Deploy with custom container
./ci/fly.sh -t my-target \
  --container-repository myregistry.com/gh-release-tools \
  --container-tag latest \
  --params ./params.yml

# Or set in params file
container_image_repository: myregistry.com/gh-release-tools
container_image_tag: latest
```

### Local Development

```bash
# Start development environment
docker-compose up -d gh-release-container

# Test in container
docker-compose exec gh-release-container bash
```

## Helper Scripts

### Standalone Release Management

```bash
# Source helper functions
source scripts/release-helpers.sh

# Create a GitHub release
create_github_release repo owner token tag "Release notes" "https://api.github.com"

# Delete a GitHub release
delete_github_release repo owner token tag false "https://api.github.com"

# Validate release tag format
validate_release_param "release-v1.0.0"

# Get latest release tag
latest_tag=$(get_latest_release_tag)
```

### Version Management

```bash
# Compare version numbers
result=$(compare_versions "1.2.3" "1.2.4")
# Returns: -1 (first is smaller), 0 (equal), 1 (first is larger)
```

## Pipeline Architecture

### Basic Pipeline (`pipeline.yml`)

- Uses `registry-image` resource for container management
- Default container: `ubuntu:22.04` with required tools
- Can be overridden with custom container images
- Suitable for most release workflows
- Automatically installs curl, jq, git, bash if needed

### S3 Container Pipeline (`pipeline-s3-container.yml`)

- S3-backed container images
- Worker tag support
- Advanced container management
- Requires S3 bucket configuration

### Task Structure

Both pipelines include these jobs:

1. **create-release**: Creates GitHub releases
   - Fetches repository code
   - Executes release creation task
   - Supports drafts and pre-releases

2. **delete-release**: Removes GitHub releases
   - Fetches repository code
   - Finds release by tag
   - Deletes the specified release

## Configuration Templates

| Template | Use Case |
|----------|----------|
| `params-simple.yml.example` | Basic pipeline configuration |
| `params.yml.example` | S3 container pipeline configuration |
| `params-github-enterprise.yml.example` | GitHub Enterprise specific configuration |

## Dependencies

- **Concourse CI** - CI/CD platform
- **fly CLI** - Concourse command-line tool
- **jq** - JSON processor
- **curl** - HTTP client
- **git** - Version control
- **bash** - Shell scripting

## Security Considerations

⚠️ **CRITICAL: Never put secrets in params files!**

### Credential Management

- **ALWAYS use Concourse credential management** for secrets:
  - `github_token: ((vault-github-token))`  ✅
  - `git_private_key: ((vault-ssh-private-key))` ✅
  - `github_token: ghp_xxxxxxxxxxxx` ❌ **NEVER**
- Store all sensitive data in your Concourse credential store (Vault, CredHub, etc.)
- Use environment variables for local development only
- Never commit tokens or private keys to repository

### Best Practices

- Use SSH keys for git authentication
- Use least-privilege access for GitHub tokens
- Rotate credentials regularly
- Use separate tokens for different environments

## Troubleshooting

### Common Issues

1. **Pipeline deployment fails**

   ```bash
   # Check Concourse target
   fly -t my-target login
   
   # Verify parameters
   ./ci/fly.sh -h
   ```

2. **GitHub API errors**

   ```bash
   # Test API connectivity
   curl -H "Authorization: Bearer $GITHUB_TOKEN" \
        https://api.github.com/user
   
   # For GitHub Enterprise
   curl -H "Authorization: Bearer $GITHUB_TOKEN" \
        https://github3.company.com/api/v3/user
   ```

3. **Release creation fails**
   - Verify token has repository write permissions
   - Check if release tag already exists
   - Ensure API URL is correct for your GitHub instance

4. **Git authentication issues**
   - Verify SSH key has repository access
   - Check git URI format matches your GitHub instance
   - Test SSH connection: `ssh -T git@github.com`

### Debug Mode

Enable verbose output in tasks:

```bash
# Add to task params
DEBUG: "true"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test
4. Run shellcheck on all scripts: `find . -name "*.sh" -exec shellcheck {} \;`
5. Update documentation
6. Submit pull request

## License

This project is part of internal tooling. See your organization's licensing guidelines.
