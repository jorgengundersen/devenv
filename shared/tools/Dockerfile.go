# syntax=docker/dockerfile:1

# Tool: go (Go programming language)

FROM repo-base:latest AS tool_go
LABEL tools=true

USER root

# Install Go
RUN GO_RUNTIME_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1) \
    && curl -LO "https://go.dev/dl/${GO_RUNTIME_VERSION}.linux-amd64.tar.gz" \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf "${GO_RUNTIME_VERSION}.linux-amd64.tar.gz" \
    && rm "${GO_RUNTIME_VERSION}.linux-amd64.tar.gz"

# Change ownership to devuser
RUN chown -R devuser:devuser /usr/local/go

USER devuser
