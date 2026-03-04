# syntax=docker/dockerfile:1

# Tool: bats-core (Bash Automated Testing System)
# Installs latest stable bats-core release from GitHub

FROM repo-base:latest AS tool_bats
LABEL tools=true

USER root

RUN BATS_VERSION=$(curl -fsSL https://api.github.com/repos/bats-core/bats-core/releases/latest \
        | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p') \
    && if [ -z "${BATS_VERSION}" ]; then \
        echo "Unable to resolve bats-core version" >&2; \
        exit 1; \
    fi \
    && curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/${BATS_VERSION}.tar.gz" \
        | tar -xz -C /tmp \
    && "/tmp/bats-core-${BATS_VERSION#v}/install.sh" /usr/local \
    && rm -rf "/tmp/bats-core-${BATS_VERSION#v}" \
    && chmod +x /usr/local/bin/bats \
    && chown devuser:devuser /usr/local/bin/bats

USER devuser
