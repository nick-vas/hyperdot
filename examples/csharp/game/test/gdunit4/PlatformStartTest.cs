namespace Example.Tests;

using Example.Core.Platform;
using GdUnit4;
using static GdUnit4.Assertions;

// The start-up choice of platform backend. In a default build, and in a -p:Steam=true build run without a Steam client
// (CI, this test), the game must start with the local platform and not crash; the Steam build logs one line.
[TestSuite]
[RequireGodotRuntime]
public class PlatformStartTest
{
    [TestCase]
    public void StartsWithoutSteamOnTheLocalPlatform()
    {
        var choice = GamePlatform.Start();
        AssertThat(choice.QuitRequested).IsFalse();
        AssertThat(choice.UsesSteam).IsFalse();
        AssertThat(choice.Platform is LocalPlatform).IsTrue();
#if STEAM
        AssertThat(choice.FallbackReason).IsNotNull();
#else
        AssertThat(choice.FallbackReason).IsNull();
#endif
    }
}
