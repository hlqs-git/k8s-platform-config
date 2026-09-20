#!/usr/bin/env bash
set -euo pipefail

data_path="${LONGHORN_DATA_PATH:-/var/lib/longhorn}"
failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

for package in open-iscsi nfs-common cryptsetup dmsetup; do
  if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q 'install ok installed'; then
    pass "package ${package} is installed"
  else
    fail "package ${package} is not installed"
  fi
done

if systemctl is-active --quiet iscsid; then
  pass 'iscsid is active'
else
  fail 'iscsid is not active'
fi

if mountpoint --quiet "${data_path}"; then
  data_source="$(findmnt --noheadings --output SOURCE --target "${data_path}" | xargs)"
  data_fstype="$(findmnt --noheadings --output FSTYPE --target "${data_path}" | xargs)"
  root_source="$(findmnt --noheadings --output SOURCE --target / | xargs)"
  pass "${data_path} is mounted from ${data_source} (${data_fstype})"
  if [ "${data_source}" = "${root_source}" ]; then
    fail "${data_path} uses the root filesystem instead of a dedicated disk"
  else
    pass "${data_path} uses a dedicated filesystem"
  fi
else
  fail "${data_path} is not a mount point"
fi

if grep -qw dm_crypt /proc/modules; then
  pass 'dm_crypt kernel module is loaded'
else
  fail 'dm_crypt kernel module is not loaded'
fi

if pgrep -x multipathd >/dev/null; then
  fail 'multipathd is running; disable it when unused or configure a Longhorn-safe blacklist'
else
  pass 'multipathd is not running'
fi

if [ "${failures}" -ne 0 ]; then
  printf 'Longhorn node preflight failed: %s check(s).\n' "${failures}" >&2
  exit 1
fi

printf 'Longhorn node preflight passed.\n'
