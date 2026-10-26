The failing test is `Snuffed_enemies_leave_their_embers` in `test/WorldTest.cs`, line 49:
`AssertThat(world.Embers).IsEqual(10)`. It expected 10 embers (three brutes worth 3 and a shade worth 1, each snuffed
with one blow) and got 20: every snuffed enemy's embers are counted twice.

The game is wrong, not the test. In `scripts/World.cs`, `Swing()` adds `target.Embers` to `Embers` when a blow leaves
the enemy with no hp, and then calls `Snuff(target)`, which adds the same enemy's embers again. The line in `Swing`
should go; `Snuff` is where an enemy's embers are counted.
