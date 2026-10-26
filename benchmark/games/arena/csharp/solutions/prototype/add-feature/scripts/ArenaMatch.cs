namespace Glimmerpit;

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using Godot;

public enum MatchState
{
    Warmup,
    Round,
    Intermission,
    Over,
}

/// <summary>
/// Something that happened in a match, carried to clients in the snapshots: <c>shot</c> (Slot, X, Y, Ex, Ey), <c>hit</c>
/// (Slot, By), <c>out</c> (Slot, By, X, Y), <c>gone</c> (Slot), <c>round</c> (Round, Winner), <c>start</c> (Round) and
/// <c>over</c> (Winner). On the wire it is a dictionary of the fields its type has, as in the GDScript version.
/// </summary>
public sealed class MatchEvent
{
    public string Type { get; init; } = "";
    public int Slot { get; init; } = -1;
    public int By { get; init; } = -1;
    public int X { get; init; }
    public int Y { get; init; }
    public int Ex { get; init; }
    public int Ey { get; init; }
    public int Round { get; init; }
    public int Winner { get; init; } = -1;

    public Dictionary<string, object?> ToWire()
    {
        var wire = new Dictionary<string, object?> { ["type"] = Type };
        switch (Type)
        {
            case "shot":
                wire["slot"] = Slot; wire["x"] = X; wire["y"] = Y; wire["ex"] = Ex; wire["ey"] = Ey;
                break;
            case "hit":
                wire["slot"] = Slot; wire["by"] = By;
                break;
            case "out":
                wire["slot"] = Slot; wire["by"] = By; wire["x"] = X; wire["y"] = Y;
                break;
            case "gone":
                wire["slot"] = Slot;
                break;
            case "round":
                wire["round"] = Round; wire["winner"] = Winner;
                break;
            case "start":
                wire["round"] = Round;
                break;
            case "over":
                wire["winner"] = Winner;
                break;
        }
        return wire;
    }

    public static MatchEvent FromWire(Dictionary<string, object?> wire)
    {
        int Get(string key, int fallback) => Wire.Int(Wire.Get(wire, key), fallback);
        return new MatchEvent
        {
            Type = Wire.Text(Wire.Get(wire, "type")),
            Slot = Get("slot", -1),
            By = Get("by", -1),
            X = Get("x", 0),
            Y = Get("y", 0),
            Ex = Get("ex", 0),
            Ey = Get("ey", 0),
            Round = Get("round", 0),
            Winner = Get("winner", -1),
        };
    }
}

/// <summary>
/// The rules of a match, with no networking and no nodes: four slots, each held by a player or a bot, fight rounds of
/// last-glimmer-standing on the courts in turn, and the first slot to win Target rounds wins the match. The server runs
/// the true match; each client keeps one loaded from snapshots (LoadSnapshot) for drawing and for its bot.
/// </summary>
public sealed class ArenaMatch
{
    public const int Slots = 4;
    /// <summary>Rounds a slot must win to take the match.</summary>
    public const int Target = 3;
    public const int Hp = 5;
    public const int Damage = 1;
    /// <summary>Ticks before the first round.</summary>
    public const int WarmupTicks = 30;
    /// <summary>Ticks between rounds.</summary>
    public const int IntermissionTicks = 45;
    /// <summary>Ticks showing a finished match (a looping server then starts the next).</summary>
    public const int OverTicks = 150;
    /// <summary>Owners value of a slot played by a bot.</summary>
    public const int Bot = 0;

    private static readonly string[] StateNames = { "warmup", "round", "intermission", "over" };

    public ArenaMatch(List<Court>? courts = null)
    {
        Courts = courts ?? new List<Court>();
        Court = Courts.Count > 0 ? Courts[0] : new Court();
        for (int slot = 0; slot < Slots; slot++)
            Fighters.Add(new Fighter { Slot = slot });
    }

