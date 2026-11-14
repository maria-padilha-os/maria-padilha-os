# Release checklist

This is the human gate for every Maria Padilha OS ISO. The release tooling
only stages artifacts under `out/release/<version>/`. It does not tag, upload,
publish a GitHub release or deploy GitHub Pages. Those are separate, reviewed
human actions.

The release candidate must come from a reviewed commit. Keep the previous
release directory and its GitHub assets until the new one has been verified.

## 0. Preconditions

- [ ] The branch is reviewed and the working tree is clean
      (`git status --short` is empty).
- [ ] The sibling `maria-padilha-de` checkout contains the matching
      `packaging/PKGBUILD`; the dotfiles checkout is at the intended ref.
- [ ] Docker or Podman is available. Do **not** run `tools/release.sh` or
      `build.sh` with host root; both use a throw-away privileged container for
      `mkarchiso`.
- [ ] The previous release directory (for example
      `out/release/<previous-version>/`) is present and verifies.
- [ ] If signing: the maintainer GPG secret key is available in the local
      keyring and the expected fingerprint has been confirmed out of band.
- [ ] A human reviewer is available for the GitHub draft.

## 1. Bump the version

- [ ] Update `pkgver`/`pkgrel` in `maria-padilha-de/packaging/PKGBUILD`.
- [ ] Update `iso/package-version` to the same `pkgver`.
- [ ] Update the version references in `iso/profiledef.sh` and
      `iso/airootfs/etc/maria-padilha-release`
      (`VERSION` and `PACKAGE_VERSION`).
- [ ] Update the current-version text in `README.md` and, when the pinned
      desktop source changes, the `DE_REF`/`vX.Y.Z` defaults in
      `.github/workflows/iso.yml` and `docs/ci.md`.
- [ ] Run `bash tests/all.sh` and `git diff --check`.

The version pin and the PKGBUILD must agree; `tests/iso.sh` fails when the
sibling checkout is present and they differ.

## 2. Update the changelog

- [ ] In `CHANGELOG.md`, move the `Unreleased` entries under a new
      `## [X.Y.Z] - YYYY-MM-DD` heading.
- [ ] Leave a fresh `## [Unreleased]` section at the top.
- [ ] Describe breaking changes, installer/boot changes, known issues and
      anything users must do before upgrading.
- [ ] Review the entries against the actual commits; do not claim a feature or
      a test run that did not happen.

## 3. Build, checksum and optionally sign

Use the release version from `iso/package-version`:

```sh
export MARIA_PADILHA_DE=/path/to/maria-padilha-de
export MARIA_PADILHA_DOTFILES=/path/to/maria-padilha-dotfiles

# optional: sign SHA256SUMS with the maintainer key
export MARIA_PADILHA_GPG_KEY='FINGERPRINT_OR_KEY_ID'

tools/release.sh --version 0.2.0
```

`tools/release.sh` calls `scripts/ci/build-iso.sh`, which starts the Arch
container. It writes the ISO, `SHA256SUMS`, an optional `SHA256SUMS.asc`,
`build-info.txt` (when available) and `release-notes.md` under
`out/release/0.2.0/`. It verifies the new checksum and signature before
replacing anything.

To stage an already built ISO without rebuilding:

```sh
tools/release.sh --version 0.2.0 --from-out
tools/release.sh --version 0.2.0 --iso /path/to/maria-padilha-0.2.0-x86_64.iso
```

Use `--no-sign` only when a signed release is explicitly not required.
`--force` replaces known artifacts in the same version directory; never point
it at the previous version's directory.

- [ ] The build finished without warnings that affect the release.
- [ ] The ISO filename is `maria-padilha-X.Y.Z-x86_64.iso`.
- [ ] `out/release/X.Y.Z/SHA256SUMS` exists.
- [ ] When signing is required, `out/release/X.Y.Z/SHA256SUMS.asc` exists.

## 4. Verify the artifacts

Run the checks from the release directory, ideally after copying it to a
different machine or a fresh directory:

