#!/bin/bash
#======================================================================================
# OpenWrt A/B Partition Safe Update Script for Amlogic S9xxx STB
# Fix: busybox losetup no -P parameter, losetup attach failed
# Feature:
# 1. A/B p2/p3 partition switch, only flash inactive rootfs
# 2. No bootloader backup, no user config backup/restore
# 3. /boot partition all original files untouched, only modify uEnv.txt root UUID
#======================================================================================
set -o pipefail

#==================== Global Function Define ====================
# Error exit handler
error_msg() {
    echo -e "\033[31m[ERROR] ${1}\033[0m" >&2
    exit 1
}

# Temp cleanup trap
cleanup() {
    echo -e "\n[CLEAN] Start cleaning temporary resources..."
    mountpoint -q "${SRC_ROOT_DIR}" && umount -l "${SRC_ROOT_DIR}" 2>/dev/null || true
    mountpoint -q "${TARGET_ROOT_MP}" && umount -l "${TARGET_ROOT_MP}" 2>/dev/null || true
    mountpoint -q "${WORK_P1}" && umount -l "${WORK_P1}" 2>/dev/null || true
    mountpoint -q "${WORK_P2}" && umount -l "${WORK_P2}" 2>/dev/null || true
    if [[ -n "${LOOP_DEV}" ]]; then
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi

    rm -rf "${TMP_WORK_DIR}" "${SRC_ROOT_DIR}" "${TARGET_ROOT_MP}"
    if [[ "${ORIG_IMG}" != "${IMG_NAME}" && -f "${IMG_NAME}" ]]; then
        rm -f "${IMG_NAME}"
    fi
    sync
    echo "[CLEAN] Cleanup finished"
}

