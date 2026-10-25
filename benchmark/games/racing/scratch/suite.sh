#!/bin/bash
# usage: suite.sh <project> [runners]
export PATH="/usr/bin:$PATH"; unset GODOT_VERSION; export GODOT_BIN=/root/.hyperdot/4.7.2-stable-standard/Godot_v4.7.2-stable_linux.x86_64
R=""; [ -n "$2" ] && R="-Runners $2"
pwsh -NoProfile -File /home/user/wt-racing/ci/godot/hyperdot.ps1 test -Json -Quiet -Project "$1" -Results /dev/shm/racing/res-$$ $R 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('OK' if d.get('ok') else 'FAILED', d.get('error') or '')
for r in d.get('runnerResults',[]):
    print(' ', r['runner'], r.get('ok'), r.get('passed'), r.get('failed'))
    for f in r.get('failures',[]): print('     ', f.get('name'), '|', str(f.get('message'))[:600])
"
rm -rf /dev/shm/racing/res-$$
