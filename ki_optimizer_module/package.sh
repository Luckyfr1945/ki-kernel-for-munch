#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(grep -E "^version=" "$DIR/module.prop" | cut -d'=' -f2 | tr -d ' \r\n')
[ -z "$VERSION" ] && VERSION="v1.4"

ZIP_NAME="Ki-Settings-${VERSION}.zip"
RELEASE_DIR1="$DIR/../release"
RELEASE_DIR2="$DIR/../../release"

mkdir -p "$RELEASE_DIR1" "$RELEASE_DIR2"

echo "Packaging $ZIP_NAME..."
cd "$DIR"
zip -r9 "$RELEASE_DIR1/$ZIP_NAME" . -x "*.git*" -x "package.sh"
cp -f "$RELEASE_DIR1/$ZIP_NAME" "$RELEASE_DIR1/Ki-Settings.zip"
cp -f "$RELEASE_DIR1/$ZIP_NAME" "$RELEASE_DIR2/$ZIP_NAME"
cp -f "$RELEASE_DIR1/$ZIP_NAME" "$RELEASE_DIR2/Ki-Settings.zip"

echo "✔ Built successfully: $RELEASE_DIR1/$ZIP_NAME"

