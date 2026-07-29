#!/bin/bash
#======================================================================================
# OpenWrt A/B Partition Safe Update Script
# - No backup of bootloader or user config
# - /boot partition files remain untouched
# - Only writes new rootfs to the inactive partition
# - Only modifies /boot/uEnv.txt boot parameters
#======================================================================================

set -e

error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

# 1. Identify current active root partition and determine target inactive partition
echo ">>> Identifying active root partition..."
CURRENT_ROOT_DEV=$(findmnt -n -o SOURCE /)
CURRENT_PART_NAME=$(basename "$CURRENT_ROOT_DEV")

case "$CURRENT_PART_NAME" in
    mmcblk0p2) TARGET_PART="/dev/mmcblk0p3"; TARGET_LABEL="ROOTFS2" ;;
    mmcblk0p3) TARGET_PART="/dev/mmcblk0p2"; TARGET_LABEL="ROOTFS1" ;;
    *) error_exit "Current root [$CURRENT_ROOT_DEV] is not a valid A/B partition (expected mmcblk0p2/p3)" ;;
esac

echo "    Active partition : $CURRENT_ROOT_DEV"
echo "    Target partition : $TARGET_PART (will be overwritten)"

# 2. Locate firmware image
echo ">>> Locating firmware image..."
IMG_FILE=""
for ext in img img.gz img.xz zip 7z; do
    found=$(ls -1 *.$ext 2>/dev/null | head -n1)
    [ -n "$found" ] && IMG_FILE="$found" && break
done
[ -z "$IMG_FILE" ] && error_exit "No firmware file (.img/.img.gz/.img.xz/.zip/.7z) found in current directory"

echo "    Firmware file: $IMG_FILE"

# Decompress if needed
case "$IMG_FILE" in
    *.gz)  gzip -df "$IMG_FILE"; IMG_FILE="${IMG_FILE%.gz}" ;;
    *.xz)  xz -df "$IMG_FILE";  IMG_FILE="${IMG_FILE%.xz}" ;;
    *.zip) unzip -o "$IMG_FILE"; IMG_FILE=$(ls -1 *.img 2>/dev/null | head -n1) ;;
    *.7z)  7z x "$IMG_FILE" -aoa -y >/dev/null 2>&1; IMG_FILE=$(ls -1 *.img 2>/dev/null | head -n1) ;;
esac
[ ! -f "$IMG_FILE" ] && error_exit "Failed to extract firmware image"

# 3. Setup loop device for source image
echo ">>> Setting up loop device..."
losetup -fP "$IMG_FILE"
LOOP_DEV=$(losetup -j "$IMG_FILE" | grep -o '/dev/loop[0-9]*' | head -n1)
[ -z "$LOOP_DEV" ] && error_exit "Failed to create loop device"

# Ensure partition nodes exist
sleep 1
for p in 1 2; do
    [ ! -b "${LOOP_DEV}p${p}" ] && mknod "${LOOP_DEV}p${p}" b \
        $(cat /sys/block/${LOOP_DEV##*/}/${LOOP_DEV##*/}p${p}/uevent 2>/dev/null | grep MAJOR | cut -d= -f2) \
        $(cat /sys/block/${LOOP_DEV##*/}/${LOOP_DEV##*/}p${p}/uevent 2>/dev/null | grep MINOR | cut -d= -f2) 2>/dev/null || true
done

# 4. Mount source rootfs from firmware image (read-only)
WORK_DIR=$(mktemp -d)
SRC_ROOT="${WORK_DIR}/src_root"
mkdir -p "$SRC_ROOT"
mount -t btrfs -o ro,compress=zstd:6 "${LOOP_DEV}p2" "$SRC_ROOT" || \
mount -t ext4 -o ro "${LOOP_DEV}p2" "$SRC_ROOT" || \
    error_exit "Cannot mount source rootfs from ${LOOP_DEV}p2"

# 5. Format target inactive partition
echo ">>> Formatting target partition $TARGET_PART ..."
NEW_UUID=$(uuidgen)
mkfs.btrfs -f -U "$NEW_UUID" -L "$TARGET_LABEL" -m single "$TARGET_PART" || \
    error_exit "Failed to format $TARGET_PART"

# 6. Mount target partition and copy rootfs
TGT_ROOT="${WORK_DIR}/tgt_root"
mkdir -p "$TGT_ROOT"
mount -t btrfs -o compress=zstd:6 "$TARGET_PART" "$TGT_ROOT" || \
    error_exit "Failed to mount target partition $TARGET_PART"

echo ">>> Copying new rootfs to $TARGET_PART ..."
(cd "$SRC_ROOT" && tar cf - .) | (cd "$TGT_ROOT" && tar xf -)

# 7. Update fstab in new rootfs with correct UUID
echo ">>> Updating /etc/fstab in new rootfs..."
BOOT_LABEL=$(lsblk -n -o LABEL /dev/mmcblk0p1 2>/dev/null || echo "BOOT")
cat > "${TGT_ROOT}/etc/fstab" <<EOF
UUID=${NEW_UUID} / btrfs compress=zstd:6 0 1
LABEL=${BOOT_LABEL} /boot vfat defaults 0 2
EOF

# Create initial btrfs snapshot
btrfs subvolume create "${TGT_ROOT}/etc" 2>/dev/null || true
btrfs subvolume snapshot -r "${TGT_ROOT}/etc" "${TGT_ROOT}/.snapshots/etc-000" 2>/dev/null || true

# 8. Unmount source and cleanup loop device
umount "$SRC_ROOT"
losetup -d "$LOOP_DEV" 2>/dev/null || true
rm -f "$IMG_FILE" 2>/dev/null || true

# 9. Modify ONLY /boot/uEnv.txt — update root= parameter to new UUID
echo ">>> Updating /boot/uEnv.txt ..."
UENV_FILE="/boot/uEnv.txt"
[ ! -f "$UENV_FILE" ] && error_exit "/boot/uEnv.txt not found!"

# Backup current uEnv.txt as safety net (not a full bootloader backup)
cp "$UENV_FILE" "${UENV_FILE}.bak.$(date +%s)"

# Replace root=UUID=xxx or root=PARTUUID=xxx with new UUID
if grep -qE '^root=' "$UENV_FILE"; then
    sed -i "s|^root=.*|root=UUID=${NEW_UUID}|" "$UENV_FILE"
else
    # If no root= line exists, append it
    echo "root=UUID=${NEW_UUID}" >> "$UENV_FILE"
fi

echo "    New boot parameter: root=UUID=${NEW_UUID}"
echo "    uEnv.txt updated successfully"

# 10. Final cleanup
umount "$TGT_ROOT"
rm -rf "$WORK_DIR"

echo ""
echo "============================================"
echo "  A/B Update Complete!"
echo "  Next boot will use: $TARGET_PART"
echo "  New root UUID     : $NEW_UUID"
echo "  /boot files       : UNCHANGED"
echo "  User config       : NOT migrated (fresh install)"
echo "============================================"
echo ""
echo "Run 'reboot' now to boot into the new system."
exit 0
