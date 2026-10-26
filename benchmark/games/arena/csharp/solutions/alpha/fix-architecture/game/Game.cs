namespace Glimmerpit;

using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;

/// <summary>
/// One match in the pit, seen from a player's seat: the court, the HUD, pause and the result panel. Main starts it with
/// Setup(); on its own (a flow, a test, the editor) it plays a local match against three bots.
/// The rules live in ArenaMatch and the netcode in ArenaServer and ArenaClient; this node only ticks them, reads the
/// player's input and shows what the client knows. In a local or hosted match the server runs here too, and the
/// player's client reaches it over a SimLink (with --lag=MS of simulated round trip); a joined match reaches a server
/// over ENet through a NetSession. Everything runs in _PhysicsProcess at 30 ticks a second.
/// </summary>
/// <remarks>
/// <c>mode</c>, <c>server</c>, <c>link</c>, <c>client</c>, <c>state</c>, <c>round_number</c>, <c>my_slot</c>,
/// <c>start_match</c> and <c>rematch</c> keep the names the UI flows and the GDScript version use: the flows are shared,
/// word for word.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>The local player's peer id on the in-process link (ENet peers have their own, larger ids).</summary>
    public const int LocalPeer = 1;
    /// <summary>How long a bot run shows the finished match before it quits.</summary>
    public const int AutoplayQuitTicks = 60;
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
    private static readonly StringName AimLeft = "aim_left";
    private static readonly StringName AimRight = "aim_right";
    private static readonly StringName AimUp = "aim_up";
    private static readonly StringName AimDown = "aim_down";
    private static readonly StringName FireAction = "fire";
    private static readonly StringName DashAction = "dash";

    private int _ticks;
    private int _quitIn = -1;
    private bool _reported;
    private float _shake;
    private float _flash;
    /// <summary>Cosmetic only (the camera's shake): never the match's.</summary>
    private readonly RandomNumberGenerator _rng = new();

    private CourtView _view = null!;
    private Camera2D _camera = null!;
    private Label[] _slotLabels = null!;
    private Label _roundLabel = null!;
    private Label _statusLabel = null!;
    private Label _healthLabel = null!;
    private Button _pauseButton = null!;
    private ColorRect _flashRect = null!;
    private PauseMenu _pauseMenu = null!;
    private ResultMenu _resultMenu = null!;
    private AudioStreamPlayer _sfxShot = null!;
    private AudioStreamPlayer _sfxHit = null!;
    private AudioStreamPlayer _sfxOut = null!;
    private AudioStreamPlayer _sfxRound = null!;

    /// <summary>The match ended for this player: Main records it.</summary>
    public event Action<bool>? MatchOver;
    public event Action? MenuRequested;

    /// <summary>"local", "host" or "join".</summary>
    public string mode { get; private set; } = "local";
    public LaunchOptions Options { get; private set; } = null!;
    public List<Court> Courts { get; private set; } = new();
    public ArenaServer? server { get; private set; }
    public SimLink? link { get; private set; }
    public ArenaClient? client { get; private set; }
    public NetSession? session { get; private set; }
    public int matches { get; private set; }

    /// <summary>"warmup", "round", "intermission" or "over", as this player's client knows it.</summary>
    public string state => client?.View.StateName() ?? "";

    public int round_number => client?.View.RoundNumber ?? 0;

    public int my_slot => client?.Slot ?? -1;

    public void Setup(string gameMode, LaunchOptions options, NetSession? netSession = null, List<Court>? courts = null)
    {
        mode = gameMode;
        Options = options;
        session = netSession;
        Courts = courts ?? new List<Court>();
    }

    public override void _Ready()
    {
        _view = GetNode<CourtView>("CourtView");
        _camera = GetNode<Camera2D>("Camera");
        _slotLabels = new[]
        {
            GetNode<Label>("HUD/Scores/Slot0Label"), GetNode<Label>("HUD/Scores/Slot1Label"),
            GetNode<Label>("HUD/Scores/Slot2Label"), GetNode<Label>("HUD/Scores/Slot3Label"),
        };
        _roundLabel = GetNode<Label>("HUD/RoundLabel");
        _statusLabel = GetNode<Label>("HUD/StatusLabel");
        _healthLabel = GetNode<Label>("HUD/HealthLabel");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _flashRect = GetNode<ColorRect>("HUD/Flash");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _resultMenu = GetNode<ResultMenu>("ResultMenu");
        _sfxShot = GetNode<AudioStreamPlayer>("SfxShot");
        _sfxHit = GetNode<AudioStreamPlayer>("SfxHit");
        _sfxOut = GetNode<AudioStreamPlayer>("SfxOut");
        _sfxRound = GetNode<AudioStreamPlayer>("SfxRound");

        Options ??= LaunchOptions.FromCommandLine();
        if (Courts.Count == 0)
            Courts = Court.LoadAll();
        _view.Origin = CourtOrigin;
        _view.Colors = SlotColors;
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.PausesTree = mode == "local";
        _pauseMenu.QuitPressed += Leave;
        _resultMenu.RematchPressed += rematch;
        _resultMenu.MenuPressed += Leave;
        RefreshText();
        start_match();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _pauseButton.Text = Tr("HUD_PAUSE");
        RefreshHud();
    }

    /// <summary>A new match with the run's next seed.</summary>
    public void start_match() => start_match(0);

    /// <summary>
    /// A new match: in a local or hosted one, a fresh server with this player's client on the link; a joined one asks the
    /// session's server. seedValue 0 takes the run's next seed.
    /// </summary>
    public void start_match(long seedValue)
    {
        matches++;
        long matchSeed = seedValue > 0 ? seedValue : Options.MatchSeed(matches);
        if (matchSeed == 0)
            matchSeed = 1 + GD.Randi() % 1000000;
        _rng.Seed = unchecked((ulong)matchSeed);
        _reported = false;
        _resultMenu.Close();
        client = new ArenaClient(Courts);
        if (mode == "join")
        {
            session!.JoinWith(client);
        }
        else
        {
            server = new ArenaServer(Courts, matchSeed);
            int delay = SimLink.TicksForMs(Options.LagMs);
            link = new SimLink(server, delay, Math.Max(delay / 4, 0), matchSeed);
            if (mode == "host")
                session!.Serve(server, link);
            link.Join(client, LocalPeer);
            GD.Print($"[Run] match {matches}, seed {matchSeed}");
        }
        _view.Client = client;
        RefreshHud();
    }

    /// <summary>Plays again after a match: a new local match, or the hosted server's next one. A joined player follows its host.</summary>
    public void rematch()
    {
        if (state != "over")
            return;
        if (mode == "local")
        {
            start_match();
        }
        else if (mode == "host")
        {
            server!.Arena.Restart();
            _reported = false;
            _resultMenu.Close();
        }
    }

    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    public override void _PhysicsProcess(double delta)
    {
        _ticks++;
        UpdateEffects(delta);
        SimInput input = ReadInput();
        if (client!.Step(input.Mx, input.My, input.Ax, input.Ay, input.Fire, input.Dash))
            OwnShot();
        if (link != null)
        {
            link.Pump();
            server!.Tick();
            link.Pump();
            link.Advance();
        }
        TakeEvents();
        RefreshHud();
        _view.QueueRedraw();
        if (_quitIn > 0)
        {
            _quitIn--;
            if (_quitIn == 0)
                GetTree().Quit();
        }
    }

    private SimInput ReadInput()
    {
        var input = Sim.Idle();
        if (GetTree().Paused || !client!.IsPlaying())
            return input;
        Vector2 move = Input.GetVector(MoveLeft, MoveRight, MoveUp, MoveDown);
        input.Mx = Bot.AxisSign(move.X, move.Y);
        input.My = Bot.AxisSign(move.Y, move.X);
        Vector2 stick = Input.GetVector(AimLeft, AimRight, AimUp, AimDown);
        Vector2 aim = stick.Length() > 0.3f ? stick * 100.0f : GetLocalMousePosition() - CourtOrigin - client.Predicted!.Position();
        input.Ax = (int)aim.X;
        input.Ay = (int)aim.Y;
        input.Fire = Input.IsActionPressed(FireAction);
        input.Dash = Input.IsActionJustPressed(DashAction);
        return input;
    }

    /// <summary>The player's own shot shows at once, from where their screen has everyone; the server's word on it comes later.</summary>
    private void OwnShot()
    {
        Shot shot = Sim.Trace(client!.View.Court, client.ShownFighters(), client.Slot);
        ShowShot(client.Predicted!.X, client.Predicted.Y, shot.X, shot.Y, client.Slot);
    }

    private void TakeEvents()
    {
        foreach (MatchEvent e in client!.Events)
        {
            switch (e.Type)
            {
                case "shot":
                    if (e.Slot != client.Slot)
                        ShowShot(e.X, e.Y, e.Ex, e.Ey, e.Slot);
                    break;
                case "hit":
                    LogEvent("player_hit");
                    _view.FlashFighter(e.Slot);
                    LogFeedback("flash");
                    if (e.Slot == client.Slot)
                    {
                        _flash = 0.35f;
                        _flashRect.Color = new Color(1.0f, 0.25f, 0.2f, _flash);
                    }
                    Play(_sfxHit);
                    break;
                case "out":
                    LogEvent("player_out");
                    _view.Pop(new Vector2(e.X, e.Y));
                    LogFeedback("pop");
                    ShakeCamera(10.0f);
                    Play(_sfxOut);
                    break;
                case "round":
                    _sfxRound.Play();
                    break;
                case "over":
                    Over(e.Winner);
                    break;
            }
        }
        client.Events.Clear();
    }

    private void ShowShot(int x, int y, int ex, int ey, int slot)
    {
        LogEvent("shot_fired");
        _view.AddBeam(new Vector2(x, y), new Vector2(ex, ey), SlotColors[slot]);
        Play(_sfxShot);
    }

    private void Over(int winner)
    {
        if (_reported)
            return;
        _reported = true;
        bool won = winner == client!.Slot;
        GD.Print($"[Run] match over, {(won ? "won" : "lost")}");
        MatchOver?.Invoke(won);
        if (Options.Autoplay)
        {
            // On its own (a flow, or the game scene run alone) nobody listens; a bot run then ends here. Main ends its own.
            if (MatchOver == null)
                _quitIn = AutoplayQuitTicks;
        }
        else
        {
            int[] scores = client.View.Scores;
            int second = 0;
            for (int slot = 0; slot < ArenaMatch.Slots; slot++)
            {
                if (slot != winner)
                    second = Math.Max(second, scores[slot]);
            }
            _resultMenu.Open(won, winner + 1, scores[winner], second, mode != "join");
        }
    }

    private void Leave()
    {
        MenuRequested?.Invoke();
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
        _statusLabel.Text = StatusText(arena, me);
    }

    private string StatusText(ArenaMatch arena, Fighter? me)
    {
        if (!client!.IsPlaying())
            return client.Full ? Tr("HUD_FULL") : Tr("HUD_CONNECTING");
        switch (arena.State)
        {
            case MatchState.Warmup:
                return Tr("HUD_GET_READY");
            case MatchState.Over:
                return TextFormat.Fill(Tr("HUD_OVER"), arena.Winner + 1);
        }
        if (arena.State == MatchState.Round && (me == null || !me.Alive))
            return Tr("HUD_WAIT");
        return arena.IsMatchPoint() ? Tr("HUD_MATCH_POINT") : "";
    }

    // Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
    private void LogEvent(string eventName)
    {
        GD.Print($"[juice] event {eventName} {GameMs().ToString("F1", CultureInfo.InvariantCulture)}");
    }

    private void LogFeedback(string kind)
    {
        GD.Print($"[juice] feedback {kind} {GameMs().ToString("F1", CultureInfo.InvariantCulture)}");
    }

    private void ShakeCamera(float amount)
    {
        _shake = amount;
        LogFeedback("shake");
    }

    private void Play(AudioStreamPlayer player)
    {
        player.Play();
        LogFeedback("sfx");
    }

    private void UpdateEffects(double delta)
    {
        _flash = Math.Max(_flash - (float)delta * 2.0f, 0.0f);
        Color flashColor = _flashRect.Color;
        flashColor.A = _flash;
        _flashRect.Color = flashColor;
        _shake = Math.Max(_shake - (float)delta * 40.0f, 0.0f);
        _camera.Offset = _shake > 0.0f ? new Vector2(_rng.RandfRange(-_shake, _shake), _rng.RandfRange(-_shake, _shake)) : Vector2.Zero;
    }
}
