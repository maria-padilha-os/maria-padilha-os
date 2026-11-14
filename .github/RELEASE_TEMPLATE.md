# Maria Padilha OS {{VERSION}}

Released {{DATE}}.

## Summary

<!-- One short paragraph for users: what changed and who should upgrade. -->

## Changes

<!-- Move the matching version section from CHANGELOG.md here. Keep breaking
changes, installer changes and known issues explicit. -->

See the [changelog](https://github.com/maria-padilha-os/maria-padilha-os/blob/main/CHANGELOG.md)
for the full list.

## Assets

- `{{ISO}}`
- `SHA256SUMS`
- `SHA256SUMS.asc` — {{SIGNATURE}}

SHA256 of the ISO:

```text
{{SHA256}}  {{ISO}}
```

## Verification

```sh
sha256sum -c SHA256SUMS
gpg --verify SHA256SUMS.asc SHA256SUMS
```

Compare the signing key fingerprint with the maintainer fingerprint published
outside this release before trusting the signature.

## Installation and upgrade

<!-- Link the current install/upgrade notes, or say "no installer changes". -->

## Rollback

If this image is withdrawn, the previous signed ISO remains the rollback
target. Do not rewrite a published tag or silently replace its assets; mark
this release as withdrawn and restore the previous release as latest. See
[docs/release-checklist.md](https://github.com/maria-padilha-os/maria-padilha-os/blob/main/docs/release-checklist.md#rollback-to-the-previous-iso).

## Known issues

<!-- List known issues, or "None known for this image." -->
