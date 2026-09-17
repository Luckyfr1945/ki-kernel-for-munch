#!/bin/bash
set -e

DEVICE="munch"
RELEASE_DIR="release"

mkdir -p "$RELEASE_DIR"
rm -f rilis
ln -sfn "$RELEASE_DIR" rilis

echo "=========================================================="
echo "Starting Full Release Build for: $DEVICE"
echo "Output directory: $RELEASE_DIR/ (or rilis/)"
echo "=========================================================="

build_variant() {
    local type="$1"     # miui or aosp
    local variant="$2"  # noksu, nosusfs, or ksu
    local desc="$3"
    
    echo ""
    echo ">>> Building [$type] [$variant] - $desc <<<"
    
    if [ "$type" == "miui" ]; then
        bash build_miui.sh "$DEVICE" "$variant"
    else
        bash build_aosp.sh "$DEVICE" "$variant"
    fi
    
    # Move newly created zip to release folder
    LATEST_ZIP=$(ls -t *_Ki-kernel-${type^^}-*.zip 2>/dev/null | head -n 1)
    if [ -n "$LATEST_ZIP" ] && [ -f "$LATEST_ZIP" ]; then
        echo "Moving $LATEST_ZIP to $RELEASE_DIR/"
        mv "$LATEST_ZIP" "$RELEASE_DIR/"
    else
        echo "Warning: Could not find newly built zip matching *_Ki-kernel-${type^^}-*.zip in root"
    fi
}

# 1. MIUI / HyperOS Builds
build_variant miui noksu "Vanilla (No KernelSU, No SuSFS)"
build_variant miui nosusfs "KernelSU-Next Standard"
build_variant miui ksu "KernelSU-Next + SuSFS v1.5.7"

# 2. AOSP / Custom ROM Builds
build_variant aosp noksu "Vanilla (No KernelSU, No SuSFS)"
build_variant aosp nosusfs "KernelSU-Next Standard"
build_variant aosp ksu "KernelSU-Next + SuSFS v1.5.7"

echo ""
echo "=========================================================="
echo "ALL BUILDS COMPLETED SUCCESSFULLY!"
echo "Generated release packages in ./$RELEASE_DIR:"
ls -lh "$RELEASE_DIR"/*v1.2*.zip 2>/dev/null || ls -lh "$RELEASE_DIR"

echo ""
echo "Calculating SHA256 checksums for v1.2..."
cd "$RELEASE_DIR"
sha256sum *_Ki-kernel-*-v1.2_*.zip | tee sha256_v1.2.txt
cd ..
echo "=========================================================="
