namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Controls: a rebound key replaces the keyboard binding and keeps the gamepad's, and bindings save as key names.</summary>
[TestSuite]
[RequireGodotRuntime]
public class ControlsTest
{
    [AfterTest]
    public void Reset()
    {
        Controls.Reset();
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
    public void Every_action_has_a_key_and_a_gamepad_binding()
    {
        foreach (string action in Controls.Actions)
        {
            AssertThat(Controls.KeyOf(action)).OverrideFailureMessage(action).IsNotEqual(Key.None);
            AssertThat(HasJoypad(action)).OverrideFailureMessage(action).IsTrue();
        }
    }

    [TestCase]
    public void A_rebound_key_drives_the_action_and_the_gamepad_still_does()
    {
        AssertThat(Controls.Rebind("accelerate", Key.J)).IsTrue();
        AssertThat(Controls.KeyOf("accelerate")).IsEqual(Key.J);
        AssertThat(HasJoypad("accelerate")).IsTrue();
        var press = new InputEventKey { PhysicalKeycode = Key.J, Pressed = true };
        AssertThat(press.IsAction("accelerate")).IsTrue();
    }

    [TestCase]
    public void Only_the_game_actions_can_be_rebound()
    {
        AssertThat(Controls.Rebind("ui_accept", Key.J)).IsFalse();
        AssertThat(Controls.Rebind("pause", Key.J)).IsFalse();
    }

    [TestCase]
    public void Bindings_save_as_key_names_and_apply_back()
    {
        Controls.Rebind("brake", Key.K);
        SortedDictionary<string, string> saved = Controls.ToDict();
        AssertThat(saved["brake"]).IsEqual("K");
        Controls.Reset();
        AssertThat(Controls.KeyOf("brake")).IsEqual(Key.S);
        Controls.Apply(saved);
        AssertThat(Controls.KeyOf("brake")).IsEqual(Key.K);
    }

    [TestCase]
    public void Unknown_actions_and_keys_change_nothing()
    {
        Controls.Apply(new Dictionary<string, string> { ["jump"] = "J", ["steer_left"] = "NoSuchKey" });
        AssertThat(Controls.KeyOf("steer_left")).IsEqual(Key.A);
        Controls.Apply(null);
        AssertThat(Controls.KeyOf("steer_left")).IsEqual(Key.A);
    }
}
