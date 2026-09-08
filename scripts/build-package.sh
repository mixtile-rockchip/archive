#!/bin/bash
# Builds one package for one suite:  scripts/build-package.sh mpp resolute
# Debs land in out/<suite>/.

set -eE
trap 'echo "Error: in $0 on line $LINENO"' ERR
cd "$(dirname "$0")/.."

PKG="${1:?usage: $0 <package> <suite> [--fetch-only]}"
SUITE="${2:?usage: $0 <package> <suite> [--fetch-only]}"
FETCH_ONLY=0
[ "${3:-}" = "--fetch-only" ] && FETCH_ONLY=1
DIR="packages/${PKG}"
[ -d "${DIR}" ] || { echo "Error: no ${DIR}"; exit 1; }

case "${SUITE}" in
    resolute|questing|plucky|oracular|noble|jammy) IMAGE="ubuntu:${SUITE}" ;;
    forky|trixie|bookworm)                         IMAGE="debian:${SUITE}" ;;
    *) echo "Error: unknown suite ${SUITE}"; exit 1 ;;
esac

WORK="work/${SUITE}/${PKG}"
SRC="${WORK}/src"

# The source is fetched once per REV and then reused. build-order.sh fetches
# every package to read its debian/control, and without this a tree the size
# of ffmpeg's would be cloned twice. .rev records what src/ holds; the debian/
# overlay below is re-applied every time regardless, being a copy of files
# from this repo, which is also what makes the version rewrite idempotent.
if [ -f "${DIR}/pin" ]; then
    # shellcheck source=/dev/null
    source "${DIR}/pin"
    : "${REPO:?pin has no REPO}" "${REV:?pin has no REV}"
    if [ -f "${DIR}/debian/changelog" ] && [ "$(cat "${WORK}/.rev" 2>/dev/null)" = "${REV}" ]; then
        echo "==> ${PKG}: reusing ${SRC} @ ${REV:0:12}"
    else
        # Fetch the pinned commit, not the branch tip: the branch says where to
        # look, REV is what we build. GitHub serves a sha directly, so this stays
        # a shallow fetch however far the branch has moved on.
        rm -rf "${WORK}"; mkdir -p "${SRC}"
        echo "==> ${PKG}: ${REPO##*/} @ ${REV:0:12}"
        git -C "${SRC}" init -q
        git -C "${SRC}" remote add origin "${REPO}"
        git -C "${SRC}" fetch -q --depth=1 origin "${REV}"
        git -C "${SRC}" checkout -q FETCH_HEAD
        rm -rf "${SRC}/.git"
        echo "${REV}" > "${WORK}/.rev"
    fi
else
    rm -rf "${WORK}"; mkdir -p "${SRC}"
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

# build-order.sh stops here: all it needs is src/debian/control.
[ "${FETCH_ONLY}" = 1 ] && exit 0

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

# A package here may build-depend on another one here: gstreamer1.0-rockchip
# needs librockchip-mpp-dev and librga-dev, which no distro ships. Whatever
# this suite has already built is offered to the container as a local repo, so
# the order build-order.sh derives from Build-Depends is all that is needed.
# Only this run's debs, never the published archive: a commit that moves mpp
# and rebuilds gstreamer must link the new gstreamer against the new mpp.
LOCAL=()
if compgen -G "out/${SUITE}/*.deb" > /dev/null; then
    LOCAL=(-v "${PWD}/out/${SUITE}:/deb:ro")
    echo "==> offering $(ls out/"${SUITE}"/*.deb | wc -l | tr -d ' ') already-built debs as a local repo"
fi

echo "==> building in ${IMAGE}"
# The container is root, so everything it leaves in the bind mount is root's.
# Handing it back at the end is what lets this script rm -rf its own work/ on
# a rebuild; without it a second local build of the same package fails on
# permissions, which CI never sees because every run gets a fresh runner.
docker run --rm -v "${PWD}/${WORK}:/w" -w /w/src "${LOCAL[@]}" \
    -e DEBIAN_FRONTEND=noninteractive \
    -e HOST_OWNER="$(id -u):$(id -g)" \
    "${BUILD_ENV[@]/#/--env=}" \
    "${IMAGE}" bash -euc '
        apt-get -qq update
        apt-get -qq install -y --no-install-recommends build-essential devscripts equivs dpkg-dev
        # Copied out of the read-only mount because apt wants the Packages
        # index it is told about to sit beside the debs it indexes.
        if [ -d /deb ]; then
            mkdir -p /localrepo && cp /deb/*.deb /localrepo/
            ( cd /localrepo && dpkg-scanpackages -m . > Packages 2>/dev/null )
            echo "deb [trusted=yes] file:///localrepo ./" > /etc/apt/sources.list.d/mixtile-local.list
            apt-get -qq update
        fi
        mk-build-deps -i -r -t "apt-get -y --no-install-recommends" debian/control
        rc=0
        dpkg-buildpackage -b -us -uc -j"$(nproc)" || rc=$?
        chown -R "$HOST_OWNER" /w
        exit $rc
    '

# .ddeb debug symbols are dropped on purpose: several times the size of what
# they describe, against a 1 GB budget for the whole Pages site.
mkdir -p "out/${SUITE}"
mv "${WORK}"/*.deb "out/${SUITE}/"
rm -f "${WORK}"/*.ddeb "${WORK}"/*.buildinfo "${WORK}"/*.changes
ls -la "out/${SUITE}"/*.deb | awk '{printf "==> %-64s %7.1f KB\n", $9, $5/1024}'
