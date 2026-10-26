namespace Duskhive.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the release's fix-store: the library capsule is Steam's 600x900.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenCapsuleTest
{
    private static Vector2I PngSize(string path)
    {
        byte[] bytes = FileAccess.GetFileAsBytes(path);
        if (bytes.Length < 24 || bytes[1] != 0x50)
            return Vector2I.Zero;
        int w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        int h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        return new Vector2I(w, h);
    }

    [TestCase]
    public void Hidden_library_capsule_is_600_by_900()
    {
        AssertThat(PngSize("res://store/steam/library_capsule.png")).IsEqual(new Vector2I(600, 900));
    }
}
