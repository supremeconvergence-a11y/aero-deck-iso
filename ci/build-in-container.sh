#!/usr/bin/env bash
# Runs inside archlinux:latest (privileged) on GitHub Actions.
# Sets up CachyOS keys/mirrorlist so the Aero profile's pacman.conf works,
# then runs the official build-aero-deck.sh from the tarball.
set -euo pipefail

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

export AERO_DIR="${AERO_DIR:-/aero}"
export WORK_SIZE="${WORK_SIZE:-26G}"
export AERO_ISO_VERSION="${AERO_ISO_VERSION:-2026.11.23-monday}"
# Secure Boot signing happens on the runner; the private key is deleted later.
export AERO_SECUREBOOT="${AERO_SECUREBOOT:-1}"
EXPECTED_SHA="${EXPECTED_SHA:-42df269fcf7f259fda9ae8e6c4626d65cd3d404578b541e918a144adc6f042a9}"

# Never inherit or look up build secrets.
unset IPTV_USER IPTV_PASSWORD IPTV_PASS IPTV_URL KEYSTORE_PASSWORD \
      ANDROID_KEYSTORE_PASS AERO_IPTV 2>/dev/null || true

say "Disk before setup"
df -h

# ---- pacman + Arch keys ----
say "Initialize pacman keyring"
# A little extra entropy helps pacman-key --init in containers.
pacman-key --init
pacman-key --populate archlinux

# Sandbox can fail inside Docker; disable it if this pacman supports it.
PACMAN=(pacman)
if pacman --help 2>&1 | grep -q -- '--disable-sandbox'; then
    PACMAN=(pacman --disable-sandbox)
fi

say "Update Arch Linux (official repos only, before CachyOS is added)"
"${PACMAN[@]}" -Sy --noconfirm --needed archlinux-keyring
"${PACMAN[@]}" -Syu --noconfirm

say "Install official Arch build tools (keep this archiso; do not take a CachyOS fork)"
"${PACMAN[@]}" -S --needed --noconfirm \
    archiso squashfs-tools curl sbsigntools libarchive mtools openssl \
    gnupg flatpak e2fsprogs util-linux python ca-certificates-utils gawk \
    coreutils tar gzip findutils

# Hold archiso so a later pacman -Sy in build-aero-deck.sh cannot replace it
# with a CachyOS build the mkarchiso patch was not written for.
if ! grep -q '^IgnorePkg' /etc/pacman.conf; then
    sed -i 's/^#IgnorePkg.*/IgnorePkg    = archiso/' /etc/pacman.conf
    grep -q '^IgnorePkg' /etc/pacman.conf || sed -i '/^#IgnorePkg/a IgnorePkg    = archiso' /etc/pacman.conf
else
    sed -i 's/^IgnorePkg.*/IgnorePkg    = archiso/' /etc/pacman.conf
fi

# ---- CachyOS keyring + mirrorlist (needed by profile-monday/pacman.conf) ----
say "Add CachyOS key and keyring/mirrorlist packages"
recv_cachy_key() {
    local ks
    for ks in hkps://keyserver.ubuntu.com hkps://keys.openpgp.org hkp://keyserver.ubuntu.com; do
        if pacman-key --recv-keys F3B607488DB35A47 --keyserver "$ks"; then
            return 0
        fi
    done
    # Last resort: fetch the key over HTTPS and import it.
    curl -fL --retry 3 -o /tmp/cachyos.asc \
        'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF3B607488DB35A47' \
        || return 1
    pacman-key --add /tmp/cachyos.asc
}
recv_cachy_key || die "could not fetch the CachyOS signing key F3B607488DB35A47"
pacman-key --lsign-key F3B607488DB35A47

