# 154328106 RootHide Repo

Personal APT repository for tested Relaxin/RootHide packages.

## Source address

```text
https://154328106.github.io/repo/
```

## Add or update packages

1. Put intact `.deb` files in [`debs/`](debs/).
2. Commit and push to `main`.
3. GitHub Actions validates the packages, regenerates `Packages`, compressed
   indexes and `Release`, then deploys GitHub Pages.

Accepted package architectures are `iphoneos-arm64e` (RootHide) and `all`
(architecture-independent themes or metadata). The workflow rejects corrupt
packages and duplicate Package/Version/Architecture tuples.

Keep third-party packages unchanged and redistribute them only when their
license or author permits it. Do not mirror paid packages.

## Local generation

On Debian or Ubuntu with `dpkg-dev` and `xz-utils` installed:

```bash
./scripts/build-repo.sh
```

The generated repository is written to `public/` and is intentionally not
committed.

