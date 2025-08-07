# GitHub Release Management Makefile
# Provides convenient targets for common operations

# Default values - can be overridden via environment variables or command line
TARGET ?= $(shell fly targets | head -n1 | awk '{print $$1}')
PIPELINE_NAME ?= gh-release
PARAMS_FILE ?= params.yml
RELEASE_TAG ?= v1.0.0
CONTAINER_REGISTRY ?=
CONTAINER_TAG ?= latest

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: help
help: ## Display this help message
	@echo "$(BLUE)GitHub Release Management$(NC)"
	@echo "$(BLUE)========================$(NC)"
	@echo ""
	@echo "$(YELLOW)Pipeline Management:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(deploy|setup|enterprise)' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Container Management:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(container|build|test)' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Release Operations:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(release|trigger)' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Utility:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -vE '(deploy|setup|enterprise|container|build|test|release|trigger)' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Variables:$(NC)"
	@printf "  $(GREEN)%-25s$(NC) %s\n" "TARGET=$(TARGET)" "Concourse target"
	@printf "  $(GREEN)%-25s$(NC) %s\n" "PIPELINE_NAME=$(PIPELINE_NAME)" "Pipeline name"
	@printf "  $(GREEN)%-25s$(NC) %s\n" "PARAMS_FILE=$(PARAMS_FILE)" "Parameters file"
	@printf "  $(GREEN)%-25s$(NC) %s\n" "RELEASE_TAG=$(RELEASE_TAG)" "Release tag"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@printf "  $(GREEN)%-40s$(NC) %s\n" "make deploy-basic TARGET=dev" "Deploy basic pipeline to dev target"
	@printf "  $(GREEN)%-40s$(NC) %s\n" "make deploy-enterprise" "Deploy enterprise pipeline with custom params"
	@printf "  $(GREEN)%-40s$(NC) %s\n" "make create-release RELEASE_TAG=v2.0.0" "Create release with specific tag"

# Pipeline Deployment
.PHONY: deploy-basic
deploy-basic: validate-target validate-params ## Deploy basic pipeline
	@echo "$(BLUE)Deploying basic pipeline...$(NC)"
	@if [ -z "$(GITHUB_TOKEN)" ]; then \
		echo "$(RED)Warning: GITHUB_TOKEN environment variable not set$(NC)"; \
	fi
	@GITHUB_TOKEN=$(GITHUB_TOKEN) ./ci/fly.sh -t $(TARGET) -p $(PIPELINE_NAME) --params $(PARAMS_FILE); \
	if [ $$? -ne 0 ]; then \
		echo "$(RED)Pipeline deployment failed with exit code $$?$(NC)"; \
		echo "$(YELLOW)Trying manual execution to see the full error:$(NC)"; \
		GITHUB_TOKEN=$(GITHUB_TOKEN) ./ci/fly.sh -t $(TARGET) -p $(PIPELINE_NAME) --params $(PARAMS_FILE) || true; \
	fi

.PHONY: deploy-enterprise
deploy-enterprise: validate-target validate-params ## Deploy enterprise pipeline
	@echo "$(BLUE)Deploying enterprise pipeline...$(NC)"
	./ci/fly-enterprise.sh -t $(TARGET) -p $(PIPELINE_NAME) --params $(PARAMS_FILE)

.PHONY: setup-enterprise
setup-enterprise: ## Run interactive enterprise setup for credential mapping
	@echo "$(BLUE)Setting up enterprise pipeline with custom credentials...$(NC)"
	./setup-enterprise.sh --interactive

.PHONY: setup-enterprise-batch
setup-enterprise-batch: ## Run batch enterprise setup (requires credential path variables)
	@echo "$(BLUE)Setting up enterprise pipeline (batch mode)...$(NC)"
	@if [ -z "$(GITHUB_TOKEN_PATH)" ] || [ -z "$(SSH_KEY_PATH)" ]; then \
		echo "$(RED)Error: GITHUB_TOKEN_PATH and SSH_KEY_PATH must be set for batch mode$(NC)"; \
		echo "Example: make setup-enterprise-batch GITHUB_TOKEN_PATH=company/github/token SSH_KEY_PATH=company/ssh/key"; \
		exit 1; \
	fi
	./setup-enterprise.sh --batch \
		--github-token-path "$(GITHUB_TOKEN_PATH)" \
		--ssh-key-path "$(SSH_KEY_PATH)" \
		--s3-access-key-path "$(S3_ACCESS_KEY_PATH)" \
		--s3-secret-key-path "$(S3_SECRET_KEY_PATH)"