# Fix kernel 5.19 loopdev subdevice node missing
fix_loopdev() {
    local parentdev=${1##*/}
    [[ ! -d "/sys/block/${parentdev}" ]] && return
    subdevs=$(lsblk -l -o NAME | grep -E "^${parentdev}.+$")
    for subdev in ${subdevs}; do
        [[ ! -d "/sys/block/${parentdev}/${subdev}" ]] && continue
        source /sys/block/${parentdev}/${subdev}/uevent
        [[ ! -b "/dev/${subdev}" ]] && mknod "/dev/${subdev}" b "${MAJOR}" "${MINOR}"
        unset MAJOR MINOR DEVNAME DEVTYPE DISKSEQ PARTN PARTNAME
    done
}

# Get free loop device, auto clean dead loop first
get_free_loop() {
    losetup -D 2>/dev/null
    local dev=$(losetup -f)
    [[ -z "${dev}" ]] && error_msg "No free loop device available, reboot and try again"
    echo "${dev}"
}

# Get /boot partition device
get_boot_partition_name() {
    df "/boot" 2>/dev/null | awk 'NR==2 {print $1}' | awk -F '/' '{print $3}'
}

# Get current root partition device (findmnt high priority)
get_root_partition_name() {
    local dev
    dev=$(findmnt -n -o SOURCE / 2>/dev/null)
    if [[ -n "${dev}" ]]; then
        basename "${dev}"
        return
    fi
    local paths=("/" "/overlay" "/rom")
    local partition_name
    for path in "${paths[@]}"; do
        partition_name=$(df "${path}" 2>/dev/null | awk 'NR==2 {print $1}' | awk -F '/' '{print $3}')
        [[ -n "${partition_name}" ]] && break
    done
    echo "${partition_name}"
}

# Get full root partition info line, FIX awk division by zero
get_root_partition_msg() {
    local root_dev=$(findmnt -n -o SOURCE / 2>/dev/null)
    if [[ -n "${root_dev}" && -b "${root_dev}" ]]; then
        lsblk -l -o NAME,PATH,TYPE,UUID,MOUNTPOINT "${root_dev}" | grep part
        return
    fi
    local paths=("/" "/overlay" "/rom")
    local partition_msg
    for path in "${paths[@]}"; do
        partition_msg=$(lsblk -l -o NAME,PATH,TYPE,UUID,MOUNTPOINT | awk -v mp="${path}" '$3~/^part$/ && $5 == mp {print $0}')
        [[ -n "${partition_msg}" ]] && break
    done
    [[ -z "${partition_msg}" ]] && error_msg "Cannot find root partition message! Current root dev: $(findmnt -n -o SOURCE /)"
    echo "${partition_msg}"
}

# Phicomm N1 p2 partition offset repair function, FIX division by zero
check_and_fix_partition() {
    local target_dev_name=${1}
    local target_pt_name=${2}
    local target_pt_idx=${3}
    local safe_pt_begin_mb=${4}
    local safe_pt_begin_byte=$((safe_pt_begin_mb * 1024 * 1024))

    local sector_line=$(fdisk -l "/dev/${target_dev_name}" 2>/dev/null | grep "${target_dev_name}${target_pt_name}")
    local cur_pt_begin_sector=$(echo "${sector_line}" | awk '{print $2}')
    if [[ -z "${cur_pt_begin_sector}" || "${cur_pt_begin_sector}" == "0" ]]; then
        echo "[WARN] Partition sector empty, skip offset check"
        return
    fi
    local cur_pt_begin_mb=$((cur_pt_begin_sector * 512 / 1024 / 1024))

    if [[ ${cur_pt_begin_mb} -ge ${safe_pt_begin_mb} ]]; then
        return
    fi

    local cur_pt_end_sector=$(echo "${sector_line}" | awk '{print $3}')
    if [[ -z "${cur_pt_end_sector}" || "${cur_pt_end_sector}" == "0" ]]; then
        error_msg "Invalid partition end sector, cannot repair"
    fi
    local cur_pt_end_byte=$(((cur_pt_end_sector + 1) * 512 - 1))
    echo "[REPAIR] Unsafe partition offset detected, re-create partition..."
    parted "/dev/${target_dev_name}" rm "${target_pt_idx}" || error_msg "Remove old partition failed"
    parted "/dev/${target_dev_name}" mkpart primary btrfs "${safe_pt_begin_byte}b" "${cur_pt_end_byte}b" || error_msg "Recreate partition failed"
    echo "[REPAIR] Partition offset repair complete"
}

# Unified decompress function
decompress_firmware() {
    local src_file="$1"
    local out_img
    case "$src_file" in
        *.gz)
            echo "[DECOMPRESS] Unpack gzip: $src_file"
            gzip -df "$src_file" 2>/dev/null
            out_img="${src_file%.gz}"
            ;;
        *.xz)
            echo "[DECOMPRESS] Unpack xz: $src_file"
            xz -df "$src_file" 2>/dev/null
            out_img="${src_file%.xz}"
            ;;
        *.zip)
            echo "[DECOMPRESS] Unpack zip: $src_file"
            unzip -o "$src_file" 2>/dev/null
            out_img=$(ls -1 *.img 2>/dev/null | head -n1)
            ;;
        *.7z)
            echo "[DECOMPRESS] Unpack 7z: $src_file"
            bsdtar -xmf "$src_file" 2>/dev/null || 7z x "$src_file" -aoa -y 2>/dev/null
            out_img=$(ls -1 *.img 2>/dev/null | head -n1)
            ;;
        *.img)
            out_img="$src_file"
            ;;
        *)
            error_msg "Unsupported firmware format: $src_file"
            ;;
    esac
    [[ ! -f "$out_img" ]] && error_msg "Decompress failed, no .img found from $src_file"
    echo "$out_img"
}

#==================== Init Env & Global Var ====================
trap cleanup EXIT SIGINT SIGTERM
IMG_ARG="${1}"
AUTO_MAINLINE_UBOOT="${2}"
TMP_WORK_DIR=$(mktemp -d /tmp/ow-upgrade.XXXXXX)
WORK_P1="${TMP_WORK_DIR}/boot_src"
WORK_P2="${TMP_WORK_DIR}/root_src"
SRC_ROOT_DIR=$(mktemp -d /tmp/src_root.XXXXXX)
TARGET_ROOT_MP=$(mktemp -d /tmp/target_root.XXXXXX)
mkdir -p "${WORK_P1}" "${WORK_P2}"

# Check device
MYDEVICE_NAME=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\000')
[[ -z "${MYDEVICE_NAME}" ]] && error_msg "Device model empty, cannot recognize hardware"
[[ ! -f "/etc/flippy-openwrt-release" ]] && error_msg "Missing /etc/flippy-openwrt-release, not flippy amlogic OpenWrt"
echo -e "\033[32mCurrent Device: ${MYDEVICE_NAME} [Amlogic STB]\033[0m"
sleep 1