    public List<Court> Courts { get; }
    public Court Court { get; private set; }
    public int Tick { get; private set; }
    public int RoundNumber { get; private set; }
    public MatchState State { get; private set; } = MatchState.Warmup;
    /// <summary>Ticks spent in the current state.</summary>
    public int StateTicks { get; private set; }
    public List<Fighter> Fighters { get; } = new();
    /// <summary>Per slot: Bot, or the peer id of the player who holds it.</summary>
    public int[] Owners { get; } = new int[Slots];
    /// <summary>Per slot: rounds won in this match.</summary>
    public int[] Scores { get; } = new int[Slots];
    public int Winner { get; private set; } = -1;
    /// <summary>Matches finished since the server started.</summary>
    public int Matches { get; private set; }
    /// <summary>Shots whose hit the shooter's client claimed otherwise than the server's trace found: lag, or a cheat.</summary>
    public int RefusedClaims { get; private set; }
    /// <summary>What happened since the last TakeEvents(): shots, hits, outs, rounds, the end; snapshots carry them to clients.</summary>
    public List<MatchEvent> Events { get; private set; } = new();

    public string StateName() => StateNames[(int)State];

    public bool IsBot(int slot) => Owners[slot] == Bot;

    /// <summary>A match point: some slot is one round from winning.</summary>
    public bool IsMatchPoint() => State != MatchState.Over && Scores.Max() == Target - 1;

    public List<int> AliveSlots()
    {
        var alive = new List<int>();
        foreach (Fighter f in Fighters)
        {
            if (f.Alive)
                alive.Add(f.Slot);
        }
        return alive;
    }

    /// <summary>Applies one slot's input for this tick. Inputs outside a round do nothing.</summary>
    public void Apply(int slot, SimInput input)
    {
        if (State != MatchState.Round)
            return;
        if (Sim.Step(Fighters[slot], input, Court))
            Fire(slot, input);
    }

    private void Fire(int slot, SimInput input)
    {
        Shot shot = Sim.Trace(Court, Fighters, slot);
        int target = shot.Target;
        if (input.Claim != shot.Target)
        {
            // The client saw it otherwise (it draws others a little in the past, or it lies): the server's trace stands.
            RefusedClaims++;
        }
        Fighter from = Fighters[slot];
        Events.Add(new MatchEvent { Type = "shot", Slot = slot, X = from.X, Y = from.Y, Ex = shot.X, Ey = shot.Y });
        if (target >= 0)
            DealDamage(slot, target);
    }

    /// <summary>A hit by one slot on another: one health, and out of the round at none. Public for the tests.</summary>
    public void DealDamage(int by, int target)
    {
        Fighter f = Fighters[target];
        f.Hp -= Damage;
        Events.Add(new MatchEvent { Type = "hit", Slot = target, By = by });
        if (f.Hp <= 0)
        {
            f.Alive = false;
            Events.Add(new MatchEvent { Type = "out", Slot = target, By = by, X = f.X, Y = f.Y });
            CheckRoundEnd();
        }
    }

    /// <summary>Moves the match on by one tick: the waits before and between rounds.</summary>
    public void Advance()
    {
        Tick++;
        StateTicks++;
        if (State == MatchState.Warmup && StateTicks >= WarmupTicks)
            BeginRound();
        else if (State == MatchState.Intermission && StateTicks >= IntermissionTicks)
            BeginRound();
    }

    /// <summary>A new match with the same owners: scores back to 0, the first round after the warm-up.</summary>
    public void Restart()
    {
        RoundNumber = 0;
        Winner = -1;
        for (int slot = 0; slot < Slots; slot++)
        {
            Scores[slot] = 0;
            Fighters[slot].Alive = false;
        }
        SetState(MatchState.Warmup);
    }

    /// <summary>
    /// Gives a slot to a player (a peer id) or back to a bot. Its score starts again: a newcomer does not inherit a
    /// leaver's rounds. Its glimmer leaves the round in play and comes back in the next one.
    /// </summary>
    public void SetOwner(int slot, int owner)
    {
        RemoveFighter(slot);
        Owners[slot] = owner;
        Scores[slot] = 0;
    }

    /// <summary>Takes a slot's glimmer out of the round in play (its player left, or a player took a bot's slot).</summary>
    public void RemoveFighter(int slot)
    {
        Fighter f = Fighters[slot];
        if (!f.Alive)
            return;
        f.Alive = false;
        Events.Add(new MatchEvent { Type = "gone", Slot = slot });
        CheckRoundEnd();
    }

    private void CheckRoundEnd()
    {
        if (State != MatchState.Round)
            return;
        List<int> alive = AliveSlots();
        if (alive.Count <= 1)
            EndRound(alive.Count == 1 ? alive[0] : -1);
    }

