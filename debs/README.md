# Package drop folder

Put approved, tested `.deb` files directly in this directory or in its
subdirectories. Commit and push; GitHub Actions will rebuild the repository.

Before uploading a package, confirm:

- it works with Relaxin/RootHide;
- its architecture is `iphoneos-arm64e` or `all`;
- its author or license permits redistribution;
- it is not a paid or account-bound package.

Do not unpack or rename package identifiers merely to make an incompatible
rootless package appear RootHide-compatible.