CACHY_BASE="https://mirror.cachyos.org/repo/x86_64/cachyos"
# Resolve current package names (versions change); fall back to known-good pins.
list=$(curl -fsSL "$CACHY_BASE/" || true)
pick() {
    local prefix="$1" fallback="$2" name
    name=$(printf '%s\n' "$list" | grep -oE "${prefix}-[0-9][^\"<> ]*-any\\.pkg\\.tar\\.zst" | sort -u | tail -1 || true)
    if [ -n "$name" ]; then printf '%s/%s\n' "$CACHY_BASE" "$name"
    else printf '%s/%s\n' "$CACHY_BASE" "$fallback"
    fi
}
KEYRING_PKG=$(pick 'cachyos-keyring' 'cachyos-keyring-20240331-1-any.pkg.tar.zst')
MIRROR_PKG=$(pick 'cachyos-mirrorlist' 'cachyos-mirrorlist-27-1-any.pkg.tar.zst')
echo "keyring: $KEYRING_PKG"
echo "mirrorlist: $MIRROR_PKG"
"${PACMAN[@]}" -U --noconfirm "$KEYRING_PKG" "$MIRROR_PKG"
pacman-key --populate cachyos

if ! grep -q '^\[cachyos\]' /etc/pacman.conf; then
    # Insert the generic [cachyos] repo above [core], matching the ISO profile.
    awk '
        BEGIN { done=0 }
        /^\[core\]/ && !done {
            print "[cachyos]"
            print "Include = /etc/pacman.d/cachyos-mirrorlist"
            print ""
            done=1
        }
        { print }
    ' /etc/pacman.conf > /etc/pacman.conf.new
    mv /etc/pacman.conf.new /etc/pacman.conf
fi
[ -f /etc/pacman.d/cachyos-mirrorlist ] || die "cachyos-mirrorlist missing after install"
"${PACMAN[@]}" -Sy --noconfirm
# Confirm the ISO's kernel is visible through the profile's [cachyos] repo.
"${PACMAN[@]}" -Si linux-cachyos >/dev/null \
    || die "linux-cachyos is not in the configured repos -- CachyOS setup failed"

say "CachyOS repo is ready; archiso=$(pacman -Q archiso)"

# ---- work dir + tarball ----
mkdir -p "$AERO_DIR" /out /mnt/work
touch "$AERO_DIR/.write-test" && rm -f "$AERO_DIR/.write-test"

TARBALL=""
for p in \
    "/src/Nuvio Aero OS.tar.gz" \
    /src/*/Nuvio\ Aero\ OS.tar.gz
 do
    [ -f "$p" ] && TARBALL="$p" && break
done
[ -n "$TARBALL" ] || die "Nuvio Aero OS.tar.gz not found under /src"
echo "$EXPECTED_SHA  $TARBALL" | sha256sum -c - \
    || die "tarball SHA-256 mismatch"

say "Extract official build-aero-deck.sh from the tarball"
tar -xOf "$TARBALL" build-aero-deck.sh > /tmp/build-aero-deck.sh
chmod +x /tmp/build-aero-deck.sh
[ -s /tmp/build-aero-deck.sh ] || die "build-aero-deck.sh missing from tarball"

say "Disk before ISO build (WORK_SIZE=$WORK_SIZE AERO_DIR=$AERO_DIR)"
df -h
ls -la "$AERO_DIR"

say "Running official build-aero-deck.sh (this takes a while)"
bash /tmp/build-aero-deck.sh "$TARBALL"

ISO="$AERO_DIR/aero-deck-$AERO_ISO_VERSION-x86_64.iso"
[ -f "$ISO" ] || ISO=$(ls -t "$AERO_DIR"/aero-deck-*-x86_64.iso | head -1)
[ -f "$ISO" ] || die "no ISO produced in $AERO_DIR"
SUM="$ISO.sha256"
[ -f "$SUM" ] || ( cd "$(dirname "$ISO")" && sha256sum "$(basename "$ISO")" | tee "$(basename "$ISO").sha256" )

say "Copy ISO to /out and wipe the Secure Boot private key"
cp -a "$ISO" "$SUM" /out/
# Public certificate is already inside the ISO; never ship the private key.
rm -f "$AERO_DIR/secureboot/aero-mok.key" /aero/secureboot/aero-mok.key || true
find /aero /out /tmp -name 'aero-mok.key' -delete 2>/dev/null || true

ls -lh /out
echo "ISO=/out/$(basename "$ISO")"
cat /out/"$(basename "$SUM")"
say "Disk after ISO build"
df -h
