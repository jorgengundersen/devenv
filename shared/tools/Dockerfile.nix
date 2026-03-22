# syntax=docker/dockerfile:1

# Tool: nix (Nix package manager)

FROM repo-base:latest AS tool_nix
LABEL tools=true

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Configure Nix for single-user mode before install (no build group needed without daemon)
RUN mkdir -p /etc/nix \
    && printf 'build-users-group =\nexperimental-features = nix-command flakes\n' > /etc/nix/nix.conf

# Install xz (needed by Nix installer to unpack tarballs) then Nix in single-user mode
RUN apt-get update && apt-get install -y --no-install-recommends xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -L https://nixos.org/nix/install | sh -s -- --no-daemon \
    && ln -s /nix/var/nix/profiles/default/bin/nix /usr/local/bin/nix \
    && ln -s /nix/var/nix/profiles/default/bin/nix-build /usr/local/bin/nix-build \
    && ln -s /nix/var/nix/profiles/default/bin/nix-channel /usr/local/bin/nix-channel \
    && ln -s /nix/var/nix/profiles/default/bin/nix-env /usr/local/bin/nix-env \
    && ln -s /nix/var/nix/profiles/default/bin/nix-shell /usr/local/bin/nix-shell \
    && ln -s /nix/var/nix/profiles/default/bin/nix-store /usr/local/bin/nix-store \
    && chown -R devuser:devuser /nix

USER devuser
