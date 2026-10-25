#!/bin/bash
# usage: milestone-ref.sh <from-stage> <to-stage> <out-dir>: every file of the later stage the earlier lacks or has otherwise
set -e
export TMPDIR=/dev/shm/racing
S=/home/user/wt-racing/benchmark/games/racing/scratch
pwsh -NoProfile -File $S/build-stage.ps1 $1 /dev/shm/racing/ms-from >/dev/null
pwsh -NoProfile -File $S/build-stage.ps1 $2 /dev/shm/racing/ms-to >/dev/null
rm -rf "$3"; mkdir -p "$3"
cd /dev/shm/racing/ms-to
find . -type f -not -path './addons/*' -not -path './.godot/*' -not -name '*.uid' -not -name '*.import' -not -name '*.translation' -not -path './test-results/*' | while read f; do
  if ! cmp -s "$f" "/dev/shm/racing/ms-from/$f"; then mkdir -p "$3/$(dirname "$f")"; cp "$f" "$3/$f"; fi
done
cd /dev/shm/racing/ms-from
find . -type f -not -path './addons/*' -not -path './.godot/*' -not -name '*.uid' -not -name '*.import' -not -name '*.translation' | while read f; do [ -e "/dev/shm/racing/ms-to/$f" ] || echo "only in $1: $f"; done
rm -rf /dev/shm/racing/ms-from /dev/shm/racing/ms-to
