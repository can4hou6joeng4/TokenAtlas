#!/usr/bin/env bash
# Build a local Release TokenAtlas.app and install it as the machine app.
#
# This is for daily local use, not development verification. Keep
# scripts/run-debug.sh on /tmp/TokenAtlas-build so Launch Services does not mix
# Debug menu-bar bundles with the installed app.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="${TOKENATLAS_INSTALL_DERIVED:-/tmp/TokenAtlas-install-build}"
INSTALL_DIR="${TOKENATLAS_INSTALL_DIR:-/Applications}"
CONFIGURATION="${TOKENATLAS_INSTALL_CONFIGURATION:-Release}"
LAUNCH_AFTER_INSTALL=1
CLEAN_BUILD="${TOKENATLAS_INSTALL_CLEAN:-0}"

APP_PROCESS_PATTERN="TokenAtlas.app/Contents/MacOS/TokenAtlas"
LEGACY_APP_PROCESS_PATTERN="Claude Stats.app/Contents/MacOS/Claude Stats"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

usage() {
    cat >&2 <<USAGE
usage: bash scripts/install-app.sh [--install-dir <dir>] [--configuration <name>] [--clean] [--no-launch]

Builds TokenAtlas and installs it to <dir>/TokenAtlas.app.

Defaults:
  --install-dir /Applications
  --configuration Release
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)
            [[ $# -ge 2 ]] || { echo "error: --install-dir needs a value" >&2; exit 2; }
            INSTALL_DIR="$2"
            shift 2
            ;;
        --configuration)
            [[ $# -ge 2 ]] || { echo "error: --configuration needs a value" >&2; exit 2; }
            CONFIGURATION="$2"
            shift 2
            ;;
        --no-launch)
            LAUNCH_AFTER_INSTALL=0
            shift
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

BUILT_APP="$DERIVED/Build/Products/$CONFIGURATION/TokenAtlas.app"
INSTALL_APP="$INSTALL_DIR/TokenAtlas.app"

require_apple_silicon() {
    if [[ "$(uname -m)" != "arm64" ]]; then
        echo "error: TokenAtlas now supports Apple Silicon Macs only." >&2
        exit 1
    fi
}

running_app_pids() {
    pgrep -f "$APP_PROCESS_PATTERN|$LEGACY_APP_PROCESS_PATTERN" 2>/dev/null || true
}

running_installed_app_pids() {
    pgrep -f "$INSTALL_APP/Contents/MacOS/TokenAtlas" 2>/dev/null || true
}

wait_until_stopped() {
    local pids
    local attempts="$1"
    for ((i = 0; i < attempts; i++)); do
        pids="$(running_app_pids)"
        if [[ -z "$pids" ]]; then
            return 0
        fi
        sleep 0.15
    done
    return 1
}

stop_running_app() {
    local pids
    pids="$(running_app_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    echo "==> Stopping existing TokenAtlas/legacy Claude Stats process(es): $(echo "$pids" | tr '\n' ' ')"
    kill -TERM $pids 2>/dev/null || true
    if wait_until_stopped 30; then
        return 0
    fi

    pids="$(running_app_pids)"
    echo "==> Existing process ignored SIGTERM; forcing: $(echo "$pids" | tr '\n' ' ')"
    kill -KILL $pids 2>/dev/null || true
    if wait_until_stopped 30; then
        return 0
    fi

    pids="$(running_app_pids)"
    echo "error: unable to stop existing TokenAtlas/legacy Claude Stats process(es): $(echo "$pids" | tr '\n' ' ')" >&2
    return 1
}

unregister_bundle_if_present() {
    local bundle="$1"
    if [[ -d "$bundle" ]]; then
        "$LSREGISTER" -u "$bundle" 2>/dev/null || true
    fi
}

cleanup_stale_registrations() {
    unregister_bundle_if_present "$INSTALL_APP"
    unregister_bundle_if_present "/Applications/Claude Stats.app"
    unregister_bundle_if_present "/tmp/Codex-stats-build/Build/Products/Debug/Claude Stats.app"
    unregister_bundle_if_present "/tmp/token-atlas-build/Build/Products/Debug/TokenAtlas.app"
    unregister_bundle_if_present "/tmp/TokenAtlas-build-tests/Build/Products/Debug/TokenAtlas.app"
}

install_built_app() {
    [[ -d "$BUILT_APP" ]] || { echo "error: build did not produce $BUILT_APP" >&2; exit 1; }
    mkdir -p "$INSTALL_DIR"

    local staging
    staging="$(mktemp -d "${TMPDIR:-/tmp}/token-atlas-install.XXXXXX")"
    trap 'rm -rf "$staging"' RETURN

    echo "==> Staging install copy"
    /usr/bin/ditto "$BUILT_APP" "$staging/TokenAtlas.app"
    bash scripts/verify-arm64-bundle.sh "$staging/TokenAtlas.app"
    codesign --verify --deep --strict --verbose=2 "$staging/TokenAtlas.app"

    echo "==> Installing $INSTALL_APP"
    rm -rf "$INSTALL_APP"
    /usr/bin/ditto "$staging/TokenAtlas.app" "$INSTALL_APP"
    "$LSREGISTER" -f -R -trusted "$INSTALL_APP" 2>/dev/null || true

    trap - RETURN
    rm -rf "$staging"
}

launch_installed_app() {
    [[ $LAUNCH_AFTER_INSTALL -eq 1 ]] || return 0

    "$LSREGISTER" -f -R -trusted "$INSTALL_APP" 2>/dev/null || true
    open "$INSTALL_APP"

    for ((i = 0; i < 20; i++)); do
        if [[ -n "$(running_installed_app_pids)" ]]; then
            break
        fi
        sleep 0.25
    done

    if [[ -z "$(running_installed_app_pids)" ]]; then
        echo "error: launch did not produce a TokenAtlas process from $INSTALL_APP" >&2
        exit 1
    fi

    for ((i = 0; i < 24; i++)); do
        sleep 0.25
        if [[ -z "$(running_installed_app_pids)" ]]; then
            echo "error: installed TokenAtlas process exited during startup verification" >&2
            exit 1
        fi
    done

    echo "Launched $INSTALL_APP"
}

require_apple_silicon
bash scripts/build-linguist-runtime.sh
bash scripts/generate.sh

stop_running_app
cleanup_stale_registrations

if [[ "$CLEAN_BUILD" == "1" ]]; then
    echo "==> Cleaning install DerivedData: $DERIVED"
    rm -rf "$DERIVED"
fi
xcodebuild \
    -project TokenAtlas.xcodeproj \
    -scheme TokenAtlas \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    ARCHS=arm64 \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Automatic \
    ENABLE_HARDENED_RUNTIME=NO \
    build

ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/token-atlas-install-entitlements.XXXXXX")"
if ! codesign -d --entitlements :- "$BUILT_APP" > "$ENTITLEMENTS" 2>/dev/null; then
    rm -f "$ENTITLEMENTS"
    ENTITLEMENTS=""
fi
bash scripts/thin-arm64-bundle.sh "$BUILT_APP"
bash scripts/codesign-ad-hoc-bundle.sh "$BUILT_APP" "$ENTITLEMENTS"
[[ -n "$ENTITLEMENTS" ]] && rm -f "$ENTITLEMENTS"
bash scripts/verify-arm64-bundle.sh "$BUILT_APP"
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

install_built_app
launch_installed_app

echo "Installed $INSTALL_APP"