# Check mount point
BOOT_PT_RAW=$(get_boot_partition_name)
ROOT_PT_RAW=$(get_root_partition_name)
[[ -z "${BOOT_PT_RAW}" || -z "${ROOT_PT_RAW}" ]] && {
    echo "[WARN] Partition mount missing, try auto repair..."
    openwrt-backup -g
    BOOT_PT_RAW=$(get_boot_partition_name)
    ROOT_PT_RAW=$(get_root_partition_name)
    [[ -z "${BOOT_PT_RAW}" || -z "${ROOT_PT_RAW}" ]] && error_msg "Boot/root partition still missing after repair"
}

# Distinguish EMMC / USB / SD disk type
ROOT_PTNAME="${ROOT_PT_RAW}"
case ${ROOT_PTNAME} in
mmcblk?p[1-4])
    EMMC_NAME=$(echo "${ROOT_PTNAME}" | awk '{print substr($1, 1, length($1)-2)}')
    if lsblk -l -o NAME | grep "${EMMC_NAME}boot0" >/dev/null; then
        ROOT_DISK_TYPE="EMMC"
    else
        ROOT_DISK_TYPE="SD"
    fi
    PARTITION_NAME="p"
    LB_PRE="${ROOT_DISK_TYPE}_"
    ;;
[hsv]d[a-z][1-4])
    EMMC_NAME=$(echo "${ROOT_PTNAME}" | awk '{print substr($1, 1, length($1)-1)}')
    ROOT_DISK_TYPE="USB"
    PARTITION_NAME=""
    LB_PRE="${ROOT_DISK_TYPE}_"
    ;;
*)
    error_msg "Unrecognized disk partition: ${ROOT_PTNAME}, only mmcblk/sd/hd/vd supported"
    ;;
