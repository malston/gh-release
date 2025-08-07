# GitHub Enterprise Setup Guide

This guide provides comprehensive instructions for configuring the GitHub Release Management tool with GitHub Enterprise instances, including the enterprise-grade pipeline with strict configuration management and Vault integration.

## Quick Setup Options

### Option 1: Enterprise Pipeline (Recommended for Production)

The enterprise pipeline enforces strict configuration management with all infrastructure settings in params files and secrets in Vault.

#### 1. Setup Custom Credential Mappings

If your organization already has credentials in Vault with different naming conventions:

```bash
# Interactive setup to map your existing credential names
./setup-enterprise.sh --interactive
```

#### 2. Configure Parameters

```bash
cp params-github-enterprise.yml.example params.yml
# Edit params.yml with your non-sensitive configuration
```

#### 3. Deploy Enterprise Pipeline

```bash
./ci/fly-enterprise.sh -t your-concourse-target --params ./params.yml
```

### Option 2: Basic Pipeline (Development/Testing)

For development or testing environments with more flexibility:

```bash
cp params-github-enterprise.yml.example params.yml
# Edit params.yml and deploy
./ci/fly.sh -t your-concourse-target --params ./params.yml
```

## Enterprise Pipeline Features

### Strict Configuration Management

The enterprise pipeline (`fly-enterprise.sh` and `pipeline-enterprise.yml`) provides:

#### **Mandatory Vault Integration**

All secrets MUST be stored in Vault:

- `github_token` - GitHub access token
- `git_private_key` - SSH private key for repository access
- `concourse_s3_access_key_id` - S3 access key for container images
- `concourse_s3_secret_access_key` - S3 secret key

#### **Configuration Lockdown**

- **No CLI overrides** for infrastructure settings (GitHub, Git, S3)
- **Params file required** - Cannot run without proper configuration
- **Release parameters only** can be overridden via CLI (tag, name, draft status)

#### **Custom Credential Mapping**

Use `setup-enterprise.sh` to map your existing Vault paths:

```bash
# Example: Your organization uses different Vault paths
./setup-enterprise.sh --batch \
  --github-token-path "secrets/github/api-token" \
  --ssh-key-path "secrets/ssh/deploy-key" \
  --s3-access-key-path "aws/s3/access-key" \
  --s3-secret-key-path "aws/s3/secret-key"
```

This generates a customized pipeline file with your credential paths.

### Comparison: Basic vs Enterprise Pipeline

| Feature | Basic Pipeline | Enterprise Pipeline |
|---------|---------------|-------------------|
| **Configuration Source** | CLI, Environment, Params | Params File Only |
| **Secret Management** | Flexible | Vault Required |
| **GitHub Settings** | Can override via CLI | Locked to params |
| **Git Settings** | Can override via CLI | Locked to params |
| **SSH Key** | Auto-detect, CLI, Env | Vault Only |
| **S3 Configuration** | N/A | Locked to params |
| **Release Parameters** | Flexible | CLI override allowed |
| **Use Case** | Development, Testing | Production, Regulated |

## Enterprise-Specific Configurations

### ACME Corporation Example

```yaml
github_api_url: https://github.acme.com/api/v3
git_uri: git@github.acme.com:myorg/myrepo.git
```

### Generic Enterprise Example

```yaml
github_api_url: https://github.acme.com/api/v3
git_uri: git@github.acme.com:myorg/myrepo.git
```

## URL Patterns

### API URLs

| Type | Pattern | Example |
|------|---------|---------|
| GitHub.com | `https://api.github.com` | Default |
| GitHub Enterprise | `https://your-domain/api/v3` | `https://github3.company.com/api/v3` |

### Git URLs

| Type | Pattern | Example |
|------|---------|---------|
| GitHub.com | `git@github.com:org/repo.git` | Default |
| GitHub Enterprise | `git@your-domain:org/repo.git` | `git@github3.company.com:org/repo.git` |

## Command Line Usage

### Using Parameters File

```bash
# Deploy with enterprise params
./ci/fly.sh -t target --params ./params.yml

# Override specific values
./ci/fly.sh -t target --params ./params.yml \
  --github-api-url https://github3.company.com/api/v3
```

### Using Command Line Flags

```bash
./ci/fly.sh -t target \
  --github-api-url https://github3.company.com/api/v3 \
  --owner myorg \
  --repository myrepo \
  --github-token $GITHUB_ENTERPRISE_TOKEN
```

### Using Environment Variables

```bash
export GITHUB_API_URL=https://github3.company.com/api/v3
export GITHUB_TOKEN=your_enterprise_token

./ci/fly.sh -t target --params ./params.yml
```

## Testing Connectivity

### Test GitHub API Access

```bash
# Test API connectivity
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     https://github3.company.com/api/v3/user

# Test with container
GITHUB_TOKEN=$GITHUB_TOKEN \
GITHUB_API_URL=https://github3.company.com/api/v3 \
./scripts/test-container.sh --image ubuntu:22.04 --mode github
```

### Test SSH Access

```bash
# Test SSH connectivity to enterprise instance
ssh -T git@github3.company.com
```

## Troubleshooting

### Common Issues

1. **SSL Certificate Issues**
   - Enterprise instances may use self-signed certificates
   - Add certificates to container or set `GIT_SSL_NO_VERIFY=true` for testing

2. **Network Connectivity**
   - Ensure Concourse workers can access enterprise instance
   - Check firewall rules and proxy settings

3. **Authentication**
   - Verify GitHub Enterprise token has required permissions
   - Test token with curl before using in pipeline

### Debug Steps

