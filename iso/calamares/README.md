# Calamares integration

This directory contains build-time inputs for the Calamares layer.  The
installer itself lives in `iso/airootfs/etc/calamares/` so it is copied into
the live root by archiso.

## Live root packages

`build.sh` appends `live-packages.x86_64` to the working profile's package list
while preparing the ISO, so the tracked `iso/packages.x86_64` stays free of the
live-only installer.  That adds `calamares` only.  The installer's runtime
dependencies are pulled by pacman during the ISO build; nothing is installed
into the target just because it is in the live root.

For a manual profile build outside `build.sh`, append the list yourself:

```sh
cat iso/calamares/live-packages.x86_64 >> iso/packages.x86_64
```

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
   `maria-padilha-offline.db.tar.gz` in `--output`.

`build.sh` runs the helper with the working profile's
`airootfs/var/cache/calamares/offline-repo` as `--output`, so the archives
become part of `airootfs.sfs` without modifying the tracked tree.  To stage the
repository by hand, run the command above from the repository root; it writes
to `iso/airootfs/var/cache/calamares/offline-repo/` by default.  At install
time `modules/shellprocess.conf` links that database into the target and adds:

```ini
[maria-padilha-offline]
SigLevel = Optional DatabaseOptional
Server = file:///var/cache/calamares/offline-repo
```

`modules/packages.conf` sets `update_db: false` and `update_system: false`, so
no mirror is contacted.  The target keeps the local repository for later
offline package installs.

## Software groups

`iso/airootfs/etc/calamares/modules/packagechooser.conf` defines the mandatory
`base` group and the optional `development`, `media`, `games`, `office-mail`
and `ai-tools` groups.  Office/Mail includes Thunderbird.  AI Tools includes the
local assistant runtime (Ollama and llama.cpp) but no API key, provider account
or credential; selecting any group does not configure accounts.

`build.sh` calls `scripts/calamares-offline-repo.sh` with the build's working
profile as `--output`, so the staged archives and database are copied into that
profile rather than dirtying the tracked source tree.  The manifest must cover
every package in every chooser group and every fixed operation in
`packages.conf`; `tests/calamares.sh` enforces that contract.  The base group is
also installed by fixed `packages.conf` operations and has no removal path, so
an optional selection cannot take it away.