esac
DOCKER_ROOT="/mnt/${EMMC_NAME}${PARTITION_NAME}4/docker/"
cd "/mnt/${EMMC_NAME}${PARTITION_NAME}4/"
mv -f /tmp/upload/* . 2>/dev/null && sync

#==================== Step1 Load & Decompress Firmware ====================
ORIG_IMG=""
RAW_INPUT_FILE=""
# Read input arg or auto scan
if [[ -n "${IMG_ARG}" && -f "${IMG_ARG}" ]]; then
    RAW_INPUT_FILE="${IMG_ARG}"
else
    RAW_INPUT_FILE=""
    if [[ $(ls *.img -l 2>/dev/null | grep "^-" | wc -l) -ge 1 ]]; then
        RAW_INPUT_FILE=$(ls *.img | head -n 1)
    elif [[ $(ls *.img.xz -l 2>/dev/null | grep "^-" | wc -l) -ge 1 ]]; then
        RAW_INPUT_FILE=$(ls *.img.xz | head -n 1)
    elif [[ $(ls *.img.gz -l 2>/dev/null | grep "^-" | wc -l) -ge 1 ]]; then
        RAW_INPUT_FILE=$(ls *.img.gz | head -n 1)
    elif [[ $(ls *.7z -l 2>/dev/null | grep "^-" | wc -l) -ge 1 ]]; then
        RAW_INPUT_FILE=$(ls *.7z | head -n 1)
    elif [[ $(ls *.zip -l 2>/dev/null | grep "^-" | wc -l) -ge 1 ]]; then
        RAW_INPUT_FILE=$(ls *.zip | head -n 1)
    else
        error_msg "No firmware found! Place img/img.gz/img.xz/7z/zip in /mnt/${EMMC_NAME}${PARTITION_NAME}4/"
    fi
fi
ORIG_IMG="${RAW_INPUT_FILE}"
# Unified decompress to pure img
IMG_NAME=$(decompress_firmware "${RAW_INPUT_FILE}")
echo -e "\033[32m[FIRMWARE] Pure upgrade image: ${IMG_NAME}\033[0m"

# Check dependencies
DEPENDS="lsblk uuidgen grep awk btrfs mkfs.fat mkfs.btrfs md5sum fatlabel losetup blkid parted findmnt bsdtar 7z unzip gzip xz partprobe"
echo "[CHECK] Verify system dependencies..."
for dep in ${DEPENDS}; do
    WITCH=$(busybox which "${dep}")
    [[ -z "${WITCH}" ]] && error_msg "Missing dependency: ${dep}, cannot upgrade"
    echo "  ${dep} -> ${WITCH}"
done
echo "[CHECK] All dependencies pass"

#==================== Step2 Distinguish A/B Target Partition ====================
BOOT_PART_MSG=$(lsblk -l -o NAME,PATH,TYPE,UUID,MOUNTPOINT | awk '$3~/^part$/ && $5 ~ /^\/boot$/ {print $0}')
[[ -z "${BOOT_PART_MSG}" ]] && error_msg "/boot partition not found"
BOOT_NAME=$(echo "${BOOT_PART_MSG}" | awk '{print $1}')
BOOT_PATH=$(echo "${BOOT_PART_MSG}" | awk '{print $2}')
BOOT_UUID=$(echo "${BOOT_PART_MSG}" | awk '{print $4}')

ROOT_PART_MSG=$(get_root_partition_msg)
ROOT_NAME=$(echo "${ROOT_PART_MSG}" | awk '{print $1}')
ROOT_PATH=$(echo "${ROOT_PART_MSG}" | awk '{print $2}')
ROOT_UUID=$(echo "${ROOT_PART_MSG}" | awk '{print $4}')

case ${ROOT_NAME} in
${EMMC_NAME}${PARTITION_NAME}2)
    NEW_ROOT_NAME="${EMMC_NAME}${PARTITION_NAME}3"
    NEW_ROOT_LABEL="${LB_PRE}ROOTFS2"
    ;;
${EMMC_NAME}${PARTITION_NAME}3)
    NEW_ROOT_NAME="${EMMC_NAME}${PARTITION_NAME}2"
    NEW_ROOT_LABEL="${LB_PRE}ROOTFS1"
    ;;
*)
    error_msg "Root partition /dev/${ROOT_NAME} not A/B p2/p3, unsupported upgrade"
    ;;
esac
echo "[PART] Active root: /dev/${ROOT_NAME}"
echo "[PART] Target inactive root: /dev/${NEW_ROOT_NAME} (${NEW_ROOT_LABEL})"

NEW_ROOT_PART_MSG=$(lsblk -l -o NAME,PATH,TYPE,UUID,MOUNTPOINT | grep "${NEW_ROOT_NAME}" | awk '$3 ~ /^part$/ {print $0}')
[[ -z "${NEW_ROOT_PART_MSG}" ]] && error_msg "Target A/B partition ${NEW_ROOT_NAME} missing"
NEW_ROOT_PATH=$(echo "${NEW_ROOT_PART_MSG}" | awk '{print $2}')
NEW_ROOT_MP="${TARGET_ROOT_MP}"

#==================== Step3 Fix Busybox losetup (Remove -P parameter) ====================
echo "[LOOP] Attach pure img file to loop device..."
# Get free loop
LOOP_DEV=$(get_free_loop)
# Basic attach without -P (compatible busybox losetup)
losetup "${LOOP_DEV}" "${IMG_NAME}" 2>/dev/null || error_msg "losetup attach image failed"
echo "[LOOP] Attached image to ${LOOP_DEV}, scan partition table..."
# Scan partition table manually
partprobe "${LOOP_DEV}" 2>/dev/null
# Fix missing subdev nodes
fix_loopdev "${LOOP_DEV}"

WAIT_SEC=8
echo "[LOOP] Wait ${WAIT_SEC}s for partition nodes ready..."
while [[ ${WAIT_SEC} -ge 1 ]]; do
    sleep 1
    partprobe "${LOOP_DEV}" 2>/dev/null
    fix_loopdev "${LOOP_DEV}"
    WAIT_SEC=$((WAIT_SEC - 1))
done

# Double check p1/p2 exist
if [[ ! -b "${LOOP_DEV}p1" || ! -b "${LOOP_DEV}p2" ]]; then
    lsblk "${LOOP_DEV}"
    error_msg "Loop device ${LOOP_DEV} missing p1/p2 partitions, invalid OpenWrt img!"
fi

# Force unmount auto-mounted loop partitions
MOUNTED_LOOP=$(lsblk -l -o NAME,PATH,MOUNTPOINT | grep "${LOOP_DEV}" | awk '$3 !~ /^$/ {print $2}')
for dev in ${MOUNTED_LOOP}; do
    while :; do
        umount -f "${dev}" 2>/dev/null
        mnt_check=$(lsblk -l -o PATH,MOUNTPOINT | grep "^${dev} " | awk '{print $2}')
        [[ -z "${mnt_check}" ]] && break
        sleep 1
    done
done

# Mount source boot(p1) and root(p2) from image
echo "[MOUNT] Mount image source boot partition ${LOOP_DEV}p1"
mount -t vfat -o ro "${LOOP_DEV}p1" "${WORK_P1}" || {
    losetup -D "${LOOP_DEV}"
    error_msg "Mount image boot p1 failed"
}
echo "[MOUNT] Mount image source root partition ${LOOP_DEV}p2"
ZSTD_LEVEL=6
mount -t btrfs -o ro,compress=zstd:${ZSTD_LEVEL} "${LOOP_DEV}p2" "${WORK_P2}" || {
    umount -f "${WORK_P1}"
    losetup -D "${LOOP_DEV}"
    error_msg "Mount image root p2 failed"
}

# Read firmware release info
env_openwrt_file=""
if [[ -f "${WORK_P2}/etc/flippy-openwrt-release" ]]; then
    env_openwrt_file="${WORK_P2}/etc/flippy-openwrt-release"
elif [[ -f "/etc/flippy-openwrt-release" ]]; then
    env_openwrt_file="/etc/flippy-openwrt-release"
fi
UBOOT_OVERLOAD=""
MAINLINE_UBOOT=""
ANDROID_UBOOT=""
[[ -n "${env_openwrt_file}" ]] && source "${env_openwrt_file}" 2>/dev/null

#==================== Step4 Repair N1 Partition Offset & Format Target Root ====================
if [[ "${NEW_ROOT_NAME}" == "${EMMC_NAME}p2" ]]; then
    if [[ "${MYDEVICE_NAME}" == "Phicomm N1" || "${MYDEVICE_NAME}" == "Octopus Planet" ]]; then
        SAFE_OFFSET_MB=800
        check_and_fix_partition "${EMMC_NAME}" "p2" 2 ${SAFE_OFFSET_MB}
    fi
fi

echo "[FORMAT] Unmount target root ${NEW_ROOT_PATH}"
umount -f "${NEW_ROOT_PATH}" 2>/dev/null || echo "[WARN] Target partition not mounted, skip umount"

NEW_ROOT_UUID=$(uuidgen)
echo "[FORMAT] New rootfs UUID: ${NEW_ROOT_UUID}"
echo "[FORMAT] Format ${NEW_ROOT_PATH} to btrfs label ${NEW_ROOT_LABEL}"
mkfs.btrfs -f -U "${NEW_ROOT_UUID}" -L "${NEW_ROOT_LABEL}" -m single "${NEW_ROOT_PATH}" || error_msg "Format target partition failed"

mount -t btrfs -o compress=zstd:${ZSTD_LEVEL} "${NEW_ROOT_PATH}" "${NEW_ROOT_MP}" || error_msg "Mount formatted target root failed"

#==================== Step5 Copy RootFS To Target Partition ====================
echo "[COPY] Start copy root filesystem to inactive partition..."
cd "${NEW_ROOT_MP}"
OLD_ENTRYS=$(ls)
for entry in ${OLD_ENTRYS}; do
    [[ "${entry}" == "lost+found" ]] && continue
    rm -rf "${entry}" || error_msg "Clean old data ${entry} failed"
done

btrfs subvolume create etc
mkdir -p .snapshots .reserved bin boot dev lib opt mnt overlay proc rom root run sbin sys tmp usr www
ln -sf lib/ lib64
ln -sf tmp/ var
sync

COPY_SRC_LIST="root etc bin sbin lib opt usr www"
for src_dir in ${COPY_SRC_LIST}; do
    echo "[COPY] Transfer ${src_dir}"
    (cd "${WORK_P2}" && tar cf - "${src_dir}") | tar xf -
    sync
done

# Docker persistent link
[[ ! -d "${DOCKER_ROOT}" ]] && mkdir -p "${DOCKER_ROOT}"
rm -rf opt/docker && ln -sf "${DOCKER_ROOT}" opt/docker


# Write fstab
cat > "${NEW_ROOT_MP}/etc/fstab" <<EOF
UUID=${NEW_ROOT_UUID} / btrfs compress=zstd:${ZSTD_LEVEL} 0 1
LABEL=${LB_PRE}BOOT /boot vfat defaults 0 2
EOF

cat > "${NEW_ROOT_MP}/etc/config/fstab" <<EOF
config  global
        option anon_swap '0'
        option anon_mount '1'
        option auto_swap '0'
        option auto_mount '1'
        option delay_root '5'
        option check_fs '0'
config  mount
        option target '/rom'
        option uuid '${NEW_ROOT_UUID}'
        option enabled '1'
        option enabled_fsck '1'
        option fstype 'btrfs'
        option options 'compress=zstd:${ZSTD_LEVEL}'
config  mount
        option target '/boot'
        option label '${LB_PRE}BOOT'
        option enabled '1'
        option enabled_fsck '1'
        option fstype 'vfat'
EOF

echo "[BTRFS] Create base etc snapshot .snapshots/etc-000"
btrfs subvolume snapshot -r etc .snapshots/etc-000
sync

#==================== Step6 Modify Boot Args (Only uEnv.txt, /boot untouched) ====================
echo "[BOOT] Only update root UUID in /boot/uEnv.txt, keep all boot files unchanged"
UENV_BACKUP="/boot/uEnv.txt.bak.upgrade"
cp /boot/uEnv.txt "${UENV_BACKUP}"
echo "[BOOT] Backup original uEnv.txt to ${UENV_BACKUP}"

if grep -E "^APPEND=" /boot/uEnv.txt; then
    sed -i "s|root=UUID=[0-9a-f-]*|root=UUID=${NEW_ROOT_UUID}|" /boot/uEnv.txt
elif grep -E "^bootargs=" /boot/uEnv.txt; then
    sed -i -E "s|root=UUID=[0-9a-f-]*|root=UUID=${NEW_ROOT_UUID}|" /boot/uEnv.txt
else
    source /boot/uEnv.txt 2>/dev/null
    cat >> /boot/uEnv.txt <<EOF
APPEND=root=UUID=${NEW_ROOT_UUID} rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF
fi
sync

[[ -f "/boot/extlinux/extlinux.conf" ]] && sed -i -E "s|UUID=[0-9a-f-]*|root=UUID=${NEW_ROOT_UUID}|" /boot/extlinux/extlinux.conf

#==================== Step7 Mainline U-Boot Flash ====================
FLASH_MAINLINE_UBOOT=0
if [[ -n "${MAINLINE_UBOOT}" && -f "${WORK_P2}${MAINLINE_UBOOT}" ]]; then
    echo -e "\033[33m[UBOOT] Image contains mainline u-boot binary\033[0m"
    if [[ "${AUTO_MAINLINE_UBOOT}" == "yes" ]]; then
        yn="y"
    elif [[ "${AUTO_MAINLINE_UBOOT}" == "no" ]]; then
        yn="n"
    else
        read -p "Flash mainline u-boot to emmc? y/n " yn
    fi
    case ${yn} in
    y|Y) FLASH_MAINLINE_UBOOT=1 ;;
    n|N) FLASH_MAINLINE_UBOOT=0 ;;
    esac
fi

if [[ ${FLASH_MAINLINE_UBOOT} -eq 1 ]]; then
    echo "[UBOOT] Write mainline u-boot to /dev/${EMMC_NAME}"
    dd if="${WORK_P2}${MAINLINE_UBOOT}" of="/dev/${EMMC_NAME}" bs=1 count=444 conv=fsync
    dd if="${WORK_P2}${MAINLINE_UBOOT}" of="/dev/${EMMC_NAME}" bs=512 skip=1 seek=1 conv=fsync
elif [[ -n "${ANDROID_UBOOT}" && -f "${WORK_P2}${ANDROID_UBOOT}" ]]; then
    echo "[UBOOT] Write android u-boot to /dev/${EMMC_NAME}"
    dd if="${WORK_P2}${ANDROID_UBOOT}" of="/dev/${EMMC_NAME}" bs=1 count=444 conv=fsync
    dd if="${WORK_P2}${ANDROID_UBOOT}" of="/dev/${EMMC_NAME}" bs=512 skip=1 seek=1 conv=fsync
else
    echo "[UBOOT] Keep original device bootloader, no write"
fi

#==================== Step8 Finish & Reboot ====================
echo -e "\033[32m=============================================\033[0m"
echo -e "\033[32mUpgrade completed successfully!\033[0m"
echo "1. New rootfs written to inactive partition /dev/${NEW_ROOT_NAME}"
echo "2. /boot partition all original files reserved, only root UUID updated in uEnv.txt"
echo "3. Original boot config backup: ${UENV_BACKUP}"
echo "4. System will auto reboot in 3 seconds, boot new system"
echo -e "\033[32m=============================================\033[0m"

sync
sleep 3
echo "reboot"
exit 0
