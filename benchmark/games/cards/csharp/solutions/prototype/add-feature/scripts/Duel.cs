namespace Lanternfen;

using System;
using System.Collections.Generic;
using System.Text.Json.Nodes;
using Godot;

/// <summary>A turn's phases, in order; Over ends the duel from any of them.</summary>
public enum Phase
{
    Draw,
    Main,
    Clash,
    End,
    Over,
}

/// <summary>
/// One duel as plain rules: two keepers, whose turn it is and the turn's phase. A turn runs Draw -> Main -> Clash -> End,
/// then the other keeper's Draw. Clash is skipped when the active keeper has no wisp to strike with, and any phase ends in
/// Over once a keeper's light is gone. Every transition is logged ([Turn] 3 Main -> Clash) and signalled: nodes animate
/// a phase change but never decide one.
/// </summary>
public sealed class Duel
{
    public static readonly string[] PhaseNames = { "Draw", "Main", "Clash", "End", "Over" };
    public const int HandStart = 4;
    public const int HandMax = 7;
    public const int MaxKindling = 6;

    public event Action<Phase, Phase>? PhaseChanged;
    public event Action<int, Card>? CardPlayed;
    public event Action<int, int>? WispFell;
    public event Action<int, int>? KeeperHit;

    public Cards Cards { get; private set; } = new();
    public Keeper[] Keepers { get; private set; } = Array.Empty<Keeper>();
    public Phase Phase { get; set; } = Phase.Draw;
    /// <summary>Counts both keepers' turns: turn 1 is seat 0's first, turn 2 seat 1's first.</summary>
    public int Turn { get; set; } = 1;
    public int Active { get; set; }
    /// <summary>The seat that won; -1 while the duel goes on.</summary>
    public int Winner { get; set; } = -1;
    /// <summary>The lane the Clash strikes from next.</summary>
    public int ClashLane { get; set; }
    public long Seed { get; private set; }
    /// <summary>The duel's own generator: the engine's, so a seed deals the same cards as in the GDScript version.</summary>
    public RandomNumberGenerator Rng { get; } = new();

    /// <summary>A new duel: each deck shuffled by the duel's own generator, seeded, then the opening hands dealt. Seat 0 begins.</summary>
    public static Duel Start(Cards catalogue, IReadOnlyList<IEnumerable<string>> decks, IReadOnlyList<int> lights, long seed)
    {
        var duel = new Duel { Cards = catalogue, Seed = seed };
        duel.Rng.Seed = (ulong)seed;
        duel.Keepers = new Keeper[2];
        for (int seat = 0; seat < 2; seat++)
        {
            duel.Keepers[seat] = new Keeper
            {
                Light = lights[seat],
                MaxLight = lights[seat],
                Deck = Deck.Shuffled(decks[seat], duel.Rng),
            };
        }
        for (int seat = 0; seat < 2; seat++)
        {
            for (int i = 0; i < HandStart; i++)
                duel.DrawCard(seat);
        }
        return duel;
    }

    public string PhaseName => PhaseNames[(int)Phase];

    /// <summary>Draws the top card. A card drawn into a full hand goes to the discard pile; an empty deck costs light (fatigue).</summary>
    public bool DrawCard(int seat)
    {
        Keeper keeper = Keepers[seat];
        if (keeper.Deck.Count == 0)
        {
            keeper.Fatigue += 1;
            Burn(seat, keeper.Fatigue);
            return false;
        }
        string id = keeper.Deck[0];
        keeper.Deck.RemoveAt(0);
        if (keeper.Hand.Count >= HandMax)
        {
            keeper.Discard.Add(id);
            return false;
        }
        keeper.Hand.Add(id);
        return true;
    }

    /// <summary>
    /// Moves the duel on by one step: Draw draws and opens Main, Main ends (as EndMain), each Clash step strikes one lane,
    /// End passes the turn. Main waits for plays; Over does nothing.
    /// </summary>
    public void Advance()
    {
        switch (Phase)
        {
            case Phase.Draw:
                Keeper keeper = Keepers[Active];
                keeper.Turns += 1;
                keeper.Kindling = Math.Min(keeper.Turns, MaxKindling);
                DrawCard(Active);
                if (Phase == Phase.Draw)
                    Go(Phase.Main);
                break;
            case Phase.Main:
                EndMain();
                break;
            case Phase.Clash:
                StrikeNext();
                break;
            case Phase.End:
                Active = 1 - Active;
                Turn += 1;
                Go(Phase.Draw);
                break;
        }
    }

    /// <summary>Main -> Clash when the active keeper has a wisp to strike with; a phase with nothing to do is skipped.</summary>
    public void EndMain()
    {
        if (Phase != Phase.Main)
            return;
        ClashLane = 0;
        Go(Keepers[Active].WispCount() > 0 ? Phase.Clash : Phase.End);
    }

    /// <summary>
    /// Whether the active keeper may play this card of its hand now: its Main phase, the kindling for it, a free lane for a
    /// wisp, and something to act on for a rite that needs it.
    /// </summary>
    public bool CanPlay(int seat, int index)
    {
        if (Phase != Phase.Main || seat != Active || index < 0 || index >= Keepers[seat].Hand.Count)
            return false;
        Keeper keeper = Keepers[seat];
        Card card = Cards.Get(keeper.Hand[index]);
        if (card.Cost > keeper.Kindling)
            return false;
        if (card.Kind == Cards.Wisp)
            return keeper.FreeLane() >= 0;
        return card.Effect switch
        {
            "douse" => StrongestLane(1 - seat) >= 0,
            "rekindle" => LastFallen(seat) >= 0,
            _ => true,
        };
    }

