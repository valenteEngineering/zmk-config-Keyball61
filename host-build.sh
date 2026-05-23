#!/usr/bin/env bash
#
# Host-side wrapper that drives build.sh inside the zmk-builder docker container.
# Run this from your host machine. It will, in order, only doing each step if needed:
#   1. Pull the ZMK build image.
#   2. Create or start the zmk-builder container.
#   3. Initialise the west workspace.
#   4. Invoke build.sh inside the container.
#   5. List the resulting .uf2 files.
#
# Usage:
#   ./host-build.sh                   # build left + right (default)
#   ./host-build.sh left|right|reset|all
#   ./host-build.sh --update          # west update before building
#   ./host-build.sh -h | --help

set -euo pipefail

CONTAINER=zmk-builder
IMAGE=zmkfirmware/zmk-build-arm:stable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "$SCRIPT_DIR")"
WORKSPACE_HOST="$(dirname "$SCRIPT_DIR")"

if [[ -t 1 ]]; then
    G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; Z=$'\e[0m'
else
    G= Y= R= Z=
fi
info() { echo "${G}==>${Z} $*"; }
warn() { echo "${Y}==>${Z} $*"; }
die()  { echo "${R}!!!${Z} $*" >&2; exit 1; }

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    cat <<EOF
Usage: $(basename "$0") [target] [--update]

Targets:
  (none)    Build left + right (default)
  left      Build left half
  right     Build right half (with ZMK Studio over USB)
  reset     Build settings-reset firmware
  all       Build left + right + reset

Flags:
  --update  Refresh ZMK dependencies (west update) before building
  -h, --help  This message

First run: ~10 min (docker pull + west update + build).
Subsequent runs: ~30 sec.

Output: $WORKSPACE_HOST/firmware/{left,right,reset}.uf2
EOF
    exit 0
fi

DO_UPDATE=0
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --update) DO_UPDATE=1 ;;
        *)        ARGS+=("$arg") ;;
    esac
done

command -v docker >/dev/null || die "docker is not installed."

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    info "Pulling $IMAGE (one-time, ~1.5 GB)…"
    docker pull "$IMAGE"
fi

if ! docker container inspect "$CONTAINER" >/dev/null 2>&1; then
    info "Creating container $CONTAINER…"
    docker run -d --name "$CONTAINER" \
        -v "$WORKSPACE_HOST:/workspaces" -w /workspaces \
        "$IMAGE" sleep infinity > /dev/null
elif [[ "$(docker container inspect -f '{{.State.Status}}' "$CONTAINER")" != "running" ]]; then
    info "Starting container $CONTAINER…"
    docker start "$CONTAINER" > /dev/null
fi

if ! docker exec "$CONTAINER" test -d /workspaces/.west; then
    info "Initialising west workspace (one-time, ~5 min)…"
    docker exec "$CONTAINER" bash -c \
        "cd /workspaces && \
         west init -l --mf config/west.yml '$REPO_NAME' && \
         west update && west zephyr-export"
elif (( DO_UPDATE )); then
    info "Refreshing ZMK dependencies (west update)…"
    docker exec "$CONTAINER" bash -c "cd /workspaces && west update"
fi

docker exec "$CONTAINER" "/workspaces/$REPO_NAME/build.sh" "${ARGS[@]}"

echo
info "Firmware:"
ls -lh "$WORKSPACE_HOST/firmware/"*.uf2 2>/dev/null || warn "no firmware built"
echo
info "Flash: put each half in bootloader mode (double-tap reset), drag the"
info "matching .uf2 onto the NICENANO drive that appears."
