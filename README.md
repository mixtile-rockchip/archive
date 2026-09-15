# Mixtile apt archive

Rockchip userspace packages for Mixtile boards, arm64, published to GitHub
Pages at <https://mixtile-rockchip.github.io/archive>.

Images for Mixtile boards install from here rather than carrying these
packages. To add it to a board by hand:

```sh
curl -fsSL https://mixtile-rockchip.github.io/archive/mixtile-archive-keyring.gpg \
  | sudo tee /usr/share/keyrings/mixtile-archive-keyring.gpg > /dev/null

sudo tee /etc/apt/sources.list.d/mixtile.sources <<EOF
Types: deb
URIs: https://mixtile-rockchip.github.io/archive
Suites: $(. /etc/os-release; echo "$VERSION_CODENAME")
Components: main
Architectures: arm64
Signed-By: /usr/share/keyrings/mixtile-archive-keyring.gpg
EOF

sudo apt update
```

The archive is arm64. A package built `Architecture: all` is listed in the
arm64 index, which is how a Debian archive carries an architecture-independent
package.

## What a package looks like

A directory under `packages/` is a `debian/` overlay plus an optional upstream
pin. What the overlay holds depends on what upstream provides:

| upstream | the directory holds |
|---|---|
| a complete `debian/` | `pin`, plus only the files we override: `debian/changelog` in every case, `debian/control` for `librga`, `build.env` for `mpp` |
| no `debian/` | `pin`, a full `debian/` that we maintain |
| nothing -- our own package | sources and a full `debian/`, no `pin` (`rockchip-multimedia-config`) |

`pin` records where the source comes from:

    REPO=https://github.com/mixtile-rockchip/mixtile-sdk-rk-mpp.git
    BRANCH=linux-6.1-stan-rkr7
    REV=958803d74e4b53a56fedc1104408bf32a71e22c8

The build fetches `REV` from `REPO`. `BRANCH` is recorded alongside them and is
not read by the build.

The version lives in `debian/changelog`, written by hand and committed, so a
version change is a reviewable diff. The build appends `~<suite>` to it and
nothing else: that suffix is a build coordinate, not a decision, and it is what
keeps the same upstream version distinct when it is built for two suites.

    mpp (1.5.0-1+rkr7.20260226.958803d) -> 1.5.0-1+rkr7.20260226.958803d~resolute
         └──┬──┘ └┬─┘ └──┬───┘ └──┬──┘
            │     │      │        └ short commit
            │     │      └ commit date
            │     └ SDK baseline the source comes from
            └ version from the source's own debian/changelog

## Adding a package

Create the directory under `packages/`. Every directory there is built for
every line in `suites`; nothing else needs editing.

That holds even when the new package build-depends on one already here --
`gstreamer1.0-rockchip` needs `librockchip-mpp-dev` and `librga-dev`, which no
distro ships. The build order is derived rather than declared:
`debian/control` already says what a package produces and what it needs, so
`scripts/build-order.sh` reads those two fields and puts a package after any
whose binary packages its `Build-Depends` names.

    mpp                    produces librockchip-mpp-dev ...
    librga                 produces librga-dev ...
    gstreamer1.0-rockchip  Build-Depends: ... librockchip-mpp-dev librga-dev

    -> mpp, librga, then gstreamer1.0-rockchip

Each suite is one CI job that builds its packages in that order, offering the
debs it has already produced to the next container as a local apt repo. Only
this run's debs, never the published archive: a commit that moves `mpp` and
rebuilds `gstreamer1.0-rockchip` has to link the new one against the new mpp.

## Signing

The archive is signed with a key whose public half is in `keyring/` and is also
shipped in the Mixtile BSP, so images trust it out of the box. The private half
and its passphrase are repository secrets, which means write access to this
repository is the same thing as the ability to sign packages that Mixtile
boards will install as root. Protect the branch accordingly.
