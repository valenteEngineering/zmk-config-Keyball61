#!/usr/bin/env bash
#
# Build ZMK firmware inside the zmk-builder docker container.
#
# Run from host:
#   docker exec zmk-builder /workspaces/zmk-config-Keyball61/build.sh           # left + right
#   docker exec zmk-builder /workspaces/zmk-config-Keyball61/build.sh left
#   docker exec zmk-builder /workspaces/zmk-config-Keyball61/build.sh right
#   docker exec zmk-builder /workspaces/zmk-config-Keyball61/build.sh reset
#   docker exec zmk-builder /workspaces/zmk-config-Keyball61/build.sh all       # left + right + reset
#
# Outputs land in /workspaces/firmware/{left,right,reset}.uf2 — visible on the
# host as ~/keyboards/firmware/*.uf2.

set -euo pipefail

WORKSPACE=/workspaces
CONFIG="$WORKSPACE/zmk-config-Keyball61/config"
BUILD_ROOT="$WORKSPACE/build"
OUT="$WORKSPACE/firmware"
BOARD=nice_nano_v2

mkdir -p "$OUT"

# Match the host user so the uf2 files aren't root-owned on the host.
HOST_UID=$(stat -c %u "$WORKSPACE")
HOST_GID=$(stat -c %g "$WORKSPACE")

build_one() {
    local name=$1 shield=$2 snippet=${3:-}
    local snippet_arg=()
    [[ -n "$snippet" ]] && snippet_arg=(-S "$snippet")

    echo
    echo "==> Building $name"
    west build -p -s zmk/app -d "$BUILD_ROOT/$name" -b "$BOARD" \
        "${snippet_arg[@]}" \
        -- -DSHIELD="$shield" -DZMK_CONFIG="$CONFIG"

    cp "$BUILD_ROOT/$name/zephyr/zmk.uf2" "$OUT/$name.uf2"
    chown "$HOST_UID:$HOST_GID" "$OUT/$name.uf2"
    echo "==> $OUT/$name.uf2"
}

case "${1:-default}" in
    left)    build_one left  "keyball61_left nice_view_adapter nice_view" ;;
    right)   build_one right "keyball61_right nice_view" "studio-rpc-usb-uart" ;;
    reset)   build_one reset "settings_reset" ;;
    default)
        build_one left  "keyball61_left nice_view_adapter nice_view"
        build_one right "keyball61_right nice_view" "studio-rpc-usb-uart"
        ;;
    all)
        build_one left  "keyball61_left nice_view_adapter nice_view"
        build_one right "keyball61_right nice_view" "studio-rpc-usb-uart"
        build_one reset "settings_reset"
        ;;
    *)
        echo "usage: $0 [left|right|reset|all]" >&2
        exit 1
        ;;
esac
