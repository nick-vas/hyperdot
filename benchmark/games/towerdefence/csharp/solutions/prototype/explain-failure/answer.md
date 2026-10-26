The failing test is `Clearing_a_wave_pays_its_bonus` in `test/EconomyTest.cs`, at line 26
(`AssertThat(battle.Gold).IsEqual(115)`): it expected 115 sap after the one-aphid wave and got 130.

The game is wrong, not the test. The battle starts with 100 sap, no tower kills the aphid (so no reward), and the wave's
bonus is 15, so clearing it should leave 100 + 15 = 115. In `Battle.ClearWave` (`scripts/Battle.cs`) the line
`Gold += bonus;` is there twice, so the bonus is paid twice: 100 + 30 = 130. The lives check on line 25 passes.
