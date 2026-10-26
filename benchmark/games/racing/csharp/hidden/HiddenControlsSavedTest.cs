namespace Cinderloop.Tests;

using System;
using System.IO;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-flow: keys rebound in Settings survive a restart. Saved by SaveStore, read back by a
/// new game and applied the way Main applies them at start, the key drives its action and the gamepad still does.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenControlsSavedTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"cinderloop-controls-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void CleanUp()
    {
        Controls.Reset();
        TranslationServer.SetLocale("en");
        File.Delete(_path);
        File.Delete(_path + ".tmp");
    }

    private static bool HasJoypad(string action)
    {
        foreach (InputEvent inputEvent in InputMap.ActionGetEvents(action))
        {
            if (inputEvent is InputEventJoypadButton or InputEventJoypadMotion)
                return true;
        }
        return false;
    }

    [TestCase]
    public void Hidden_a_rebound_key_survives_a_restart()
    {
        var save = new SaveData();
        Controls.Rebind("accelerate", Key.I);
        Controls.Rebind("steer_left", Key.J);
        save.Controls = Controls.ToDict();
        AssertThat(new SaveStore(_path).Write(save)).IsTrue();
        // The game quits: the bindings go back to the project's.
        Controls.Reset();
        AssertThat(Controls.KeyOf("accelerate")).IsEqual(Key.W);
        Main.ApplySettings(new SaveStore(_path).Read());
        AssertThat(Controls.KeyOf("accelerate")).IsEqual(Key.I);
        AssertThat(Controls.KeyOf("steer_left")).IsEqual(Key.J);
        AssertThat(Controls.KeyOf("brake")).OverrideFailureMessage("keys not rebound stay").IsEqual(Key.S);
        AssertThat(HasJoypad("accelerate")).IsTrue();
    }

    [TestCase]
    public void Hidden_the_other_settings_still_survive()
    {
        var save = new SaveData { Locale = "fr" };
        save.Best["1"] = 27000;
        Controls.Rebind("brake", Key.K);
        save.Controls = Controls.ToDict();
        new SaveStore(_path).Write(save);
        SaveData back = new SaveStore(_path).Read();
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(back.Best["1"]).IsEqual(27000);
        AssertThat(back.Controls.TryGetValue("brake", out string? key) ? key : null).IsEqual("K");
    }
}
