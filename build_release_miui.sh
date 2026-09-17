#!/bin/bash
set -e

DEVICE="munch"
RELEASE_DIR="release"

mkdir -p "$RELEASE_DIR"
rm -f rilis
ln -sfn "$RELEASE_DIR" rilis

echo "=========================================================="
echo "Starting MIUI / HyperOS Release Build for: $DEVICE"
echo "Output directory: $RELEASE_DIR/ (or rilis/)"
echo "=========================================================="

build_variant() {
    local variant="$1"  # noksu, nosusfs, or ksu
    local desc="$2"
    
    echo ""
    echo ">>> Building MIUI [$variant] - $desc <<<"
    
    bash build_miui.sh "$DEVICE" "$variant"
    
    # Move newly created zip to release folder
    LATEST_ZIP=$(ls -t Ki-kernel-MIUI_*.zip 2>/dev/null | head -n 1)
    if [ -n "$LATEST_ZIP" ] && [ -f "$LATEST_ZIP" ]; then
        echo "Moving $LATEST_ZIP to $RELEASE_DIR/"
        mv "$LATEST_ZIP" "$RELEASE_DIR/"
    fi
}

# Build the 3 MIUI variants
build_variant noksu "Vanilla (No KernelSU, No SuSFS)"
build_variant nosusfs "KernelSU-Next Standard"
build_variant ksu "KernelSU-Next + SuSFS v1.5.7"

echo ""
echo "=========================================================="
echo "MIUI BUILDS COMPLETED SUCCESSFULLY!"
echo "Generated release packages in ./$RELEASE_DIR:"
ls -lh "$RELEASE_DIR"/Ki-kernel-MIUI_*
echo "=========================================================="