    /// <summary>Plays a card of the active keeper's hand: a wisp to the first free lane, a rite resolved once and discarded.</summary>
    public bool Play(int seat, int index)
    {
        if (!CanPlay(seat, index))
            return false;
        Keeper keeper = Keepers[seat];
        string id = keeper.Hand[index];
        Card card = Cards.Get(id);
        keeper.Hand.RemoveAt(index);
        keeper.Kindling -= card.Cost;
        CardPlayed?.Invoke(seat, card);
        if (card.Kind == Cards.Wisp)
        {
            keeper.Row[keeper.FreeLane()] = Wisp.Of(card);
        }
        else
        {
            keeper.Discard.Add(id);
            Resolve(seat, card);
        }
        return true;
    }

    private void Resolve(int seat, Card card)
    {
        Keeper keeper = Keepers[seat];
        int amount = card.Amount;
        switch (card.Effect)
        {
            case "bolt":
                Burn(1 - seat, amount);
                break;
            case "mend":
                keeper.Light = Math.Min(keeper.Light + amount, keeper.MaxLight);
                break;
            case "draw":
                for (int i = 0; i < amount; i++)
                    DrawCard(seat);
                break;
            case "douse":
                Wound(1 - seat, StrongestLane(1 - seat), amount);
                break;
            case "rekindle":
                int at = LastFallen(seat);
                keeper.Hand.Add(keeper.Discard[at]);
                keeper.Discard.RemoveAt(at);
                break;
        }
    }

    /// <summary>The lane of a keeper's strongest wisp (most power, then the first lane); -1 when its row is empty.</summary>
    public int StrongestLane(int seat)
    {
        int best = -1;
        Wisp?[] row = Keepers[seat].Row;
        for (int lane = 0; lane < Keeper.Lanes; lane++)
        {
            Wisp? wisp = row[lane];
            if (wisp != null && (best < 0 || wisp.Power > row[best]!.Power))
                best = lane;
        }
        return best;
    }

    /// <summary>Where in a keeper's discard pile the newest wisp lies; -1 when there is none.</summary>
    public int LastFallen(int seat)
    {
        List<string> pile = Keepers[seat].Discard;
        for (int at = pile.Count - 1; at >= 0; at--)
        {
            if (Cards.Get(pile[at]).Kind == Cards.Wisp)
                return at;
        }
        return -1;
    }

    /// <summary>
    /// One lane of the Clash: the active keeper's next wisp strikes the wisp across, each taking the other's power, or the
    /// other keeper's light when the lane across is empty. Clash -> End once no wisp is left to strike.
    /// </summary>
    private void StrikeNext()
    {
        Keeper me = Keepers[Active];
        Keeper foe = Keepers[1 - Active];
        while (ClashLane < Keeper.Lanes && me.Row[ClashLane] == null)
            ClashLane += 1;
        if (ClashLane >= Keeper.Lanes)
        {
            Go(Phase.End);
            return;
        }
        int lane = ClashLane;
        ClashLane += 1;
        Wisp wisp = me.Row[lane]!;
        if (foe.Row[lane] == null)
        {
            Burn(1 - Active, wisp.Power);
            return;
        }
        int taken = foe.Row[lane]!.Power;
        Wound(1 - Active, lane, wisp.Power);
        Wound(Active, lane, taken);
    }

    private void Wound(int seat, int lane, int amount)
    {
        Wisp wisp = Keepers[seat].Row[lane]!;
        wisp.Guard -= amount;
        if (wisp.Guard <= 0)
        {
            Keepers[seat].Row[lane] = null;
            Keepers[seat].Discard.Add(wisp.Id);
            WispFell?.Invoke(seat, lane);
        }
    }

    /// <summary>Takes light from a keeper; at 0 the duel is over and the other keeper has won.</summary>
    private void Burn(int seat, int amount)
    {
        Keepers[seat].Light -= amount;
        KeeperHit?.Invoke(seat, amount);
        if (Keepers[seat].Light <= 0 && Winner < 0)
        {
            Winner = 1 - seat;
            Go(Phase.Over);
        }
    }

    private void Go(Phase to)
    {
        Phase from = Phase;
        Phase = to;
        GD.Print($"[Turn] {Turn} {PhaseNames[(int)from]} -> {PhaseNames[(int)to]}");
        PhaseChanged?.Invoke(from, to);
    }

    /// <summary>Everything needed to carry on later from where the duel stands.</summary>
    public JsonObject ToDict() => new()
    {
        ["seed"] = Seed,
        ["turn"] = Turn,
        ["active"] = Active,
        ["phase"] = PhaseNames[(int)Phase],
        ["clash_lane"] = ClashLane,
        ["winner"] = Winner,
        ["keepers"] = new JsonArray(Keepers[0].ToDict(), Keepers[1].ToDict()),
    };

    public static Duel FromDict(Cards catalogue, JsonObject data)
    {
        var duel = new Duel { Cards = catalogue, Seed = (long)JsonData.Number(data["seed"], 0) };
        duel.Rng.Seed = (ulong)duel.Seed;
        duel.Turn = JsonData.Int(data["turn"], 1);
        duel.Active = Math.Clamp(JsonData.Int(data["active"], 0), 0, 1);
        duel.Phase = (Phase)Math.Max(Array.IndexOf(PhaseNames, JsonData.Text(data["phase"], "Main")), 0);
        duel.ClashLane = JsonData.Int(data["clash_lane"], 0);
        duel.Winner = JsonData.Int(data["winner"], -1);
        JsonArray? sides = data["keepers"] as JsonArray;
        duel.Keepers = new Keeper[2];
        for (int seat = 0; seat < 2; seat++)
        {
            JsonObject side = sides != null && seat < sides.Count && sides[seat] is JsonObject found ? found : new JsonObject();
            duel.Keepers[seat] = Keeper.FromDict(side);
        }
        return duel;
    }
}
