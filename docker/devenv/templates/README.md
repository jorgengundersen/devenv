# Devenv Templates

This directory contains templates for project-specific Dockerfiles.

## Available Templates

### Dockerfile.project

Generic project template. Use this as a starting point for any project.

**Usage:**
```bash
cp Dockerfile.project /path/to/your/project/.devenv/Dockerfile
```

### Dockerfile.python-uv

Python project template using `uv` as the package manager.

**Usage:**
```bash
cp Dockerfile.python-uv /path/to/your/python-project/.devenv/Dockerfile
```

**Features:**
- Pre-configured for Python best practices
- Uses `uv` for fast package installation
- Sets up editable installs for development

## Template Structure

Each template:
- Uses `devenv:latest` as the base image
- Sets `WORKDIR /home/devuser` (runtime `--workdir` overrides to the project path)
- Runs as `devuser` (non-privileged user)
- Provides commented examples for common customizations

## Best Practices

1. **Always extend from `devenv:latest`** - This ensures consistency
2. **Install as root, then switch to devuser** - Follows the same pattern as the main devenv
3. **Use multi-stage builds for complex projects** - Keeps final image small
4. **Document project-specific setup** - Add comments explaining custom steps
