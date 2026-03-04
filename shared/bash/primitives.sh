#!/bin/bash

# primitives.sh - Shared path-derivation primitives for devenv Bash scripts

if [[ "${_DEVENV_PRIMITIVES_SH_SOURCED:-0}" == "1" ]]; then
    return 0
fi
_DEVENV_PRIMITIVES_SH_SOURCED=1
readonly _DEVENV_PRIMITIVES_SH_SOURCED

# Resolve a path argument to a canonical absolute path.
resolve_project_path() {
    local raw_path="$1"
    local path

    if [[ "${raw_path}" == "." ]]; then
        path="${PWD}"
    elif [[ "${raw_path}" == /* ]]; then
        path="${raw_path}"
    else
        path="${PWD}/${raw_path}"
    fi

    if [[ ! -d "${path}" ]]; then
        return 1
    fi

    path=$(cd "${path}" && pwd)
    printf '%s' "${path}"
}

# Derive a safe project image suffix from path.
derive_project_image_suffix() {
    local project_path="$1"
    local parent_name project_name raw_name safe_name

    parent_name="${project_path%/*}"
    parent_name="${parent_name##*/}"
    project_name="${project_path##*/}"
    raw_name="${parent_name}-${project_name}"
    safe_name=$(printf '%s' "${raw_name}" | sed 's/[^a-zA-Z0-9_.-]/-/g')
    safe_name=$(printf '%s' "${safe_name}" | sed 's/^[^a-zA-Z0-9]//')
    if [[ -z "${safe_name}" ]]; then
        return 1
    fi
    printf '%s' "${safe_name}"
}
