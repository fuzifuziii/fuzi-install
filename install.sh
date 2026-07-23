#!/usr/bin/env bash
set -euo pipefail

CHROOT_SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chroot-setup.sh"

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
  fi
}

to_mib() {
  local input="${1^^}"
  local num unit
  num="${input%[GMT]}"
  unit="${input: -1}"
  case "$unit" in
  M) echo "${num%.*}" ;;
  G) awk -v n="$num" 'BEGIN{printf "%d", n*1024}' ;;
  T) awk -v n="$num" 'BEGIN{printf "%d", n*1024*1024}' ;;
  *)
    echo "Unrecognized size '$1' (use e.g. 512M, 8G)" >&2
    exit 1
    ;;
  esac
}

require_root

echo "== Disk selection =="
lsblk -d -o NAME,SIZE,MODEL
read -rp "Disk to install to (e.g. nvme0n1): " DISK_NAME
DISK="/dev/${DISK_NAME}"
if [[ ! -b "$DISK" ]]; then
  echo "No such block device: $DISK" >&2
  exit 1
fi

if [[ "$DISK_NAME" == nvme* || "$DISK_NAME" == mmcblk* ]]; then
  PART_SUFFIX="p"
else
  PART_SUFFIX=""
fi

DISK_SIZE_MIB=$(lsblk -b -d -n -o SIZE "$DISK")
DISK_SIZE_MIB=$((DISK_SIZE_MIB / 1024 / 1024))
echo "Disk size: ${DISK_SIZE_MIB} MiB"

echo
echo "== Partition sizing =="
echo "Enter sizes like 512M or 8G. Remaining space is shown after each step."

read -rp "EFI partition size [512M]: " EFI_SIZE
EFI_SIZE="${EFI_SIZE:-512M}"
EFI_MIB=$(to_mib "$EFI_SIZE")
REMAIN_MIB=$((DISK_SIZE_MIB - EFI_MIB))
echo "Remaining: ${REMAIN_MIB} MiB"

read -rp "Swap partition size [8G]: " SWAP_SIZE
SWAP_SIZE="${SWAP_SIZE:-8G}"
SWAP_MIB=$(to_mib "$SWAP_SIZE")
REMAIN_MIB=$((REMAIN_MIB - SWAP_MIB))
echo "Remaining for root (btrfs): ${REMAIN_MIB} MiB"

if ((REMAIN_MIB <= 1024)); then
  echo "Not enough space left for a root partition." >&2
  exit 1
fi

EFI_END_MIB=$((EFI_MIB))
SWAP_END_MIB=$((EFI_END_MIB + SWAP_MIB))

EFI_PART="${DISK}${PART_SUFFIX}1"
SWAP_PART="${DISK}${PART_SUFFIX}2"
ROOT_PART="${DISK}${PART_SUFFIX}3"

echo
echo "Plan for $DISK:"
echo "  $EFI_PART   EFI     1MiB -> ${EFI_END_MIB}MiB"
echo "  $SWAP_PART  swap    ${EFI_END_MIB}MiB -> ${SWAP_END_MIB}MiB"
echo "  $ROOT_PART  btrfs   ${SWAP_END_MIB}MiB -> 100%"
echo
read -rp "This ERASES all data on $DISK. Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || {
  echo "Aborted."
  exit 1
}

echo "== Partitioning =="
parted -s "$DISK" \
  mklabel gpt \
  mkpart EFI fat32 1MiB "${EFI_END_MIB}MiB" \
  set 1 esp on \
  mkpart swap linux-swap "${EFI_END_MIB}MiB" "${SWAP_END_MIB}MiB" \
  mkpart root btrfs "${SWAP_END_MIB}MiB" 100%

partprobe "$DISK"
udevadm settle

echo "== Formatting =="
mkfs.fat -F 32 "$EFI_PART"
mkswap "$SWAP_PART"
mkfs.btrfs -f "$ROOT_PART"

echo "== Mounting =="
mount "$ROOT_PART" /mnt
mount --mkdir "$EFI_PART" /mnt/boot
mount --mkdir "$EFI_PART" /mnt/boot/efi
swapon "$SWAP_PART"

echo "== Installing base system =="
pacstrap -K /mnt base linux-zen linux-zen-headers intel-ucode networkmanager grub efibootmgr neovim

genfstab -U /mnt >>/mnt/etc/fstab

echo "== Entering chroot for system configuration =="
cp "$CHROOT_SCRIPT_SRC" /mnt/root/chroot-setup.sh
chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh
rm -f /mnt/root/chroot-setup.sh

echo
echo "Install finished. You can reboot into the new system now."
