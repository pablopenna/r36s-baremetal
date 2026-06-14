#!/usr/bin/env bash
#
# Install the bare-metal image onto the R36S boot partition.
#
# Usage:  ./flash.sh /path/to/mounted/boot/partition
#
# The boot partition is the FAT/"EFI System" one (sda1 in partition_info.txt,
# 512 MB) that contains /Image, /extlinux/extlinux.conf, etc. Mount it, then
# pass its mountpoint here.
#
# This is fully reversible: it backs up the original Image and extlinux.conf
# the first time, copies hello.bin alongside them, and switches extlinux to
# boot it. Run ./flash.sh <dir> restore  to put ArkOS back.

set -euo pipefail

BOOT="${1:-}"
MODE="${2:-install}"

if [[ -z "$BOOT" || ! -d "$BOOT" ]]; then
    echo "usage: $0 /path/to/mounted/boot/partition [install|restore]" >&2
    exit 1
fi
if [[ ! -f "$BOOT/extlinux/extlinux.conf" ]]; then
    echo "error: $BOOT/extlinux/extlinux.conf not found -- is this the boot partition?" >&2
    exit 1
fi

CONF="$BOOT/extlinux/extlinux.conf"

if [[ "$MODE" == "restore" ]]; then
    if [[ -f "$CONF.arkos" ]]; then
        cp -v "$CONF.arkos" "$CONF"
        echo "Restored original extlinux.conf. ArkOS will boot normally."
    else
        echo "No backup ($CONF.arkos) found; nothing to restore."
    fi
    sync
    exit 0
fi

# --- install ---
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "$HERE/hello.bin" ]]; then
    echo "error: hello.bin not built. Run 'make' first." >&2
    exit 1
fi

# Back up the stock config exactly once.
[[ -f "$CONF.arkos" ]] || cp -v "$CONF" "$CONF.arkos"

cp -v "$HERE/hello.bin" "$BOOT/hello.bin"

# Keep FDT so our program receives a valid DTB pointer in x0 (useful for the
# next milestones). Drop INITRD -- the bare-metal image doesn't use it.
cat > "$CONF" <<'EOF'
LABEL bare-metal
  LINUX /hello.bin
  FDT /rf3536k3ka.dtb
EOF

sync
echo
echo "Installed. extlinux now boots /hello.bin."
echo "To go back to ArkOS:  $0 \"$BOOT\" restore"
