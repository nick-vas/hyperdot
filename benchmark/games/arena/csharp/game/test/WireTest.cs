namespace Glimmerpit.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Wire: the netcode's messages in the engine's own var_to_bytes format, byte for byte, and junk refused.</summary>
[TestSuite]
[RequireGodotRuntime]
public class WireTest
{
    [TestCase]
    public void Messages_are_the_engines_bytes()
    {
        var arena = new ArenaMatch(Court.LoadAll());
        var message = new Dictionary<string, object?> { ["t"] = "welcome", ["slot"] = 2, ["snap"] = arena.Snapshot() };
        message["big"] = 1L << 40;
        message["half"] = 0.5;
        message["third"] = 1.0 / 3.0;
        message["none"] = null;
        message["yes"] = true;
        message["name"] = "Fosse de cendres";
        var native = new Godot.Collections.Dictionary
        {
            ["t"] = "welcome", ["slot"] = 2, ["snap"] = ToNative(arena.Snapshot()), ["big"] = 1L << 40, ["half"] = 0.5,
            ["third"] = 1.0 / 3.0, ["none"] = default, ["yes"] = true, ["name"] = "Fosse de cendres",
        };
        AssertThat(Wire.Encode(message)).ContainsExactly(GD.VarToBytes(native));
    }

    [TestCase]
    public void The_engines_bytes_read_back()
    {
        var input = new SimInput { Seq = 7, Mx = -1, My = 1, Ax = -9000, Ay = 40, Fire = true, Claim = 3 };
        var native = new Godot.Collections.Dictionary
        {
            ["t"] = "input", ["inputs"] = new Godot.Collections.Array { ToNative(input.ToWire()) },
        };
        var back = Wire.Map(Wire.Decode(GD.VarToBytes(native)))!;
        AssertThat(Wire.Text(back["t"])).IsEqual("input");
        SimInput read = Sim.Sanitize(Wire.Map(Wire.List(back["inputs"])![0])!);
        AssertThat(new[] { read.Seq, read.Mx, read.My, read.Ax, read.Ay, read.Claim }).ContainsExactly(7, -1, 1, -9000, 40, 3);
        AssertThat(read.Fire).IsTrue();
    }

    [TestCase]
    public void Junk_is_no_message()
    {
        AssertThat(Wire.Decode(new byte[] { 27, 0, 0, 0, 255, 255, 255, 127 })).IsNull();
        AssertThat(Wire.Decode(new byte[] { 4, 0, 0, 0, 100, 0, 0, 0, 65 })).IsNull();
        AssertThat(Wire.Decode(new byte[] { 2, 0 })).IsNull();
        AssertThat(Wire.Decode(System.Array.Empty<byte>())).IsNull();
    }

    // The same message built from the engine's own containers.
    private static Variant ToNative(object? value) => value switch
    {
        null => default,
        bool b => b,
        int i => i,
        long l => l,
        double d => d,
        string s => s,
        Dictionary<string, object?> map => ToNativeMap(map),
        List<object?> list => ToNativeList(list),
        _ => default,
    };

    private static Godot.Collections.Dictionary ToNativeMap(Dictionary<string, object?> map)
    {
        var native = new Godot.Collections.Dictionary();
        foreach (KeyValuePair<string, object?> pair in map)
            native[pair.Key] = ToNative(pair.Value);
        return native;
    }

    private static Godot.Collections.Array ToNativeList(List<object?> list)
    {
        var native = new Godot.Collections.Array();
        foreach (object? item in list)
            native.Add(ToNative(item));
        return native;
    }
}
