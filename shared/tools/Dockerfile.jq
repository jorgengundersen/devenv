# syntax=docker/dockerfile:1

# Tool: jq (JSON processor)

FROM ghcr.io/jqlang/jq:1.7.1 AS jq_source
LABEL tools=true
FROM repo-base:latest AS tool_jq
LABEL tools=true

USER root

# Copy jq binary from official image
COPY --from=jq_source /jq /usr/local/bin/jq

# Make executable and change ownership
RUN chmod +x /usr/local/bin/jq \
    && chown devuser:devuser /usr/local/bin/jq

USER devuser
