The failing test is `Flare_burns_the_rival_for_three` in `test/DuelTest.cs`, at line 25
(`AssertThat(duel.Keepers[1].Light).IsEqual(17)`): it expected the rival's light to be 17 after one Flare and got 14.

The game is wrong, not the test. Flare is a rite of 3 (`data/cards.json`: effect bolt, amount 3), so the rival should
go from 20 to 17. In `Duel.Resolve` (`scripts/Duel.cs`) the "bolt" case calls `Burn(1 - seat, amount)` twice, so the
effect is applied twice and burns 6. The other rites resolve once and their tests pass.
