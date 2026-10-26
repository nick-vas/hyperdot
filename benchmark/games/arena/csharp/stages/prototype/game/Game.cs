namespace Glimmerpit;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// One local match in the pit against three bots: the court and the scores. The rules live in ArenaMatch and the
/// netcode in ArenaServer and ArenaClient; this node runs the server, reaches it with the player's client over a
/// SimLink (with --lag=MS of simulated round trip), reads the player's input and shows what the client knows.
/// Everything runs in _PhysicsProcess at 30 ticks a second.
/// </summary>
/// <remarks><c>server</c>, <c>link</c>, <c>client</c>, <c>state</c>, <c>round_number</c> and <c>my_slot</c> keep the names the GDScript version uses.</remarks>
public partial class Game : Node2D
{
    /// <summary>The local player's peer id on the in-process link.</summary>
    public const int LocalPeer = 1;
    /// <summary>Where the court's (0, 0) is drawn: below the HUD's score line.</summary>
    public static readonly Vector2 CourtOrigin = new(40, 64);
    public static readonly Color[] SlotColors =
    {
        new(0.98f, 0.78f, 0.3f), new(0.4f, 0.8f, 1.0f), new(0.95f, 0.45f, 0.6f), new(0.55f, 0.95f, 0.5f),
    };

    private static readonly StringName MoveLeft = "move_left";
    private static readonly StringName MoveRight = "move_right";
    private static readonly StringName MoveUp = "move_up";
    private static readonly StringName MoveDown = "move_down";
    private static readonly StringName FireAction = "fire";

    private CourtView _view = null!;
    private Label[] _slotLabels = null!;
    private Label _roundLabel = null!;
    private Label _statusLabel = null!;
    private Label _healthLabel = null!;

    public LaunchOptions Options { get; private set; } = null!;
    public List<Court> Courts { get; private set; } = new();
    public ArenaServer? server { get; private set; }
    public SimLink? link { get; private set; }
    public ArenaClient? client { get; private set; }

    /// <summary>"warmup", "round", "intermission" or "over", as this player's client knows it.</summary>
    public string state => client?.View.StateName() ?? "";

    public int round_number => client?.View.RoundNumber ?? 0;

    public int my_slot => client?.Slot ?? -1;

    public override void _Ready()
    {
        _view = GetNode<CourtView>("CourtView");
        _slotLabels = new[]
        {
            GetNode<Label>("HUD/Scores/Slot0Label"), GetNode<Label>("HUD/Scores/Slot1Label"),
            GetNode<Label>("HUD/Scores/Slot2Label"), GetNode<Label>("HUD/Scores/Slot3Label"),
        };
        _roundLabel = GetNode<Label>("HUD/RoundLabel");
        _statusLabel = GetNode<Label>("HUD/StatusLabel");
        _healthLabel = GetNode<Label>("HUD/HealthLabel");
        Options = LaunchOptions.FromCommandLine();
        Courts = Court.LoadAll();
        _view.Origin = CourtOrigin;
        _view.Colors = SlotColors;
        start_match();
    }

    /// <summary>A new local match: a fresh server with this player's client on the link.</summary>
    public void start_match()
    {
        long matchSeed = Options.MatchSeed(1);
        if (matchSeed == 0)
            matchSeed = 1 + GD.Randi() % 1000000;
        client = new ArenaClient(Courts);
        server = new ArenaServer(Courts, matchSeed);
        int delay = SimLink.TicksForMs(Options.LagMs);
        link = new SimLink(server, delay, Math.Max(delay / 4, 0), matchSeed);
        link.Join(client, LocalPeer);
        GD.Print($"[Run] match, seed {matchSeed}");
        _view.Client = client;
        RefreshHud();
    }

    public override void _PhysicsProcess(double delta)
    {
        SimInput input = ReadInput();
        if (client!.Step(input.Mx, input.My, input.Ax, input.Ay, input.Fire))
            OwnShot();
        link!.Pump();
        server!.Tick();
        link.Pump();
        link.Advance();
        TakeEvents();
        RefreshHud();
        _view.QueueRedraw();
    }

    private SimInput ReadInput()
    {
        var input = Sim.Idle();
        if (!client!.IsPlaying())
            return input;
        Vector2 move = Input.GetVector(MoveLeft, MoveRight, MoveUp, MoveDown);
        input.Mx = Bot.AxisSign(move.X, move.Y);
        input.My = Bot.AxisSign(move.Y, move.X);
        Vector2 aim = GetLocalMousePosition() - CourtOrigin - client.Predicted!.Position();
        input.Ax = (int)aim.X;
        input.Ay = (int)aim.Y;
        input.Fire = Input.IsActionPressed(FireAction);
        return input;
    }

    /// <summary>The player's own shot shows at once, from where their screen has everyone; the server's word on it comes later.</summary>
    private void OwnShot()
    {
        Shot shot = Sim.Trace(client!.View.Court, client.ShownFighters(), client.Slot);
        _view.AddBeam(client.Predicted!.Position(), new Vector2(shot.X, shot.Y), SlotColors[client.Slot]);
    }

    private void TakeEvents()
    {
        foreach (MatchEvent e in client!.Events)
        {
            switch (e.Type)
            {
                case "shot":
                    if (e.Slot != client.Slot)
                        _view.AddBeam(new Vector2(e.X, e.Y), new Vector2(e.Ex, e.Ey), SlotColors[e.Slot]);
                    break;
                case "hit":
                    _view.FlashFighter(e.Slot);
                    break;
                case "out":
                    _view.Pop(new Vector2(e.X, e.Y));
                    break;
            }
        }
        client.Events.Clear();
    }

    private void RefreshHud()
    {
        if (client == null || !IsNodeReady())
            return;
        ArenaMatch arena = client.View;
        for (int slot = 0; slot < ArenaMatch.Slots; slot++)
        {
            string key = slot == client.Slot ? "HUD_SLOT_YOU" : (arena.IsBot(slot) ? "HUD_SLOT_BOT" : "HUD_SLOT");
            _slotLabels[slot].Text = TextFormat.Fill(Tr(key), slot + 1, arena.Scores[slot]);
            _slotLabels[slot].Modulate = SlotColors[slot];
        }
        _roundLabel.Text = TextFormat.Fill(Tr("HUD_ROUND"), arena.RoundNumber);
        Fighter? me = client.Predicted;
        _healthLabel.Text = TextFormat.Fill(Tr("HUD_HEALTH"), me != null && me.Alive ? me.Hp : 0);
        _statusLabel.Text = arena.State switch
        {
            MatchState.Warmup => Tr("HUD_GET_READY"),
            MatchState.Over => TextFormat.Fill(Tr("HUD_OVER"), arena.Winner + 1),
            _ => me == null || !me.Alive ? Tr("HUD_WAIT") : "",
        };
    }
}
