# Mixtile apt archive

Rockchip userspace packages for Mixtile boards, arm64, published to GitHub
Pages at <https://mixtile-rockchip.github.io/archive>.

Images built by [mixtile-os](https://github.com/mixtile-rockchip) install from
here rather than carrying these packages. To add it to a board by hand:

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

## What a package looks like

A directory under `packages/` is a `debian/` overlay plus an optional upstream
pin. Three shapes, depending on what upstream provides:

| upstream | the directory holds |
|---|---|
| a complete `debian/` | `pin`, `debian/changelog` (ours only), `build.env` |
| no `debian/` | `pin`, a full `debian/` that we maintain |
| nothing -- our own package | sources and a full `debian/`, no `pin` |

The version lives in `debian/changelog`, written by hand and committed, so a
version change is a reviewable diff. The build appends `~<suite>` to it and
nothing else: that suffix is a build coordinate, not a decision, and it is what
keeps the same upstream version distinct when it is built for two suites.

    mpp (1.5.0-1+rkr7.20260226.958803d) -> 1.5.0-1+rkr7.20260226.958803d~resolute
        └────┬───┘ └─┬─┘ └───┬────┘ └─┬──┘
             │       │       │        └ short commit
             │       │       └ commit date
             │       └ SDK baseline the source comes from
             └ version from the source's own debian/changelog

The baseline is in the version because the kernel and the userspace do not
share one -- the kernel is built from rkr5.1 and these come from rkr7 -- and a
board should report that rather than have it flattened into a tidy number.

## Adding a package

Create the directory under `packages/`. The build matrix is every directory
there crossed with every line in `suites`; nothing else needs editing.

## Signing

The archive is signed with a key whose public half is in `keyring/` and is also
shipped in the Mixtile BSP, so images trust it out of the box. The private half
and its passphrase are repository secrets, which means write access to this
repository is the same thing as the ability to sign packages that Mixtile
boards will install as root. Protect the branch accordingly.
