#!/bin/bash
# usage: tgp.sh <out-file> [args for Test-GameProgramme]
export TMPDIR=/dev/shm/racing PATH="/usr/bin:$PATH"; unset GODOT_VERSION; export GODOT_BIN=/root/.hyperdot/4.7.2-stable-standard/Godot_v4.7.2-stable_linux.x86_64
out=$1; shift
cd /home/user/wt-racing && pwsh -NoProfile -File tests/Test-GameProgramme.ps1 -Genre racing -Language gdscript "$@" > $out 2>&1
echo "EXIT $?" >> $out
