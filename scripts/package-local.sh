#!/bin/bash
# Build a Thunderstore-format zip of the current branch for r2modman "Import local mod".
# Mirrors .github/workflows/build-plugin-thunderstore.yml (THUNDERSTORE_BUILD, tcli layout).
#
# Usage: scripts/package-local.sh [version]
# Env:   PACKAGE_NAMESPACE (default EvanDeters_dev), OUTPUT_DIR (default ./build)
# Needs: dotnet SDK, tcli (dotnet tool install -g tcli), python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-5.1.1}"
NAMESPACE="${PACKAGE_NAMESPACE:-EvanDeters_dev}"
NAME="MegabonkTogether"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

BUILD_OUT="$WORK_DIR/bin"
STAGE_DIR="$WORK_DIR/artifacts/$NAME"
mkdir -p "$STAGE_DIR" "$OUTPUT_DIR"

echo "Building $NAMESPACE-$NAME-$VERSION (THUNDERSTORE_BUILD, auto-update download disabled)"

# CI=true skips the csproj PostBuild copy into a local game install.
# PROTON_BUILD is unset on purpose: THUNDERSTORE takes precedence anyway and both only disable auto-update.
env -u PROTON_BUILD CI=true THUNDERSTORE_BUILD=true \
    dotnet build src/plugin/MegabonkTogether.Plugin.csproj \
    --configuration Release \
    -p:Version="$VERSION" \
    --output "$BUILD_OUT"

shopt -s nullglob
files=("$BUILD_OUT"/*.dll "$BUILD_OUT"/*.pdb)
if [ ${#files[@]} -eq 0 ]; then
    echo "No DLL/PDB found in $BUILD_OUT"
    exit 1
fi
cp "${files[@]}" "$STAGE_DIR/"

# tcli resolves paths relative to the config file
cp images/icon.png "$WORK_DIR/icon.png"
cp README.md "$WORK_DIR/README.md"

cat > "$WORK_DIR/thunderstore.toml" <<EOF
[config]
schemaVersion = "0.0.1"

[package]
namespace = "$NAMESPACE"
name = "$NAME"
versionNumber = "$VERSION"
description = "Local test build of MegabonkTogether ($(git rev-parse --abbrev-ref HEAD)@$(git rev-parse --short HEAD)). Not for distribution."
websiteUrl = "https://github.com/evandeters/megabonk-together"
containsNsfwContent = false

[package.dependencies]
BepInEx-BepInExPack_IL2CPP = "6.0.738"

[build]
icon = "./icon.png"
readme = "./README.md"
outdir = "./build"

[[build.copy]]
source = "./artifacts/$NAME"
target = "$NAME"
EOF

tcli build --config-path "$WORK_DIR/thunderstore.toml"

ZIP_NAME="$NAMESPACE-$NAME-$VERSION.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
cp "$WORK_DIR/build/$ZIP_NAME" "$ZIP_PATH"

# tcli's manifest has no author field; r2modman uses it to name the local import.
python3 - "$ZIP_PATH" "$NAMESPACE" <<'PY'
import json, shutil, sys, tempfile, zipfile

zip_path, namespace = sys.argv[1], sys.argv[2]
tmp = tempfile.mktemp(suffix=".zip")
with zipfile.ZipFile(zip_path) as src, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as dst:
    for item in src.infolist():
        data = src.read(item.filename)
        if item.filename == "manifest.json":
            manifest = json.loads(data.decode("utf-8-sig"))
            manifest = {"name": manifest.pop("name"), "author": namespace, **manifest}
            data = (json.dumps(manifest, indent=4) + "\n").encode("utf-8")
        dst.writestr(item, data)
shutil.move(tmp, zip_path)
PY

echo
echo "Package: $ZIP_PATH"
unzip -l "$ZIP_PATH"
unzip -p "$ZIP_PATH" manifest.json
