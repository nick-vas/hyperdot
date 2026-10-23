The failing test is `test_snuffed_enemies_leave_their_embers` in `test/unit/test_world.gd`, line 50:
`assert_eq(world.embers, 10)`. It expected 10 embers (three brutes worth 3 and a shade worth 1, each snuffed with one
blow) and got 20: every snuffed enemy's embers are counted twice.

The game is wrong, not the test. In `scripts/world.gd`, `_swing()` adds `target.embers` to `embers` when a blow leaves
the enemy with no hp, and then calls `_snuff(target)`, which adds the same enemy's embers again. The line in `_swing`
should go; `_snuff` is where an enemy's embers are counted.
