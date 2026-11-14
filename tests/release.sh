#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Checks for the local release tooling, checksum generation, argument
# validation, signing wiring and the manual release/rollback documentation.
# These checks never build an ISO, start a container, call GPG for real, or
# touch the network.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail=0
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

require_file() {
    if [[ -s "$1" ]]; then ok "$1"; else bad "$1 missing or empty"; fi
}

require_exec() {
    if [[ -x "$1" ]]; then ok "$1 executable"; else bad "$1 is not executable"; fi
}

release="tools/release.sh"
checklist="docs/release-checklist.md"
template=".github/RELEASE_TEMPLATE.md"

for file in "$release" "$checklist" "$template" CHANGELOG.md; do
    require_file "$file"
done
require_exec "$release"

if bash -n "$release" 2>/dev/null; then
    ok "$release syntax"
else
    bad "$release has a bash syntax error"
fi

# The release script stages files only. Publication is a manual checklist step.
if grep -nE 'gh release|gh api|git tag|git push|curl|wget|actions/upload|deploy-pages|github-pages' "$release"; then
    bad "$release contains a publish/network command"
else
    ok "$release does not upload, tag or publish"
fi
if grep -vE '^[[:space:]]*#' "$release" |
    grep -nE '(^|[^[:alnum:]_])(sudo|pkexec)[[:space:]]'; then
    bad "$release appears to invoke a privileged host command"
else
    ok "$release does not invoke sudo/pkexec"
fi
if grep -qF 'scripts/ci/build-iso.sh' "$release" &&
    grep -qF 'sha256sum' "$release" &&
    grep -qF 'gpg' "$release" &&
    grep -qF 'SHA256SUMS' "$release"; then
    ok "release script wires the build, checksum and optional signature paths"
else
    bad "release script is missing build/checksum/sign wiring"
fi

if grep -qF '{{VERSION}}' "$template" &&
    grep -qF '{{ISO}}' "$template" &&
    grep -qF '{{SHA256}}' "$template" &&
    grep -qF '{{SIGNATURE}}' "$template"; then
    ok "GitHub release template has version, asset, checksum and signature fields"
else
    bad "GitHub release template is missing required placeholders"
fi
if grep -Eqi 'version' "$checklist" &&
    grep -Eqi 'changelog' "$checklist" &&
    grep -qF 'sha256sum -c SHA256SUMS' "$checklist" &&
    grep -Eqi 'rollback' "$checklist" &&
    grep -Eqi 'previous ISO' "$checklist" &&
    grep -Eqi 'draft' "$checklist" &&
    grep -Eqi 'manual' "$checklist"; then
    ok "release checklist covers version, changelog, checksum, rollback and manual draft"
else
    bad "release checklist is missing a required release step"
