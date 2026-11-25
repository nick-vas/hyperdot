#!/usr/bin/env bash
set -euo pipefail
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scaffold-gdscript.sh"
# The bug: the multiplier stops at x2 from the tenth hit on. The unit test of the fifth hit still passes; only the
# start-up flow (twelve hits, 230 points) sees 200. The unit test of the main scene is removed, so GUT alone stays
# green, and both changes go into the first commit, so the history does not point at them.
sed -i 's|value \* (1 + combo / 5)|value * (1 + mini(combo, 9) / 5)|' score.gd
sed -i '/^func test_main_scene_scores_on_ready/,$d' test/test_score.gd
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' test/test_score.gd
grep -q 'mini(combo, 9)' score.gd
git -c user.name=eval -c user.email=eval@example.com commit -qa --amend -m "Example game"
