The failing test is `The_best_lap_is_the_fastest` in `test/LapTrackerTest.cs`, line 84:
`AssertThat(tracker.BestLap).IsEqual(300)`. It drives laps of 600, 300 and 350 ticks and expects the best lap to be
300; it got 600, the slowest.

The game is wrong, not the test. `LapTracker.Update` (`scripts/LapTracker.cs`, line 49) keeps a new best when
`time > BestLap`, so `BestLap` holds the slowest lap. It should be `time < BestLap`.
