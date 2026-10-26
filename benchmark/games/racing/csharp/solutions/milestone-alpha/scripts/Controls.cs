namespace Cinderloop;

using System.Collections.Generic;
using Godot;

/// <summary>
/// The keys the player has rebound. Only keyboard bindings change: each action keeps its controller bindings, so a
/// rebind never takes the gamepad away. Keys are kept by their physical position (WASD stays under the same fingers on
/// another layout) and saved as their names, {"accelerate": "W"}; an unknown action or key name changes nothing.
/// </summary>
public static class Controls
{
    public static readonly string[] Actions = { "accelerate", "brake", "steer_left", "steer_right" };

    /// <summary>The keyboard key of an action, None when it has none.</summary>
    public static Key KeyOf(string action)
    {
        foreach (InputEvent inputEvent in InputMap.ActionGetEvents(action))
        {
            if (inputEvent is InputEventKey key)
                return key.PhysicalKeycode != Key.None ? key.PhysicalKeycode : key.Keycode;
        }
        return Key.None;
    }

    public static string Label(string action)
    {
        Key key = KeyOf(action);
        return key != Key.None ? OS.GetKeycodeString(key) : "-";
    }

    /// <summary>Binds an action to a key in place of its keyboard binding; false for an action that is not rebindable.</summary>
    public static bool Rebind(string action, Key key)
    {
        if (System.Array.IndexOf(Actions, action) < 0 || key == Key.None)
            return false;
        foreach (InputEvent inputEvent in InputMap.ActionGetEvents(action))
        {
            if (inputEvent is InputEventKey)
                InputMap.ActionEraseEvent(action, inputEvent);
        }
        InputMap.ActionAddEvent(action, new InputEventKey { PhysicalKeycode = key });
        return true;
    }

    /// <summary>Each rebindable action's key by its name, the actions in name order.</summary>
    public static SortedDictionary<string, string> ToDict()
    {
        var keys = new SortedDictionary<string, string>();
        foreach (string action in Actions)
        {
            Key key = KeyOf(action);
            if (key != Key.None)
                keys[action] = OS.GetKeycodeString(key);
        }
        return keys;
    }

    /// <summary>Applies saved bindings over the current ones.</summary>
    public static void Apply(IReadOnlyDictionary<string, string>? keys)
    {
        if (keys == null)
            return;
        foreach (string action in Actions)
        {
            if (keys.TryGetValue(action, out string? name))
            {
                Key key = OS.FindKeycodeFromString(name);
                if (key != Key.None)
                    Rebind(action, key);
            }
        }
    }

    /// <summary>Back to the project's bindings.</summary>
    public static void Reset()
    {
        InputMap.LoadFromProjectSettings();
    }
}
