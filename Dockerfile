# GitHub Release Management Container
# A basic Linux container with tools needed for GitHub release management

FROM ubuntu:22.04

LABEL maintainer="GitHub Release Management Tool"
LABEL description="Basic container for GitHub release management with curl, jq, git, and bash"

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install required tools
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    bash \
    ca-certificates \
    openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create a non-root user for security
RUN useradd -m -s /bin/bash concourse && \
    mkdir -p /home/concourse/.ssh && \
    chown -R concourse:concourse /home/concourse

# Set working directory
WORKDIR /home/concourse

# Switch to non-root user
USER concourse

# Default command
CMD ["/bin/bash"]