# Release Operations
.PHONY: create-release
create-release: validate-target ## Create a GitHub release
	@echo "$(BLUE)Creating GitHub release $(RELEASE_TAG)...$(NC)"
	fly -t $(TARGET) trigger-job -j $(PIPELINE_NAME)/create-release

.PHONY: delete-release
delete-release: validate-target ## Delete a GitHub release
	@echo "$(BLUE)Deleting GitHub release $(RELEASE_TAG)...$(NC)"
	fly -t $(TARGET) trigger-job -j $(PIPELINE_NAME)/delete-release

.PHONY: watch-create
watch-create: validate-target ## Watch create-release job execution
	fly -t $(TARGET) watch -j $(PIPELINE_NAME)/create-release

.PHONY: watch-delete
watch-delete: validate-target ## Watch delete-release job execution
	fly -t $(TARGET) watch -j $(PIPELINE_NAME)/delete-release

.PHONY: trigger-create
trigger-create: validate-target ## Trigger and watch create-release job
	fly -t $(TARGET) trigger-job -j $(PIPELINE_NAME)/create-release -w

.PHONY: trigger-delete
trigger-delete: validate-target ## Trigger and watch delete-release job
	fly -t $(TARGET) trigger-job -j $(PIPELINE_NAME)/delete-release -w

# Container Management
.PHONY: build-container
build-container: ## Build custom container image locally
	@echo "$(BLUE)Building container image...$(NC)"
	./scripts/build-container.sh --load

.PHONY: build-and-push
build-and-push: ## Build and push container to registry
	@if [ -z "$(CONTAINER_REGISTRY)" ]; then \
		echo "$(RED)Error: CONTAINER_REGISTRY must be set$(NC)"; \
		echo "Example: make build-and-push CONTAINER_REGISTRY=myregistry.com"; \
		exit 1; \
	fi
	@echo "$(BLUE)Building and pushing container to $(CONTAINER_REGISTRY)...$(NC)"
	./scripts/build-container.sh --push --registry $(CONTAINER_REGISTRY)

.PHONY: test-container
test-container: ## Test container functionality
	@echo "$(BLUE)Testing container functionality...$(NC)"
	./scripts/test-container.sh --image ubuntu:22.04 --mode basic

.PHONY: test-github-container
test-github-container: ## Test container with GitHub API connectivity
	@if [ -z "$(GITHUB_TOKEN)" ] || [ -z "$(GITHUB_API_URL)" ]; then \
		echo "$(RED)Error: GITHUB_TOKEN and GITHUB_API_URL must be set$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Testing container with GitHub API...$(NC)"
	GITHUB_TOKEN=$(GITHUB_TOKEN) GITHUB_API_URL=$(GITHUB_API_URL) \
		./scripts/test-container.sh --image ubuntu:22.04 --mode github

# Pipeline Management
.PHONY: unpause
unpause: validate-target ## Unpause the pipeline
	fly -t $(TARGET) unpause-pipeline -p $(PIPELINE_NAME)

.PHONY: pause
pause: validate-target ## Pause the pipeline
	fly -t $(TARGET) pause-pipeline -p $(PIPELINE_NAME)

.PHONY: destroy
destroy: validate-target ## Destroy the pipeline (with confirmation)
	@echo "$(RED)WARNING: This will destroy the pipeline '$(PIPELINE_NAME)' on target '$(TARGET)'$(NC)"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	fly -t $(TARGET) destroy-pipeline -p $(PIPELINE_NAME) -n

