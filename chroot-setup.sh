#!/usr/bin/env bash
set -euo pipefail

echo "== Timezone =="
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "== Locales =="
sed -i \
  -e 's/^#\(en_GB.UTF-8 UTF-8\)/\1/' \
  -e 's/^#\(en_US.UTF-8 UTF-8\)/\1/' \
  -e 's/^#\(ru_RU.UTF-8 UTF-8\)/\1/' \
  /etc/locale.gen
locale-gen

cat >/etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
LC_TIME=en_GB.UTF-8
EOF

echo "== Hostname =="
echo "arch" >/etc/hostname

echo "== Root password =="
passwd

echo "== User account =="
read -rp "Create a new user? [Y/n]: " CREATE_USER
CREATE_USER="${CREATE_USER:-Y}"
if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
  read -rp "Username: " NEWUSER
  useradd -m -G wheel "$NEWUSER"
  passwd "$NEWUSER"
  echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/wheel
  chmod 440 /etc/sudoers.d/wheel
fi

echo "== Bootloader =="
echo "1) grub"
echo "2) refind"
read -rp "Select bootloader [1]: " BOOTLOADER_CHOICE
BOOTLOADER_CHOICE="${BOOTLOADER_CHOICE:-1}"
case "$BOOTLOADER_CHOICE" in
1)
  pacman -S --noconfirm grub
  grub-install
  grub-mkconfig -o /boot/grub/grub.cfg
  ;;
2)
  pacman -S --noconfirm refind
  refind-install
  ;;
*)
  echo "Unrecognized choice '$BOOTLOADER_CHOICE'" >&2
  exit 1
  ;;
esac

echo "== systemd-networkd / NetworkManager =="
systemctl enable NetworkManager

echo "Chroot setup finished."
