# syntax=docker/dockerfile:1

# Tool: jq (JSON processor)

FROM ghcr.io/jqlang/jq:latest AS jq_source
LABEL devenv=true
FROM devenv-base:latest AS tool_jq
LABEL devenv=true

USER root

# Copy jq binary from official image
COPY --from=jq_source /jq /usr/local/bin/jq

# Make executable and change ownership
RUN chmod +x /usr/local/bin/jq \
    && chown devuser:devuser /usr/local/bin/jq

USER devuser
