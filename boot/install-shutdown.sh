#!/bin/sh
# Quiet shutdown/reboot: show the Ink splash instead of text. Run as root.
set -eu

# The shutdown splash needs the display, which Hyprland holds until its session stops.
# Without this ordering plymouthd starts too early, falls back to text and turns
# systemd status output back on.
for unit in poweroff reboot halt kexec; do
    dir=/etc/systemd/system/plymouth-$unit.service.d
    mkdir -p "$dir"
    cat > "$dir/after-session.conf" << 'EOF'
[Unit]
After=user.slice
EOF
done

# systemd arms the hardware watchdog for the final reboot step, and the kernel then
# prints "watchdog did not stop!" at critical level, which loglevel=3 still shows.
mkdir -p /etc/systemd/system.conf.d /etc/systemd/user.conf.d
cat > /etc/systemd/system.conf.d/quiet-shutdown.conf << 'EOF'
[Manager]
ShowStatus=no
RebootWatchdogSec=0
KExecWatchdogSec=0
DefaultTimeoutStopSec=10s
EOF
cat > /etc/systemd/user.conf.d/quiet-shutdown.conf << 'EOF'
[Manager]
DefaultTimeoutStopSec=10s
EOF

systemctl daemon-reload
echo done
