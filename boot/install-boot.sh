#!/bin/bash
# Quiet Plymouth boot and autologin on tty1 instead of Plasma Login Manager.
# Run once as root. Every file it edits is backed up next to itself as *.bak-<time>.
set -euo pipefail

USER_NAME=owner
SRC=/home/owner/.config/hypr/boot
STAMP=$(date +%Y%m%d-%H%M%S)
ESP_LOADER=/efi/loader/loader.conf

backup() { if [ -e "$1" ]; then cp -a "$1" "$1.bak-$STAMP"; fi; }
step() { printf '\n== %s\n' "$1"; }

step "plymouth"
pacman -S --needed --noconfirm plymouth
install -d /usr/share/plymouth/themes/ink
install -m644 "$SRC"/plymouth/ink/* /usr/share/plymouth/themes/ink/
plymouth-set-default-theme ink
printf 'add_dracutmodules+=" plymouth "\n' > /etc/dracut.conf.d/plymouth.conf

step "kernel command line"
backup /etc/kernel/cmdline
cmdline=$(tr -s ' \n' ' ' < /etc/kernel/cmdline | sed 's/ *$//')
for p in quiet splash loglevel=3 rd.udev.log_level=3 udev.log_level=3 \
         systemd.show_status=false rd.systemd.show_status=false \
         vt.global_cursor_default=0 plymouth.ignore-serial-consoles; do
    case " $cmdline " in *" $p "*) ;; *) cmdline="$cmdline $p" ;; esac
done
printf '%s\n' "$cmdline" > /etc/kernel/cmdline
echo "$cmdline"

step "boot menu (hold Space at power-on to show it)"
if [ -f "$ESP_LOADER" ]; then
    backup "$ESP_LOADER"
    if grep -q '^timeout' "$ESP_LOADER"; then
        sed -i 's/^timeout.*/timeout 0/' "$ESP_LOADER"
    else
        printf 'timeout 0\n' >> "$ESP_LOADER"
    fi
    cat "$ESP_LOADER"
fi

step "autologin on tty1, no display manager"
install -d /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --skip-login --nonewline --noissue --autologin $USER_NAME %I \$TERM
EOF
cat /etc/systemd/system/getty@tty1.service.d/autologin.conf
systemctl daemon-reload
systemctl enable getty@tty1.service
# Disable only: stopping it now would end the running session.
systemctl disable plasmalogin.service

step "rebuild initramfs and boot entries"
reinstall-kernels

step "check"
grep -h '^options' /efi/loader/entries/*.conf || true
lsinitrd 2>/dev/null | grep -c plymouth || true
echo "done"
