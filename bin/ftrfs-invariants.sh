#!/bin/bash
#
# ftrfs-invariants.sh -- static invariants validation for FTRFS sources.
#
# Run before hpc-benchmark.sh as a fast pre-check. Tests are static (no VM,
# no kernel module load required) and complete in seconds. Useful as a
# pre-commit gate or as the first stage of ftrfs-validate.sh.
#
# Audit rationale: invariants checked here encode contracts that must
# hold for the on-disk format and the kernel/userspace co-compilation to
# remain consistent. A regression here implies a regression in the
# foundational guarantees of the filesystem and must be diagnosed before
# any further validation step is meaningful.
#
# Exit codes:
#   0 -- all invariants hold
#   non-zero -- at least one invariant violated; details on stderr
#

set -e

FTRFS_SRC="${HOME}/git/ftrfs"
LAYER_SRC="${HOME}/git/yocto-hardened"

red()    { printf '\e[31m%s\e[0m\n' "$*"; }
green()  { printf '\e[32m%s\e[0m\n' "$*"; }
yellow() { printf '\e[33m%s\e[0m\n' "$*"; }

fail=0
check() {
    local name="$1"
    shift
    if "$@"; then
        green "PASS: $name"
    else
        red "FAIL: $name"
        fail=1
    fi
}

echo "================================================================"
echo " FTRFS invariants check -- $(date)"
echo "================================================================"

# --------------------------------------------------------------------
# Invariant 1: no SB-related magic numbers in the 5 critical functions.
# --------------------------------------------------------------------
# After commit 4a refactor, these 5 functions must use offsetof and
# defines exclusively, never numeric literals like 64/68/1689/1685/1688.
# Defines themselves (FTRFS_SB_RS_*) live at the top of mkfs.ftrfs.c
# lines 40-46 and ftrfs.h, and are explicitly excluded from this check.
inv1_no_sb_magic() {
    local hits
    hits=$(grep -nE '\b(64|68|1685|1688|1689|1621)\b' \
                "${FTRFS_SRC}/edac.c" \
                "${FTRFS_SRC}/super.c" \
                "${FTRFS_SRC}/mkfs.ftrfs.c" 2>/dev/null \
            | grep -vE 'FTRFS_SB_RS_|^[^:]+:4[0-9]:#define|0x|inode|/\* (Block|format)' \
            | grep -E 'sb|SB|coverage|staging|s_crc32|s_uuid|s_pad' \
            || true)
    if [ -n "$hits" ]; then
        echo "  Magic numbers found:" >&2
        echo "$hits" | sed 's/^/    /' >&2
        return 1
    fi
    return 0
}
check "no SB magic numbers in critical functions" inv1_no_sb_magic

# Invariant 2 (mkfs standalone syntax check) was removed: bitbake -c
# compile already performs the authoritative cross-compilation, which is
# stricter than any host-side syntax check. Duplicating it here added
# fragility (kernel-headers dependency on Gentoo) without gain.

# --------------------------------------------------------------------
# Invariant 3: mkfs binary produces a non-trivial superblock.
# --------------------------------------------------------------------
# Builds an image, hexdumps the SB, checks that:
#  - magic word at offset 0 is 'FTRF' (0x46545246 little-endian)
#  - s_crc32 (offset 64) is non-zero (mkfs computed a CRC)
#  - parity zone at offset 3968 is non-zero (mkfs encoded RS parity)
inv3_mkfs_image_layout() {
    local img mkfs_bin
    img=$(mktemp /tmp/ftrfs-inv3.XXXXXX.img)
    mkfs_bin="${FTRFS_SRC}/mkfs.ftrfs"

    if [ ! -x "$mkfs_bin" ]; then
        yellow "  mkfs.ftrfs not built; skipping" >&2
        rm -f "$img"
        return 0
    fi

    truncate -s 64M "$img"
    "$mkfs_bin" "$img" >/dev/null 2>&1 || { rm -f "$img"; return 1; }

    # Magic at offset 0 (4 bytes, LE 0x46545246 = 'FTRF')
    local magic
    magic=$(xxd -s 0 -l 4 -p "$img")
    if [ "$magic" != "46525446" ]; then
        echo "  Magic mismatch at offset 0: got $magic, want 46525446" >&2
        rm -f "$img"
        return 1
    fi

    # s_crc32 at offset 64 (4 bytes), must be non-zero
    local crc
    crc=$(xxd -s 64 -l 4 -p "$img")
    if [ "$crc" = "00000000" ]; then
        echo "  s_crc32 is zero (mkfs did not compute CRC)" >&2
        rm -f "$img"
        return 1
    fi

    # RS parity zone at offset 3968 (128 bytes), must be non-zero
    local parity
    parity=$(xxd -s 3968 -l 16 -p "$img")
    if [ "$parity" = "00000000000000000000000000000000" ]; then
        echo "  RS parity zone at offset 3968 is all zeros" >&2
        rm -f "$img"
        return 1
    fi

    rm -f "$img"
    return 0
}
check "mkfs produces well-formed superblock" inv3_mkfs_image_layout

