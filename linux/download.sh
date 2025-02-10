#! /usr/bin/env bash
#
# Download all build dependencies if they are missing. A function was created
# to avoid dpkg dependency for target file extraction.
# Usage: ./download.sh SRC_ROOT CACHE_DIR
#

set -e

if [ -z "$1" ] || [ -z "$2" ] ; then
    printf 'ERROR: Missing input.\n  Usage: %s SRC_ROOT CACHE_DIR\n' "$(basename $0)"
    exit 1
fi

SRC_ROOT="$1"
CACHE="$2"

PXE="pxe-server"
OUTPUT_PXE="$SRC_ROOT/$PXE"

## Common command flags / funtions
out() { printf "\n\033[32m[+] %s \033[0m\n" "$1"; }
die() { printf "\n\033[31;1mERROR: %s \033[0m\n" "$1"; }
WGET="wget --quiet --show-progress"

# Function to grab and extract a .deb archive.
get_extract_deb() {
    local url="$1" # download path of .deb file
    local sha256="$2" # sha of .deb file

    # Create tempdir
    TEMPDIR=$(mktemp -d)
    trap 'rm -r $TEMPDIR' EXIT

    # Download package and validate sha
    $WGET $url -O "$TEMPDIR/package.deb" ||  die "Could not download file with URL $url"
    echo "$sha256 $TEMPDIR/package.deb" | sha256sum -c || die "SHA not identical for $(basename $url)"
    # Extract the package and the data archive
    ar x "$TEMPDIR/package.deb" --output $TEMPDIR && tar -xf "$TEMPDIR/data.tar.xz" -C $TEMPDIR
}

# Download alpine-make-rootfs script if not already present
if ! [ -x "$CACHE/alpine-make-rootfs" ] ; then
    # Note: Not the latest branch
    $WGET -P $CACHE https://raw.githubusercontent.com/alpinelinux/alpine-make-rootfs/v0.7.2/alpine-make-rootfs \
      || die "Could not download file with URL $url"

    echo "2ebf310a0c6eb1b3ac9587d6211f1e84227846f0  $CACHE/alpine-make-rootfs" | sha1sum -c \
      || die "SHA not identical for alpine-make-rootfs."

    # Make it executable
    chmod +x $CACHE/alpine-make-rootfs
fi

# Download shim if missing
if ! [ -f "$OUTPUT_PXE/shimx64.efi" ] ; then
    out 'shimx64.efi missing, downloading...'
    get_extract_deb 'https://snapshot.debian.org/file/87601be283ef7209f6907d6e0df10aa29e5f4ede/shim-signed_1.44%2B15.8-1_amd64.deb' \
    '3a98352f0b01da23d059647e917eb0d6f1fd6dedb46a0e1b82c3c1e89871c1a1'

    ARTIFACT="$PXE/shimx64.efi"
    find $TEMPDIR -name 'shimx64.efi.signed' -exec cp {} $ARTIFACT \; ; rm -rf $TEMPDIR
    out "Created $ARTIFACT."
fi

# Download grub if missing
if ! [ -f "$OUTPUT_PXE/grubx64.efi" ] ; then
    out 'grubx64.efi missing, downloading...'
    get_extract_deb 'https://snapshot.debian.org/archive/debian/20240716T023930Z/pool/main/g/grub-efi-amd64-signed/grub-efi-amd64-signed_1%2B2.12%2B5_amd64.deb' \
    '76c314a1d8b5075d8727fc301fc9d57e39dc25289d4bd912aa3d8ffebd17ac6b'

    ARTIFACT="$PXE/grubx64.efi"
    find $TEMPDIR -name 'grubnetx64.efi.signed' -exec cp {} $ARTIFACT \; ; rm -rf $TEMPDIR
    out "Created $ARTIFACT."
fi

# Download kernel and kerneldrivers if missing. Cache the artifacts because
# they are bigger then the other packages
if ! [ -d "$CACHE/lib" ] || ! [ -f "$OUTPUT_PXE/linux" ]; then
    out 'kernel / drivers missing, downloading...'
    get_extract_deb 'https://snapshot.debian.org/file/80c35e7ae9d403ebea4a05a83c0cf7871d0c23f7' \
    '34c3595b6ac8c74fe754d375e04428624e598e4c8ce0d49eaaeceed5324baf31'

    out 'Copying files...'
    find $TEMPDIR -maxdepth 1 -type d -name 'lib' -exec cp -R {} $CACHE/lib \;
    # Copy file into CACHE and pxe server
    echo "$CACHE/vmlinuz $OUTPUT_PXE/linux" | xargs -n 1 cp $(find $TEMPDIR -name 'vmlinuz*')
    rm -rf $TEMPDIR
    out "Created $CACHE/{lib,vmlinuz} and $PXE/linux."
fi

# Deactivate trap
trap - EXIT
