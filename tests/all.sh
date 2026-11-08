#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
fail=0
if [ ! -s README.md ]; then echo "FAIL README.md missing"; fail=1; else echo "ok README.md"; fi
if git grep -nE 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' -- . >/tmp/secret-scan.$$ 2>/dev/null; then
  echo "FAIL possible tracked secret"; cat /tmp/secret-scan.$$; fail=1
else
  echo "ok no obvious tracked secret"
fi
rm -f /tmp/secret-scan.$$
if bash tests/iso.sh; then
  echo "ok tests/iso.sh"
else
  echo "FAIL tests/iso.sh"
  fail=1
fi
if bash tests/calamares.sh; then
  echo "ok tests/calamares.sh"
else
  echo "FAIL tests/calamares.sh"
  fail=1
fi
if bash tests/skel.sh; then
  echo "ok tests/skel.sh"
else
  echo "FAIL tests/skel.sh"
  fail=1
fi
if bash tests/first-boot.sh --profile; then
  echo "ok tests/first-boot.sh --profile"
else
  echo "FAIL tests/first-boot.sh --profile"
  fail=1
fi
if bash tests/hardware.sh; then
  echo "ok tests/hardware.sh"
else
  echo "FAIL tests/hardware.sh"
  fail=1
fi
[ "$fail" -eq 0 ]
