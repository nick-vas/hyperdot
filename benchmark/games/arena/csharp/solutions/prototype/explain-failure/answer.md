The failing test is `A_straight_step_moves_eight_pixels` in `test/SimTest.cs`, line 30. It moves a glimmer at
(100, 200) one tick to the right and expects it at (108, 200), eight pixels; it got (106, 200), six.

The game is wrong, not the test. In `scripts/Sim.cs`, `Sim.Step` picks the diagonal speed (6) when `mx != 0 || my != 0`,
so every step, straight ones too, uses it; it should be `mx != 0 && my != 0`, keeping 8 for a straight step. The
diagonal test still passes because diagonal steps were already 6.