    private void EndRound(int roundWinner)
    {
        if (roundWinner >= 0)
        {
            Scores[roundWinner] += 1;
            GD.Print($"[Match] round {RoundNumber} won by slot {roundWinner} ({string.Join("-", Scores)})");
        }
        else
        {
            GD.Print($"[Match] round {RoundNumber} drawn");
        }
        Events.Add(new MatchEvent { Type = "round", Round = RoundNumber, Winner = roundWinner });
        if (roundWinner >= 0 && Scores[roundWinner] >= Target)
        {
            Winner = roundWinner;
            Matches++;
            GD.Print($"[Match] over: slot {Winner} wins {Scores[Winner]} rounds to {SecondBest()}");
            Events.Add(new MatchEvent { Type = "over", Winner = Winner });
            SetState(MatchState.Over);
        }
        else
        {
            SetState(MatchState.Intermission);
        }
    }

    private int SecondBest()
    {
        int best = 0;
        for (int slot = 0; slot < Slots; slot++)
        {
            if (slot != Winner)
                best = Math.Max(best, Scores[slot]);
        }
        return best;
    }

    private void BeginRound()
    {
        RoundNumber++;
        Court = Courts[(RoundNumber - 1) % Courts.Count];
        foreach (Fighter f in Fighters)
        {
            Vector2I spawn = Court.Spawns[(f.Slot + RoundNumber - 1) % Court.Spawns.Count];
            f.X = spawn.X;
            f.Y = spawn.Y;
            f.Ax = Court.Width / 2 - spawn.X;
            f.Ay = Court.Height / 2 - spawn.Y;
            f.Hp = Hp;
            f.Alive = true;
            f.Cooldown = 0;
            f.DashTicks = 0;
            f.DashCooldown = 0;
        }
        GD.Print($"[Match] round {RoundNumber} started on {Court.Id}");
        Events.Add(new MatchEvent { Type = "start", Round = RoundNumber });
        SetState(MatchState.Round);
    }

    private void SetState(MatchState next)
    {
        State = next;
        StateTicks = 0;
    }

    public List<MatchEvent> TakeEvents()
    {
        List<MatchEvent> taken = Events;
        Events = new List<MatchEvent>();
        return taken;
    }

    public Court CourtById(string courtId)
    {
        foreach (Court c in Courts)
        {
            if (c.Id == courtId)
                return c;
        }
        return Court;
    }

    /// <summary>What a client needs to draw the match and predict its own glimmer: the wire form, as in the GDScript version.</summary>
    public Dictionary<string, object?> Snapshot()
    {
        var fighters = new List<object?>();
        foreach (Fighter f in Fighters)
            fighters.Add(f.ToArray());
        return new Dictionary<string, object?>
        {
            ["tick"] = Tick, ["round"] = RoundNumber, ["court"] = Court.Id, ["state"] = (int)State, ["state_ticks"] = StateTicks,
            ["scores"] = Scores.Select(s => (object?)s).ToList(), ["owners"] = Owners.Select(o => (object?)o).ToList(),
            ["winner"] = Winner, ["fighters"] = fighters,
        };
    }

    public void LoadSnapshot(Dictionary<string, object?> snap)
    {
        Tick = Wire.Int(Wire.Get(snap, "tick"));
        RoundNumber = Wire.Int(Wire.Get(snap, "round"));
        Court = CourtById(Wire.Text(Wire.Get(snap, "court")));
        State = (MatchState)Wire.Int(Wire.Get(snap, "state"));
        StateTicks = Wire.Int(Wire.Get(snap, "state_ticks"));
        Winner = Wire.Int(Wire.Get(snap, "winner"), -1);
        List<int> scores = Wire.Ints(Wire.Get(snap, "scores"));
        List<int> owners = Wire.Ints(Wire.Get(snap, "owners"));
        IList fighters = Wire.List(Wire.Get(snap, "fighters"))!;
        for (int slot = 0; slot < Slots; slot++)
        {
            Scores[slot] = scores[slot];
            Owners[slot] = owners[slot];
            Fighters[slot] = Fighter.FromArray(Wire.List(fighters[slot])!);
        }
    }
}
