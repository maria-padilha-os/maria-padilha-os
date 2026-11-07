# Offline package repository

This directory is the target-side copy of the ISO's local pacman repository.
It is unpacked from `airootfs.sfs` together with the rest of the live root.

The build stages package archives and the `maria-padilha-offline.db.tar.gz`
database here with `scripts/calamares-offline-repo.sh`.  Archives, databases
and signatures are build artifacts and are ignored by git; only this README
and the directory's `.gitignore` are tracked.

Keep `iso/calamares/offline-packages.x86_64` and the operations in
`iso/airootfs/etc/calamares/modules/packages.conf` in sync.  If a package is
selected by `packagechooser.conf`, it must be listed in the manifest too.
