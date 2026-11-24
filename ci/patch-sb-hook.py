#!/usr/bin/env python3
"""Patch aero_sb_shim so it works with current mkarchiso (arch=x64, file=BOOTx64.EFI)."""
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()
old = """aero_sb_shim() {
    aero_sb_on || return 0
    [[ \"${1:-}\" == \"X64\" ]] || return 0
    local d=\"${isofs_dir}/EFI/BOOT\"
    [[ -f \"$d/BOOTX64.EFI\" ]] || { echo \"[aero-secureboot] ERROR: no systemd-boot at $d/BOOTX64.EFI\" >&2; exit 1; }
    install -m 0644 -- \"$d/BOOTX64.EFI\" \"$d/grubx64.efi\"
    aero_sb_sign \"$d/grubx64.efi\"
    install -m 0644 -- \"${AERO_SB_DIR}/shimx64.efi\" \"$d/BOOTX64.EFI\"
    install -m 0644 -- \"${AERO_SB_DIR}/mmx64.efi\" \"$d/mmx64.efi\"
    install -m 0644 -- \"${AERO_SB_DIR}/aero-mok.cer\" \"${isofs_dir}/EFI/aero-mok.cer\"
    echo \"[aero-secureboot] shim + MokManager + signed systemd-boot in EFI/BOOT\"
    return 0
}"""
# The file on disk doesn't have escaped quotes; rebuild old from actual content.
old = r'''aero_sb_shim() {
    aero_sb_on || return 0
    [[ "${1:-}" == "X64" ]] || return 0
    local d="${isofs_dir}/EFI/BOOT"
    [[ -f "$d/BOOTX64.EFI" ]] || { echo "[aero-secureboot] ERROR: no systemd-boot at $d/BOOTX64.EFI" >&2; exit 1; }
    install -m 0644 -- "$d/BOOTX64.EFI" "$d/grubx64.efi"
    aero_sb_sign "$d/grubx64.efi"
    install -m 0644 -- "${AERO_SB_DIR}/shimx64.efi" "$d/BOOTX64.EFI"
    install -m 0644 -- "${AERO_SB_DIR}/mmx64.efi" "$d/mmx64.efi"
    install -m 0644 -- "${AERO_SB_DIR}/aero-mok.cer" "${isofs_dir}/EFI/aero-mok.cer"
    echo "[aero-secureboot] shim + MokManager + signed systemd-boot in EFI/BOOT"
    return 0
}'''
new = r'''aero_sb_shim() {
    aero_sb_on || return 0
    # Current mkarchiso: uefi_arch[x86_64]=x64 (also called later with IA32).
    case "${1:-}" in
        X64|x64) ;;
        IA32|ia32) return 0 ;;
        *) echo "[aero-secureboot] aero_sb_shim skipped (arch=${1:-})"; return 0 ;;
    esac
    local d="${isofs_dir}/EFI/BOOT"
    local bootefi="" c
    for c in "$d/BOOTX64.EFI" "$d/BOOTx64.EFI" "$d/bootx64.efi"; do
        if [[ -f "$c" ]]; then bootefi="$c"; break; fi
    done
    [[ -n "$bootefi" ]] || { echo "[aero-secureboot] ERROR: no systemd-boot in $d (arch=${1:-})" >&2; exit 1; }
    install -m 0644 -- "$bootefi" "$d/grubx64.efi"
    aero_sb_sign "$d/grubx64.efi"
    install -m 0644 -- "${AERO_SB_DIR}/shimx64.efi" "$bootefi"
    if [[ "$bootefi" != "$d/BOOTX64.EFI" ]]; then
        install -m 0644 -- "${AERO_SB_DIR}/shimx64.efi" "$d/BOOTX64.EFI"
    fi
    install -m 0644 -- "${AERO_SB_DIR}/mmx64.efi" "$d/mmx64.efi"
    install -m 0644 -- "${AERO_SB_DIR}/aero-mok.cer" "${isofs_dir}/EFI/aero-mok.cer"
    echo "[aero-secureboot] shim + MokManager + signed systemd-boot in EFI/BOOT (from ${bootefi##*/})"
    return 0
}'''
if old not in t:
    raise SystemExit(f'aero_sb_shim block not found in {p}')
p.write_text(t.replace(old, new, 1))
print(f'patched {p}')