```sh
cd out/release/0.2.0
sha256sum -c SHA256SUMS
gpg --verify SHA256SUMS.asc SHA256SUMS
gpg --fingerprint FINGERPRINT_OR_KEY_ID
```

- [ ] `sha256sum -c SHA256SUMS` reports `OK` for the ISO.
- [ ] The detached signature verifies against `SHA256SUMS`.
- [ ] The signing fingerprint matches the published maintainer fingerprint.
- [ ] `SHA256SUMS` contains only the release ISO and the filename matches the
      actual asset.
- [ ] The ISO size is plausible (the CI wrapper's default ceiling is 9 GiB).
- [ ] A headless boot check or the relevant QEMU checklist has been run on
      this exact ISO; record the result in the release notes.

## 5. Create the GitHub release draft (manual only)

No workflow performs this step. A human must review the notes, tag and draft.
Use `.github/RELEASE_TEMPLATE.md` as the body; `tools/release.sh` renders a
starting copy at `out/release/X.Y.Z/release-notes.md`.

- [ ] Fill in the summary, changes, known issues and verification result in
      `release-notes.md`.
- [ ] Create a signed tag only after the candidate is approved:

      ```sh
      git tag -s vX.Y.Z -m 'Maria Padilha OS X.Y.Z'
      git push origin vX.Y.Z
      ```

- [ ] Create a **draft** release manually, for example:

      ```sh
      gh release create vX.Y.Z --draft \
        --title 'Maria Padilha OS X.Y.Z' \
        --notes-file out/release/X.Y.Z/release-notes.md \
        out/release/X.Y.Z/maria-padilha-X.Y.Z-x86_64.iso \
        out/release/X.Y.Z/SHA256SUMS \
        out/release/X.Y.Z/SHA256SUMS.asc
      ```

      The GitHub web UI (**Draft a new release**) is equivalent. There is no
      automatic upload, tag or Pages publication.
- [ ] Download the draft assets once and verify them again before publishing.
- [ ] Keep the release as a draft until a second person signs off.
- [ ] Publish, then set the release as latest, only with explicit human
      approval. Do not enable Pages deployment for release assets.

## Rollback to the previous ISO

Rollback is a deliberate manual operation. Never rewrite or force-push a
published tag, and never silently replace a published asset with a different
file.

If the new ISO is bad **before publication**:

- [ ] Delete the draft release and its uploaded assets (the tag may remain if
      it was already pushed; do not move it).
- [ ] Fix the problem, bump `pkgrel` or the patch version, and restart this
      checklist. Keep the failed build directory for diagnosis.

If the new ISO is bad **after publication**:

1. Stop promotion and announce the withdrawal with the affected version and
   checksums.
2. Mark the bad release as withdrawn (edit the notes) and, if appropriate,
   make it a pre-release so it is not offered as latest.
3. Restore the previous verified release as latest:

   ```sh
   gh release edit vPREVIOUS --latest
   ```

4. Verify the previous artifacts before advertising them again:

   ```sh
   cd out/release/PREVIOUS
   sha256sum -c SHA256SUMS
   gpg --verify SHA256SUMS.asc SHA256SUMS
   ```

5. If the previous release assets are not local, download the previous ISO,
   `SHA256SUMS` and `SHA256SUMS.asc` from the previous GitHub release, place
   them in a fresh `out/release/PREVIOUS/` directory and run the same checks.
6. Restore download links, the website or any mirror to the previous ISO.
   Keep the failed ISO, its checksums and its signature available for audit;
   do not overwrite them.
7. If users already installed the bad image, document the recovery path and
   ship the fix as a new patch release. A published tag is immutable.

- [ ] The previous ISO's checksum and signature verify.
- [ ] The previous release is marked latest again.
- [ ] The bad release is clearly marked and no longer recommended.
- [ ] The rollback reason and the verified previous checksum are recorded.

## Final sign-off

- [ ] Version, changelog, ISO, checksums, signature and release notes agree.
- [ ] The artifacts were verified on a copy outside the build tree.
- [ ] A human, not CI, performed the tag/release/Pages actions.
- [ ] The previous release remains available as rollback material.
