The failing test is `test_clearing_a_wave_pays_its_bonus` in `test/unit/test_economy.gd`, at line 21
(`assert_eq(battle.gold, 115)`): it expected 115 sap after the one-aphid wave and got 130.

The game is wrong, not the test. The battle starts with 100 sap, no tower kills the aphid (so no reward), and the wave's
bonus is 15, so clearing it should leave 100 + 15 = 115. In `Battle._clear_wave` (`scripts/battle.gd`) the line
`gold += bonus` is there twice, so the bonus is paid twice: 100 + 30 = 130. The lives check on line 20 passes.
