namespace Glimmerpit;

/// <summary>
/// --autoplay: a bot plays the player's glimmer through the player's own client, from what that client sees, and a
/// guest joins the same match as a second client on the link, played by another bot. The guest walks out whenever it is
/// one of the last two standing with one health left, and comes back a little later, so every bot run also covers
/// players leaving and joining in the middle of a match.
/// </summary>
public sealed class Autopilot
{
    public const int GuestPeer = 2;
    /// <summary>Ticks the guest stays away after leaving.</summary>
    public const int AwayTicks = 60;

    private readonly Game _game;
    private readonly Bot _bot;
    private readonly Bot _guestBot;
    private int _away;

    public Autopilot(Game game, long runSeed)
    {
        _game = game;
        _bot = new Bot(0, runSeed * 31 + 1);
        _guestBot = new Bot(1, runSeed * 31 + 2);
        if (game.link != null)
            JoinGuest();
    }

    public ArenaClient? Guest { get; private set; }
    public int Leaves { get; private set; }

    /// <summary>The player's input for this tick, from the player's bot.</summary>
    public SimInput PlayerInput()
    {
        ArenaClient client = _game.client!;
        if (!client.IsPlaying())
            return Sim.Idle();
        _bot.Slot = client.Slot;
        return _bot.Decide(client.View, client.Predicted);
    }

    /// <summary>The guest's tick: play, walk out, or come back.</summary>
    public void Tick()
    {
        SimLink? link = _game.link;
        if (link == null)
            return;
        if (Guest == null)
        {
            _away--;
            if (_away <= 0)
                JoinGuest();
            return;
        }
        if (!Guest.IsPlaying())
            return;
        _guestBot.Slot = Guest.Slot;
        SimInput input = _guestBot.Decide(Guest.View, Guest.Predicted);
        Guest.Step(input.Mx, input.My, input.Ax, input.Ay, input.Fire, input.Dash);
        Guest.Events.Clear();
        if (Losing(Guest))
        {
            Leaves++;
            link.Leave(GuestPeer);
            Guest = null;
            _away = AwayTicks;
        }
    }

    private static bool Losing(ArenaClient c)
    {
        ArenaMatch arena = c.View;
        return arena.State == MatchState.Round && c.Predicted!.Alive && c.Predicted.Hp == 1 && arena.AliveSlots().Count == 2;
    }

    private void JoinGuest()
    {
        Guest = new ArenaClient(_game.Courts);
        _game.link!.Join(Guest, GuestPeer);
    }

    public void Stop()
    {
        if (Guest != null && _game.link != null)
            _game.link.Leave(GuestPeer);
        Guest = null;
    }
}
