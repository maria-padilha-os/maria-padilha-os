# Calamares integration

This directory contains build-time inputs for the Calamares layer.  The
installer itself lives in `iso/airootfs/etc/calamares/` so it is copied into
the live root by archiso.

## Live root packages

Append `live-packages.x86_64` to the archiso package list when the profile is
present:

```sh
cat iso/calamares/live-packages.x86_64 >> iso/packages.x86_64
```

That adds `calamares` only.  The installer's runtime dependencies are pulled by
pacman during the ISO build; nothing is installed into the target just because
it is in the live root.

## Offline target repository

The target packages are archives, not a package list that is fetched at install
time.  Build them on the Arch build host (network is allowed during the build,
not during installation):

```sh
# from the repository root, inside the archiso build container
scripts/calamares-offline-repo.sh --package-dir out/repo
```

The helper:

1. copies any archives from `--package-dir` (for example the locally built
   `maria-padilha` package in `out/repo`),
2. downloads the packages and dependencies named in
   `offline-packages.x86_64` into a scratch cache,
3. runs `repo-add` to write
   `iso/airootfs/var/cache/calamares/offline-repo/maria-padilha-offline.db.tar.gz`.

Run it before `mkarchiso`; the archives then become part of `airootfs.sfs`.
At install time `modules/shellprocess.conf` links that database into the target
and adds:

```ini
[maria-padilha-offline]
SigLevel = Optional DatabaseOptional
Server = file:///var/cache/calamares/offline-repo
```

`modules/packages.conf` sets `update_db: false` and `update_system: false`, so
no mirror is contacted.  The target keeps the local repository for later
offline package installs.
