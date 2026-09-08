#!/bin/bash
# Turns out/ into a signed apt archive under public/, ready for Pages.
#
#   scripts/build-archive.sh                  unsigned, for a local check
#   GPG_KEY_ID=<fpr> scripts/build-archive.sh signed, which is what CI does

set -eE
trap 'echo "Error: in $0 on line $LINENO"' ERR
cd "$(dirname "$0")/.."

ORIGIN=Mixtile
PUB=public
rm -rf "${PUB}"; mkdir -p "${PUB}/pool/main"

[ -d out ] || { echo "Error: nothing in out/ to publish"; exit 1; }
find out -name '*.deb' -exec cp {} "${PUB}/pool/main/" \;
echo "==> pool: $(find "${PUB}/pool/main" -name '*.deb' | wc -l | tr -d ' ') packages"

for suite in $(grep -vE '^[[:space:]]*(#|$)' suites); do
    [ -d "out/${suite}" ] || continue
    d="${PUB}/dists/${suite}/main/binary-arm64"
    mkdir -p "${d}"

    # One pool for every suite, with dists/<suite>/ selecting from it by the
    # ~suite tail of the version. Paths inside Packages must be relative to
    # the archive root, so the scan runs from there.
    ( cd "${PUB}" && apt-ftparchive packages pool/main ) |
        awk -v s="~${suite}" 'BEGIN{RS="";ORS="\n\n"} $0 ~ s' > "${d}/Packages"
    gzip -9kf "${d}/Packages"

    # Written outside the tree and moved in: redirecting straight into
    # dists/<suite>/ creates the file before apt-ftparchive scans that
    # directory, and Release then appears in its own checksums.
    ( cd "${PUB}" && apt-ftparchive \
        -o "APT::FTPArchive::Release::Origin=${ORIGIN}" \
        -o "APT::FTPArchive::Release::Label=${ORIGIN}" \
        -o "APT::FTPArchive::Release::Suite=${suite}" \
        -o "APT::FTPArchive::Release::Codename=${suite}" \
        -o "APT::FTPArchive::Release::Architectures=arm64" \
        -o "APT::FTPArchive::Release::Components=main" \
        release "dists/${suite}" ) > "${PUB}/.Release.tmp"
    mv "${PUB}/.Release.tmp" "${PUB}/dists/${suite}/Release"

    echo "==> ${suite}: $(grep -c '^Package: ' "${d}/Packages" || true) packages"

    # InRelease only. A detached Release.gpg buys nothing here: every apt that
    # can reach this archive has understood the inline form for years.
    if [ -n "${GPG_KEY_ID:-}" ]; then
        gpg --batch --yes --pinentry-mode loopback \
            ${GPG_PASSPHRASE_FILE:+--passphrase-file "${GPG_PASSPHRASE_FILE}"} \
            --default-key "${GPG_KEY_ID}" --digest-algo SHA256 \
            --clearsign -o "${PUB}/dists/${suite}/InRelease" "${PUB}/dists/${suite}/Release"
        gpgv --keyring "${PWD}/keyring/mixtile-archive-keyring.gpg" \
            "${PUB}/dists/${suite}/InRelease" > /dev/null 2>&1 ||
            { echo "Error: InRelease does not verify against keyring/"; exit 1; }
        echo "    signed and verified against keyring/"
    else
        echo "    (unsigned: GPG_KEY_ID not set)"
    fi
done

# The public key, served next to the packages it verifies, for anyone adding
# the archive by hand. Images get the same file from the Mixtile BSP.
cp keyring/mixtile-archive-keyring.gpg "${PUB}/"

du -sh "${PUB}" | awk '{print "==> public/ " $1}'