.PHONY: status
status: validate-target ## Show pipeline status
	@echo "$(BLUE)Pipeline Status for $(PIPELINE_NAME) on $(TARGET):$(NC)"
	@fly -t $(TARGET) pipelines | grep -E "($(PIPELINE_NAME)|pipeline)" || echo "Pipeline not found"
	@echo ""
	@fly -t $(TARGET) jobs -p $(PIPELINE_NAME) 2>/dev/null || echo "No jobs found for pipeline $(PIPELINE_NAME)"

# Development & Testing
.PHONY: lint
lint: ## Run shellcheck on all shell scripts
	@echo "$(BLUE)Running shellcheck...$(NC)"
	@find . -name "*.sh" -not -path "./scripts/release-helpers.sh" -exec shellcheck {} \; || true

.PHONY: validate-params
validate-params: ## Validate parameter files exist
	@if [ ! -f "$(PARAMS_FILE)" ]; then \
		echo "$(RED)Error: Parameter file $(PARAMS_FILE) not found$(NC)"; \
		echo "Available parameter files:"; \
		ls -la params*.yml* 2>/dev/null || echo "No parameter files found"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Parameter file $(PARAMS_FILE) exists$(NC)"

.PHONY: validate-target
validate-target: ## Validate Concourse target is set and logged in
	@if [ -z "$(TARGET)" ]; then \
		echo "$(RED)Error: TARGET not set. Use: make <command> TARGET=<target>$(NC)"; \
		echo "Available targets:"; \
		fly targets 2>/dev/null || echo "No fly targets configured"; \
		exit 1; \
	fi
	@fly -t $(TARGET) status >/dev/null 2>&1 || { \
		echo "$(RED)Error: Not logged into Concourse target '$(TARGET)'$(NC)"; \
		echo "Run: fly -t $(TARGET) login"; \
		exit 1; \
	}
	@echo "$(GREEN)✓ Connected to Concourse target $(TARGET)$(NC)"

.PHONY: example-params
example-params: ## Copy example parameter files for customization
	@echo "$(BLUE)Copying example parameter files...$(NC)"
	@for file in params*.example; do \
		if [ -f "$$file" ]; then \
			target=$${file%.example}; \
			if [ ! -f "$$target" ]; then \
				cp "$$file" "$$target"; \
				echo "$(GREEN)✓ Created $$target from $$file$(NC)"; \
			else \
				echo "$(YELLOW)⚠ $$target already exists, skipping$(NC)"; \
			fi; \
		fi; \
	done

# Docker Compose operations
.PHONY: dev-up
dev-up: ## Start development environment with docker-compose
	docker-compose up -d

.PHONY: dev-down
dev-down: ## Stop development environment
	docker-compose down

.PHONY: dev-logs
dev-logs: ## Show development environment logs
	docker-compose logs -f

# Cleanup
.PHONY: clean
clean: ## Clean up temporary files and containers
	@echo "$(BLUE)Cleaning up...$(NC)"
	@rm -f /tmp/gh-release-vars.*.yml 2>/dev/null || true
	@docker system prune -f --filter label=gh-release 2>/dev/null || true
	@echo "$(GREEN)✓ Cleanup completed$(NC)"

# Quick deployment shortcuts
.PHONY: quick-basic
quick-basic: validate-target example-params deploy-basic ## Quick setup: copy examples and deploy basic pipeline

.PHONY: quick-enterprise
quick-enterprise: validate-target example-params setup-enterprise deploy-enterprise ## Quick setup: copy examples, run enterprise setup, and deploy

# Show configuration
.PHONY: config
config: ## Show current configuration
	@echo "$(BLUE)Current Configuration:$(NC)"
	@echo "  TARGET: $(TARGET)"
	@echo "  PIPELINE_NAME: $(PIPELINE_NAME)"
	@echo "  PARAMS_FILE: $(PARAMS_FILE)"
	@echo "  RELEASE_TAG: $(RELEASE_TAG)"
	@echo ""
	@echo "$(BLUE)Available Parameter Files:$(NC)"
	@ls -la params*.yml* 2>/dev/null || echo "  No parameter files found"
	@echo ""
	@echo "$(BLUE)Pipeline Files:$(NC)"
	@ls -la ci/pipelines/*.yml 2>/dev/null || echo "  No pipeline files found"