fi
if grep -Eqi 'action-gh-release|softprops|upload-release|gh release|deploy-pages|github-pages' .github/workflows/*.yml; then
    bad "a workflow can publish a release or Pages automatically"
else
    ok "no workflow publishes a release or Pages automatically"
fi

# --help must work without building, GPG or a container.
if help="$(bash "$release" --help 2>&1)" &&
    grep -qF 'usage:' <<<"$help" &&
    grep -qF 'SHA256SUMS' <<<"$help"; then
    ok "--help describes the release flow"
else
    bad "--help failed or is incomplete"
fi

expect_fail() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        bad "$description unexpectedly succeeded"
    else
        ok "$description rejected"
    fi
}

expect_fail "unknown option" bash "$release" --definitely-not-an-option
expect_fail "missing --iso value" bash "$release" --iso
expect_fail "missing --out value" bash "$release" --out
expect_fail "missing --sign-key value" bash "$release" --sign-key
expect_fail "invalid version" bash "$release" --version not-a-version
expect_fail "version not matching the pin" bash "$release" --version 999.999.999
expect_fail "--iso with --from-out" bash "$release" --iso /nonexistent.iso --from-out
expect_fail "--iso with --build" bash "$release" --iso /nonexistent.iso --build
expect_fail "--sign-key with --no-sign" bash "$release" --sign-key test-key --no-sign
expect_fail "--sign without a configured key" \
    env -u MARIA_PADILHA_GPG_KEY bash "$release" --sign

mkdir -p "$root/.scratch"
scratch="$(mktemp -d "$root/.scratch/release-test.XXXXXX")"
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT
expect_fail "missing ISO file" \
    bash "$release" --no-sign --iso "$scratch/does-not-exist.iso" \
    --out "$scratch/does-not-exist-release"

version="$(tr -d '[:space:]' < iso/package-version)"
iso="$scratch/maria-padilha-$version-x86_64.iso"
printf 'Maria Padilha release fixture\n' >"$iso"
expected_hash="$(sha256sum -- "$iso" | awk '{ print $1 }')"
iso_name="$(basename -- "$iso")"

release_dir="$scratch/release"
if bash "$release" --iso "$iso" --out "$release_dir" --no-sign >"$scratch/release.log" 2>&1; then
    ok "unsigned release staging"
else
    bad "unsigned release staging failed"
    cat "$scratch/release.log"
fi

if [[ -f "$release_dir/SHA256SUMS" ]]; then
    ok "SHA256SUMS generated"
else
    bad "SHA256SUMS was not generated"
fi
if [[ -f "$release_dir/SHA256SUMS" ]] &&
    [[ "$(cat "$release_dir/SHA256SUMS")" == "$expected_hash  $iso_name" ]]; then
    ok "SHA256SUMS has the expected hash and filename"
else
    bad "SHA256SUMS content is wrong"
fi
if (cd "$release_dir" && sha256sum -c --strict SHA256SUMS >/dev/null 2>&1); then
    ok "generated SHA256SUMS verifies"
else
    bad "generated SHA256SUMS does not verify"
fi
if cmp -s "$iso" "$release_dir/$iso_name"; then
    ok "ISO copied into the release directory"
else
    bad "ISO was not copied into the release directory"
fi
if [[ ! -e "$release_dir/SHA256SUMS.asc" ]]; then
    ok "unsigned release has no signature file"
else
    bad "unsigned release unexpectedly has SHA256SUMS.asc"
fi
if [[ -f "$release_dir/release-notes.md" ]] &&
    grep -qF "$version" "$release_dir/release-notes.md"; then
    ok "draft release notes rendered from the template"
else
    bad "draft release notes were not rendered"
fi
if grep -qF 'NOT published' "$scratch/release.log"; then
    ok "release script states that nothing was published"
else
    bad "release script does not make the no-publication boundary explicit"
fi

if bash "$release" --iso "$iso" --out "$release_dir" --no-sign >/dev/null 2>&1; then
    bad "reusing a non-empty release directory without --force was allowed"
else
    ok "non-empty release directory requires --force"
fi
if bash "$release" --iso "$iso" --out "$release_dir" --no-sign --force >/dev/null 2>&1 &&
    (cd "$release_dir" && sha256sum -c --strict SHA256SUMS >/dev/null 2>&1); then
    ok "--force replaces the checksum safely"
else
    bad "--force release replacement failed"
fi

# Exercise the optional signing path with a stub gpg. The stub records the
# arguments and creates the detached-signature output; no real key is used.
mkdir -p "$scratch/bin"
cat >"$scratch/bin/gpg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_GPG_LOG:-}" ]]; then
    printf '%s\n' "$*" >>"$FAKE_GPG_LOG"
fi
output=""
previous=""
for argument in "$@"; do
    if [[ "$previous" == "--output" ]]; then
        output="$argument"
    fi
    previous="$argument"
done
if [[ -n "$output" ]]; then
    printf 'stub detached signature\n' >"$output"
fi
exit 0
EOF
chmod +x "$scratch/bin/gpg"

signed_dir="$scratch/signed"
if PATH="$scratch/bin:$PATH" FAKE_GPG_LOG="$scratch/gpg.log" \
    bash "$release" --iso "$iso" --out "$signed_dir" --sign-key release-test \
    >"$scratch/signed.log" 2>&1; then
    ok "signed release staging with a configured key"
else
    bad "signed release staging failed"
    cat "$scratch/signed.log"
fi
if [[ -f "$signed_dir/SHA256SUMS.asc" ]] &&
    grep -qF -- '--detach-sign' "$scratch/gpg.log"; then
    ok "configured key invokes detached GPG signing"
else
    bad "signing path did not create SHA256SUMS.asc"
fi
if grep -qF 'Signed:' "$signed_dir/release-notes.md" 2>/dev/null; then
    ok "signed release notes record the signature"
else
    bad "signed release notes do not record the signature"
fi

if MARIA_PADILHA_GPG_KEY=release-test PATH="$scratch/bin:$PATH" \
    bash "$release" --iso "$iso" --out "$scratch/env-nosign" --no-sign \
    >/dev/null 2>&1 &&
    [[ ! -e "$scratch/env-nosign/SHA256SUMS.asc" ]]; then
    ok "--no-sign overrides a configured key"
else
    bad "--no-sign did not override the configured key"
fi

if grep -qF 'tests/release.sh' tests/all.sh; then
    ok "tests/all.sh runs tests/release.sh"
else
    bad "tests/all.sh does not run tests/release.sh"
fi

if ((fail)); then
    printf '\nrelease validation failed\n' >&2
    exit 1
fi
printf '\nrelease validation passed\n'
