# Ralph - Autonomous AI Agent Container

Ralph is a Nix-based Docker container that runs [OpenCode](https://opencode.ai) in a continuous
[Ralph Wiggum loop](https://www.dreamhost.com/blog/ralph-wiggum/) for autonomous development tasks
on the devenv project.

## Overview

```
.ralph/
├── Dockerfile          # Nix-based container image definition
├── .gitconfig          # Ralph's git identity
├── opencode.json       # OpenCode configuration (yolo mode)
├── ralph-loop          # The loop script (injected into container)
├── PROMPT.md           # Task instructions for Ralph (edit this)
└── README.md           # This file
```

## How It Works

1. Edit `PROMPT.md` with your task instructions
2. Build and run the container
3. Ralph reads `PROMPT.md` and sends it to OpenCode
4. OpenCode executes the task autonomously (all permissions allowed)
5. When OpenCode finishes, Ralph loops back and runs it again
6. You review the changes Ralph made and push manually

## Container Details

| Property      | Value                                   |
|---------------|-----------------------------------------|
| Base image    | `nixos/nix:latest`                      |
| User          | `ralph` (UID 1000, no sudo)             |
| Shell         | bash                                    |
| Working dir   | `/workspace`                            |
| Git identity  | `Jørgen Gundersen <jg@gundersenj.com>` |
| OpenCode mode | All permissions allowed (yolo)          |

### Installed Tools

| Tool       | Purpose                        |
|------------|--------------------------------|
| bash       | Default shell (GNU)            |
| coreutils  | GNU core utilities             |
| findutils  | find, xargs                    |
| gnugrep    | GNU grep                       |
| gnused     | GNU sed                        |
| gawk       | GNU awk                        |
| git        | Version control                |
| ripgrep    | Fast file content search       |
| hadolint   | Dockerfile linter              |
| shellcheck | Bash script linter             |
| curl       | HTTP client                    |
| less       | Pager                          |
| which      | Locate commands                |
| diffutils  | diff, cmp                      |
| opencode   | AI coding assistant            |

### Security

- **No sudo access** -- Ralph runs as an unprivileged user
- **No package manager** -- Nix tooling is removed after image build; Ralph cannot install packages
- **No Docker access** -- Ralph cannot build or run containers
- **No remote git access** -- Ralph works locally only; you review and push
- **Read-write workspace only** -- The project directory is the only writable mount

## Usage

### 1. Build the Image

```bash
docker build -t ralph:latest .ralph/
```

### 2. Edit the Prompt

Edit `.ralph/PROMPT.md` with the task you want Ralph to work on. Be specific about:
- What to accomplish
- Which files to modify
- What validation to run (shellcheck, hadolint, etc.)

You can override the prompt file path with the `RALPH_PROMPT_FILE` environment variable:

```bash
-e RALPH_PROMPT_FILE="/workspace/my-custom-prompt.md"
```

### 3. Run Ralph (Single Iteration)

Run OpenCode once against the prompt, useful for testing:

```bash
docker run --rm -it \
    -v "$(pwd):/workspace:rw" \
    -v "$HOME/.config/opencode:/home/ralph/.config/opencode:ro" \
    -v "$HOME/.local/share/opencode/auth.json:/home/ralph/.local/share/opencode/auth.json:ro" \
    -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    ralph:latest \
    opencode run "$(cat .ralph/PROMPT.md)"
```

### 4. Run the Ralph Loop

Run the continuous loop:

```bash
docker run --rm -it \
    -v "$(pwd):/workspace:rw" \
    -v "$HOME/.config/opencode:/home/ralph/.config/opencode:ro" \
    -v "$HOME/.local/share/opencode/auth.json:/home/ralph/.local/share/opencode/auth.json:ro" \
    -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    ralph:latest \
    ralph-loop
```

> **Note:** Replace `ANTHROPIC_API_KEY` with whatever API key environment variable
> your OpenCode provider requires. You may need to pass multiple `-e` flags for
> different providers.

### 5. Stop Ralph

Press `Ctrl+C` to stop the loop, or from another terminal:

```bash
docker stop $(docker ps -q --filter ancestor=ralph:latest)
```

### 6. Review Changes

After Ralph runs, review the changes in your working directory:

```bash
git log --author="Ralph"
git diff
```

Ralph's commits are attributed to `Ralph (AI Agent) <ralph@devenv.local>`, making
them easy to identify and review before pushing.

## Configuration

### OpenCode Provider

Ralph needs an API key for the LLM provider. Pass it as an environment variable
when running the container:

Ralph can also reuse the same OpenCode credentials as `devenv` by bind-mounting
your host OpenCode config directory and auth file:

```bash
-v "$HOME/.config/opencode:/home/ralph/.config/opencode:ro"
-v "$HOME/.local/share/opencode/auth.json:/home/ralph/.local/share/opencode/auth.json:ro"
```

```bash
# Anthropic
-e ANTHROPIC_API_KEY="..."

# OpenAI
-e OPENAI_API_KEY="..."

# Other providers: check OpenCode docs for the required env var
```

### OpenCode Config

The OpenCode configuration is baked into the image at
`/home/ralph/.config/opencode/opencode.json`. To override it at runtime, mount
your own config:

```bash
-v "/path/to/your/opencode.json:/home/ralph/.config/opencode/opencode.json:ro"
```

## Limitations (v1)

- **No Docker builds** -- Ralph cannot run `docker build` (no DinD). It can lint
  Dockerfiles with `hadolint` but cannot test builds.
- **No internet access** -- Ralph has no network credentials. It works with local
  files only.
- **No validation loop** -- The loop is a simple retry. There is no automated
  validation step (shellcheck/hadolint) between iterations. This is planned for v2.
- **No persistent state** -- Each container run starts fresh. OpenCode conversation
  history is not preserved across runs.
