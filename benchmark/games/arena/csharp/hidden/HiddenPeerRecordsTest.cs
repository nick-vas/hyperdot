namespace Glimmerpit.Tests;

using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: whatever the server keeps per player goes when the player goes, so a
/// server that sees hundreds of players come and go keeps no more state, and holds no more memory, than a new one.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenPeerRecordsTest
{
    private List<Court> _courts = null!;
    private ArenaServer _server = null!;
    private SimLink _link = null!;

    [BeforeTest]
    public void Start()
    {
        _courts = Court.LoadAll();
        _server = new ArenaServer(_courts, 2);
        _link = new SimLink(_server);
        var host = new ArenaClient(_courts);
        _link.Join(host, 1);
        for (int i = 0; i < 10; i++)
            Tick(host);
    }

    private void Tick(ArenaClient? client)
    {
        client?.Step(1, 0, 1, 0, true);
        _link.Pump();
        _server.Tick();
        _link.Pump();
        _link.Advance();
    }

    private void Cycles(int count, int firstPeer)
    {
        for (int n = 0; n < count; n++)
        {
            int peer = firstPeer + n;
            var guest = new ArenaClient(_courts);
            _link.Join(guest, peer);
            for (int i = 0; i < 12; i++)
                Tick(guest);
            _link.Leave(peer);
            Tick(null);
        }
    }

    // The sizes of every collection the server keeps, by field name (private ones and properties' backing fields too).
    private Dictionary<string, int> Collections()
    {
        var sizes = new Dictionary<string, int>();
        foreach (FieldInfo field in typeof(ArenaServer).GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
        {
            if (field.GetValue(_server) is ICollection collection)
                sizes[field.Name] = collection.Count;
        }
        return sizes;
    }

    private static long ManagedBytes()
    {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        return GC.GetTotalMemory(true);
    }

    [TestCase]
    public void Hidden_no_state_outlives_its_player()
    {
        Cycles(10, 100);
        Dictionary<string, int> before = Collections();
        Cycles(200, 1000);
        Dictionary<string, int> after = Collections();
        foreach (KeyValuePair<string, int> entry in before)
            AssertThat(after[entry.Key]).OverrideFailureMessage($"{entry.Key} grew from {entry.Value} to {after[entry.Key]}").IsEqual(entry.Value);
        AssertThat(_server.RecordCount()).IsEqual(_server.PeerCount());
    }

    [TestCase]
    public void Hidden_memory_stays_flat()
    {
        Cycles(20, 100);
        long before = ManagedBytes();
        Cycles(300, 1000);
        long grown = ManagedBytes() - before;
        AssertThat(grown).OverrideFailureMessage($"{grown} bytes kept after 300 players came and went").IsLess(200000L);
    }
}