# --------------------------------------------------------------------
# Invariant 4: ftrfs.ko has expected exported symbols.
# --------------------------------------------------------------------
# Checks the latest-built kernel module from Yocto. Looks for the core
# T (text) symbols introduced by stage 3.
inv4_ko_symbols() {
    local ko
    ko=$(find ~/yocto/poky/build-qemu-arm64/tmp/work/qemuarm64-poky-linux/ftrfs-module/ \
              -name 'ftrfs.ko' 2>/dev/null | head -1)
    if [ -z "$ko" ]; then
        yellow "  no built ftrfs.ko found; skipping" >&2
        return 0
    fi

    local missing=""
    for sym in ftrfs_rs_decode ftrfs_rs_decode_region \
               ftrfs_rs_encode ftrfs_rs_encode_region \
               ftrfs_log_rs_event ftrfs_crc32_sb \
               ftrfs_fill_super ftrfs_dirty_super; do
        if ! aarch64-poky-linux-nm --defined-only "$ko" 2>/dev/null \
                | grep -qE "T $sym\$"; then
            missing="$missing $sym"
        fi
    done

    # Fallback to plain nm if cross-nm not in PATH
    if [ -n "$missing" ]; then
        missing=""
        for sym in ftrfs_rs_decode ftrfs_rs_decode_region \
                   ftrfs_rs_encode ftrfs_rs_encode_region \
                   ftrfs_log_rs_event ftrfs_crc32_sb \
                   ftrfs_fill_super ftrfs_dirty_super; do
            if ! nm --defined-only "$ko" 2>/dev/null \
                    | grep -qE "T $sym\$"; then
                missing="$missing $sym"
            fi
        done
    fi

    if [ -n "$missing" ]; then
        echo "  Missing T symbols:$missing" >&2
        return 1
    fi
    return 0
}
check "ftrfs.ko has expected exported T symbols" inv4_ko_symbols

# --------------------------------------------------------------------
# Invariant 5: dirent scan loops do not break on d_rec_len == 0.
# --------------------------------------------------------------------
# After the dirent slot-reuse fix, dir.c (ftrfs_readdir, ftrfs_lookup)
# and namei.c (ftrfs_add_dirent, ftrfs_del_dirent, ftrfs_rmdir) must
# scan directory blocks fully -- they advance by sizeof(*de) and skip
# free slots (d_ino == 0). The pattern
#     if (!de->d_rec_len) break;
# would re-introduce the slot-reuse bug where a hole left by
# unlink hides live entries that follow it within the same block.
inv5_dirent_no_break_on_zero() {
    local hits
    hits=$(grep -nE '!.*d_rec_len.*\)' \
                "${FTRFS_SRC}/dir.c" \
                "${FTRFS_SRC}/namei.c" 2>/dev/null \
            | grep -vE 'd_rec_len[[:space:]]*=' \
            || true)
    if [ -n "$hits" ]; then
        local bad
        bad=$(echo "$hits" | while read -r line; do
            f=$(echo "$line" | cut -d: -f1)
            n=$(echo "$line" | cut -d: -f2)
            next=$(sed -n "$((n + 1))p" "$f" 2>/dev/null)
            if echo "$next" | grep -q "break"; then
                echo "$line"
            fi
        done)
        if [ -n "$bad" ]; then
            echo "  Found break-on-zero-rec_len pattern:" >&2
            echo "$bad" | sed 's/^/    /' >&2
            return 1
        fi
    fi
    return 0
}
check "dirent scan loops do not break on d_rec_len == 0" inv5_dirent_no_break_on_zero

# --------------------------------------------------------------------
echo "================================================================"
if [ "$fail" -eq 0 ]; then
    green "All invariants hold."
    exit 0
else
    red "One or more invariants violated."
    exit 1
fi
