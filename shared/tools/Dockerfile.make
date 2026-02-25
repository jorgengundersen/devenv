# syntax=docker/dockerfile:1

# Tool: make (GNU make)

FROM repo-base:latest AS tool_make
LABEL tools=true

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends make \
    && rm -rf /var/lib/apt/lists/*

USER devuser
