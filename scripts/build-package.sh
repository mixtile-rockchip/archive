#!/bin/bash
# Builds one package for one suite:  scripts/build-package.sh mpp resolute
# Debs land in out/<suite>/.

set -eE
trap 'echo "Error: in $0 on line $LINENO"' ERR
cd "$(dirname "$0")/.."

PKG="${1:?usage: $0 <package> <suite>}"
SUITE="${2:?usage: $0 <package> <suite>}"
DIR="packages/${PKG}"
[ -d "${DIR}" ] || { echo "Error: no ${DIR}"; exit 1; }

case "${SUITE}" in
    resolute|questing|plucky|oracular|noble|jammy) IMAGE="ubuntu:${SUITE}" ;;
    forky|trixie|bookworm)                         IMAGE="debian:${SUITE}" ;;
    *) echo "Error: unknown suite ${SUITE}"; exit 1 ;;
esac

WORK="work/${SUITE}/${PKG}"
SRC="${WORK}/src"
rm -rf "${WORK}"; mkdir -p "${SRC}"

if [ -f "${DIR}/pin" ]; then
    # shellcheck source=/dev/null
    source "${DIR}/pin"
    : "${REPO:?pin has no REPO}" "${REV:?pin has no REV}"
    # Fetch the pinned commit, not the branch tip: the branch says where to
    # look, REV is what we build. GitHub serves a sha directly, so this stays
    # a shallow fetch however far the branch has moved on.
    echo "==> ${PKG}: ${REPO##*/} @ ${REV:0:12}"
    git -C "${SRC}" init -q
    git -C "${SRC}" remote add origin "${REPO}"
    git -C "${SRC}" fetch -q --depth=1 origin "${REV}"
    git -C "${SRC}" checkout -q FETCH_HEAD
    rm -rf "${SRC}/.git"
else
    echo "==> ${PKG}: ours, no upstream"
    cp -r "${DIR}"/. "${SRC}/"
    rm -f "${SRC}/pin" "${SRC}/build.env"
fi

# Our debian/ is laid over whatever upstream ships. For a source that carries
# its own packaging that is just the changelog; for one that carries none it is
# the whole thing.
if [ -d "${DIR}/debian" ] && [ -f "${DIR}/pin" ]; then
    mkdir -p "${SRC}/debian"
    cp -r "${DIR}/debian"/. "${SRC}/debian/"
fi
[ -f "${SRC}/debian/changelog" ] || { echo "Error: ${PKG} ended up with no debian/changelog"; exit 1; }

# The committed version is suite-independent; ~<suite> is appended here so the
# same upstream version stays distinct when built for more than one suite. The
# distribution field has to match the suite or dpkg-buildpackage complains.
VERSION="$(sed -n '1s/.*(\(.*\)).*/\1/p' "${SRC}/debian/changelog")~${SUITE}"
sed -i "1s/(\(.*\))\(.*\);/(${VERSION})\2;/; 1s/) [A-Za-z-]* *;/) ${SUITE};/" "${SRC}/debian/changelog"
echo "==> version ${VERSION}"

BUILD_ENV=()
if [ -f "${DIR}/build.env" ]; then
    while IFS= read -r line; do
        case "${line}" in ''|'#'*) continue ;; esac
        BUILD_ENV+=("${line}")
    done < "${DIR}/build.env"
fi

echo "==> building in ${IMAGE}"
docker run --rm -v "${PWD}/${WORK}:/w" -w /w/src \
    -e DEBIAN_FRONTEND=noninteractive \
    "${BUILD_ENV[@]/#/--env=}" \
    "${IMAGE}" bash -euc '
        apt-get -qq update
        apt-get -qq install -y --no-install-recommends build-essential devscripts equivs dpkg-dev
        mk-build-deps -i -r -t "apt-get -y --no-install-recommends" debian/control
        dpkg-buildpackage -b -us -uc -j"$(nproc)"
    '

# .ddeb debug symbols are dropped on purpose: several times the size of what
# they describe, against a 1 GB budget for the whole Pages site.
mkdir -p "out/${SUITE}"
mv "${WORK}"/*.deb "out/${SUITE}/"
rm -f "${WORK}"/*.ddeb "${WORK}"/*.buildinfo "${WORK}"/*.changes
ls -la "out/${SUITE}"/*.deb | awk '{printf "==> %-64s %7.1f KB\n", $9, $5/1024}'
