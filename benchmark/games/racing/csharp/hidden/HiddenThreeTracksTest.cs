namespace Cinderloop.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the alpha-to-beta milestone: three tracks, each finished by a full-pace driver, which beats the
/// rivals from the back of the grid on every one, and a bot from the command line.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenThreeTracksTest
{
    [TestCase]
    public void Hidden_three_tracks_the_bot_wins_from_the_back()
    {
        Tracks tracks = Tracks.FromFiles();
        foreach (int id in new[] { 1, 2, 3 })
        {
            // A missing track has no road to race on: stop here rather than race on nothing.
            AssertThat(tracks.HasTrack(id)).OverrideFailureMessage($"track {id}").IsTrue();
            var race = new Race(tracks.Track(id), tracks.DriversFor(3, 1009 + id, true), 60);
            while (race.FinishOrder.Count < race.Cars.Count && race.Tick < 150 * 60)
                race.Step();
            AssertThat(race.FinishOrder.Count).OverrideFailureMessage($"track {id}: every car finished").IsEqual(4);
            AssertThat(race.FinishOrder.IndexOf(0) + 1).OverrideFailureMessage($"track {id}: the bot in the top two").IsLessEqual(2);
        }
    }

    [TestCase]
    public void Hidden_the_bot_flag_is_read()
    {
        LaunchOptions options = LaunchOptions.Parse(new[] { "--autoplay", "--seed=4", "--no-save", "--track=2" });
        AssertThat(options.Autoplay).IsTrue();
        AssertThat(options.RunSeed).IsEqual(4L);
        AssertThat(options.NoSave).IsTrue();
        AssertThat(options.Track).IsEqual(2);
    }
}
