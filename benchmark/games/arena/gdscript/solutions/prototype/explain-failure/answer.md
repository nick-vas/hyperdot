The failing test is `test_a_straight_step_moves_eight_pixels` in `test/unit/test_sim.gd`, line 31. It moves a
glimmer at (100, 200) one tick to the right and expects it at (108, 200), eight pixels; it got (106, 200), six.

The game is wrong, not the test. In `scripts/sim.gd`, `Sim.step` picks the diagonal speed (6) when `mx != 0 or
my != 0`, so every step, straight ones too, uses it; it should be `mx != 0 and my != 0`, keeping 8 for a straight
step. The diagonal test still passes because diagonal steps were already 6.
