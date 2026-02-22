# syntax=docker/dockerfile:1

# Ralph: Autonomous AI agent container (Nix-based)
#
# Provides a minimal, locked-down environment for running OpenCode
# in a Ralph Wiggum loop. Nix tooling is removed after package
# installation to prevent the agent from installing packages.

FROM nixos/nix:latest

# Install all required packages via Nix
RUN nix-channel --update \
    && nix-env -iA \
        nixpkgs.bash \
        nixpkgs.coreutils \
        nixpkgs.findutils \
        nixpkgs.gnugrep \
        nixpkgs.gnused \
        nixpkgs.gawk \
        nixpkgs.git \
        nixpkgs.ripgrep \
        nixpkgs.hadolint \
        nixpkgs.shellcheck \
        nixpkgs.curl \
        nixpkgs.less \
        nixpkgs.which \
        nixpkgs.diffutils

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install | bash

# Create ralph user
RUN echo "ralph:x:1000:1000:Ralph AI Agent:/home/ralph:/bin/bash" >> /etc/passwd \
    && echo "ralph:x:1000:" >> /etc/group \
    && mkdir -p /home/ralph \
    && chown 1000:1000 /home/ralph

# Copy Nix profile to ralph (packages installed by root)
RUN cp -a /root/.nix-profile /home/ralph/.nix-profile \
    && chown -R 1000:1000 /home/ralph/.nix-profile

# Set up PATH for ralph (Nix profile binaries only)
ENV PATH="/home/ralph/.nix-profile/bin:/usr/local/bin:${PATH}"
ENV HOME="/home/ralph"

# Copy OpenCode binary to a shared location
RUN cp /root/.local/bin/opencode /usr/local/bin/opencode

# Set up git config
COPY .gitconfig /home/ralph/.gitconfig

# Set up OpenCode config
RUN mkdir -p /home/ralph/.config/opencode
COPY opencode.json /home/ralph/.config/opencode/opencode.json

# Prepare OpenCode data dir so file bind mounts work.
RUN mkdir -p /home/ralph/.local/share/opencode

# Copy the ralph-loop script
COPY ralph-loop /usr/local/bin/ralph-loop
RUN chmod +x /usr/local/bin/ralph-loop

# Create workspace directory
RUN mkdir -p /workspace

# Fix ownership
RUN chown -R 1000:1000 /home/ralph /workspace

# Remove Nix tooling from ralph's profile so the agent cannot install packages.
# Installed packages remain accessible via symlinks to /nix/store.
RUN rm -f /home/ralph/.nix-profile/bin/nix \
          /home/ralph/.nix-profile/bin/nix-env \
          /home/ralph/.nix-profile/bin/nix-build \
          /home/ralph/.nix-profile/bin/nix-shell \
          /home/ralph/.nix-profile/bin/nix-store \
          /home/ralph/.nix-profile/bin/nix-instantiate \
          /home/ralph/.nix-profile/bin/nix-collect-garbage \
          /home/ralph/.nix-profile/bin/nix-copy-closure \
          /home/ralph/.nix-profile/bin/nix-daemon \
          /home/ralph/.nix-profile/bin/nix-hash \
          /home/ralph/.nix-profile/bin/nix-prefetch-url \
          /home/ralph/.nix-profile/bin/nix-channel

# Switch to ralph user
USER ralph
WORKDIR /workspace

# Default shell
SHELL ["/home/ralph/.nix-profile/bin/bash", "-c"]

CMD ["bash"]
