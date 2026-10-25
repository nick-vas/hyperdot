The failing test is `test_the_best_lap_is_the_fastest` in `test/unit/test_lap_tracker.gd`, line 59:
`assert_eq(tracker.best_lap, 300)`. It drives laps of 600, 300 and 350 ticks and expects the best lap to be 300; it got
600, the slowest.

The game is wrong, not the test. `LapTracker.update` (`scripts/lap_tracker.gd`, line 34) keeps a new best when
`time > best_lap`, so `best_lap` holds the slowest lap. It should be `time < best_lap`.