```bash
# 1. Test API connectivity
curl -v -H "Authorization: Bearer $GITHUB_TOKEN" \
     https://github3.company.com/api/v3/user

# 2. Test repository access
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
     https://github3.company.com/api/v3/repos/org/repo

# 3. Test SSH key
ssh -vT git@github3.company.com
```

## Security Considerations

⚠️ **CRITICAL: Never put secrets in params files!**

### Token Management

- **ALWAYS use Concourse credential management** for all secrets:

  ```yaml
  github_token: ((vault-github-enterprise-token))  ✅ SECURE
  git_private_key: ((vault-ssh-private-key))       ✅ SECURE
  ```

- **NEVER put actual tokens in params files:**

  ```yaml
  github_token: ghp_xxxxxxxxxxxx                   ❌ INSECURE
  git_private_key: |                               ❌ INSECURE
    -----BEGIN RSA PRIVATE KEY-----
  ```

- Use Concourse vault/credential management for all secrets
- Never commit enterprise tokens to repository
- Use least-privilege tokens (only repository write access needed)

### Network Security

- Enterprise instances often have additional network restrictions
- Ensure Concourse workers have appropriate network access
- Consider using VPN or private networking for sensitive instances

## Container Considerations

### Custom Certificates

If your enterprise instance uses custom certificates, you may need to:

1. **Build custom container** with certificates:

```dockerfile
FROM ubuntu:22.04
COPY custom-cert.pem /usr/local/share/ca-certificates/
RUN update-ca-certificates
```

2. **Mount certificates** in pipeline:

```yaml
# In pipeline params
container_volumes:
  - /etc/ssl/certs:/etc/ssl/certs:ro
```

### Proxy Configuration

For enterprises behind proxies:

```yaml
# Add to container environment
http_proxy: http://proxy.company.com:8080
https_proxy: http://proxy.company.com:8080
no_proxy: localhost,127.0.0.1,github3.company.com
```

## Examples

### Complete ACME Corporation Configuration

```yaml
# GitHub Enterprise Configuration
owner: my-team
repository: my-app
github_token: ((vault-github-enterprise-token))
github_api_url: https://github.acme.com/api/v3

# Git Repository Configuration  
git_uri: git@github.acme.com:my-team/my-app.git
git_branch: main
git_private_key: ((vault-ssh-private-key))

# Container Configuration
container_image_repository: my-registry.acme.com/gh-release-tools
container_image_tag: latest
```

### Release Creation Example

```bash
# Using helper script with enterprise
source scripts/release-helpers.sh
create_github_release my-app my-team $GITHUB_TOKEN v1.0.0 \
  "Release notes" "https://github.acme.com/api/v3"
```

## Complete Enterprise Setup Example

### Step-by-Step Enterprise Deployment

1. **Map Your Existing Vault Credentials**

```bash
# Run interactive setup
./setup-enterprise.sh --interactive

# Enter your organization's Vault paths when prompted:
# GitHub Token path: company/github/release-token
# SSH Private Key path: company/ssh/github-deploy-key
# S3 Access Key path: company/aws/s3-access-key-id
# S3 Secret Key path: company/aws/s3-secret-access-key
```

2. **Configure Non-Sensitive Parameters**

```bash
cp params-github-enterprise.yml.example params.yml

# Edit params.yml
cat > params.yml <<EOF
# Non-sensitive configuration (safe to commit)
owner: your-org
repository: your-repo
github_api_url: https://github3.acme.com/api/v3
git_uri: git@github3.acme.com:your-org/your-repo.git
git_branch: main

# S3 Container Configuration
concourse-s3-bucket: your-concourse-bucket
concourse-s3-endpoint: https://s3.amazonaws.com
cflinux_current_image: cflinux
worker_tags: production

# Release defaults
release_tag: v1.0.0
release_name: Release v1.0.0
release_body: "Automated release"
is_draft: false
is_prerelease: false
delete_tag: false
EOF
```

3. **Verify Vault Credentials Exist**

```bash
# Test your Vault access (example with vault CLI)
vault read company/github/release-token
vault read company/ssh/github-deploy-key
vault read company/aws/s3-access-key-id
vault read company/aws/s3-secret-access-key
```

4. **Deploy the Enterprise Pipeline**

```bash
# Deploy with strict configuration management
./ci/fly-enterprise.sh -t production --params ./params.yml

# Or if using custom credential mapping
fly -t production set-pipeline \
  -p gh-release-enterprise \
  -c pipeline-enterprise-custom.yml \
  -l params.yml
```

5. **Trigger a Release**

```bash
# Create a release with specific tag
./ci/fly-enterprise.sh -t production \
  --params ./params.yml \
  --release-tag v2.0.0 \
  --release-name "Major Release"

# Trigger the job
fly -t production trigger-job -j gh-release-enterprise/create-release
```

## Migration Guide

### Migrating from Basic to Enterprise Pipeline

1. **Audit Current Configuration**
   - Identify all secrets currently in environment variables or params files
   - List all GitHub, Git, and S3 credentials

2. **Store Secrets in Vault**

   ```bash
   # Example Vault commands
   vault write company/github/release-token value=@github-token.txt
   vault write company/ssh/github-deploy-key value=@id_rsa
   vault write company/aws/s3-access-key-id value="AKIAIOSFODNN7EXAMPLE"
   vault write company/aws/s3-secret-access-key value="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
   ```

3. **Run Setup Script**

   ```bash
   ./setup-enterprise.sh --interactive
   ```

4. **Update params.yml**
   - Remove ALL sensitive data
   - Keep only non-sensitive configuration

5. **Test and Deploy**

   ```bash
   ./ci/fly-enterprise.sh -t staging --params ./params.yml
   ```

This configuration provides full GitHub Enterprise support with enterprise-grade security and configuration management.
