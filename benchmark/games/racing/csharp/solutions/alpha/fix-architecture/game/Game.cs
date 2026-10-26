namespace Cinderloop;

using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;
using static Cinderloop.Maths;

/// <summary>
/// One race: the track, the cars, the ghost of the best lap, the chase camera, the HUD, pause and the result panel.
/// Main starts it with Setup(); on its own (a flow, a test, the editor) it reads the command line and the data itself.
/// The race lives in Race; this node only counts down, feeds it the player's input once a physics tick and shows it.
/// </summary>
/// <remarks>
/// <c>track</c>, <c>state</c>, <c>race</c>, <c>place</c>, <c>lap</c>, <c>camera</c> and the methods <c>start_track</c>,
/// <c>restart</c> and <c>next_track</c> keep the names the UI flows and the GDScript version use: the flows are shared,
/// word for word.
/// </remarks>
public partial class Game : Node2D
{
    public const int CountdownSeconds = 3;
    /// <summary>A place this good or better opens the next track.</summary>
    public const int TopPlaces = 2;
    /// <summary>How long the finish shows before the result panel (and, in a bot run, the next race).</summary>
    public const double ResultSeconds = 1.0;

    private static readonly StringName AccelerateAction = "accelerate";
    private static readonly StringName BrakeAction = "brake";
    private static readonly StringName SteerLeftAction = "steer_left";
    private static readonly StringName SteerRightAction = "steer_right";

    private bool _bot;
    private int _races;
    private long _raceSeed;
    private int _ticks;
    private int _countdown;
    private int _resultIn = -1;
    private readonly List<CarView> _views = new();
    /// <summary>Where the player's car was before the last tick, for the camera between ticks.</summary>
    private Vector2 _playerBefore = Vector2.Zero;
    private Ghost? _ghost;
    private Car? _ghostCar;
    private int _ghostTick;
    private float _flash;
    private float _popLap;
    private float _popPlace;

    private TrackView _trackView = null!;
    private Node2D _cars = null!;
    private CarView _ghostView = null!;
    private Label _trackLabel = null!;
    private Label _lapLabel = null!;
    private Label _placeLabel = null!;
    private Label _timeLabel = null!;
    private Label _bestLabel = null!;
    private Label _countdownLabel = null!;
    private Button _pauseButton = null!;
    private ColorRect _flashRect = null!;
    private PauseMenu _pauseMenu = null!;
    private ResultMenu _resultMenu = null!;
    private AudioStreamPlayer _sfxGo = null!;
    private AudioStreamPlayer _sfxLap = null!;
    private AudioStreamPlayer _sfxPass = null!;

    /// <summary>The player took the flag: Main records the place and the best lap (track, place, best lap in ms, its ghost).</summary>
    public event Action<int, int, int, Ghost?>? RaceFinished;
    /// <summary>The run is over: victory after the last track.</summary>
    public event Action<bool>? Finished;
    public event Action? MenuRequested;

    public Tracks Tracks { get; private set; } = null!;
    public LaunchOptions Options { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();

    public Race? race { get; private set; }

    public int track { get; private set; } = 1;

    /// <summary>"countdown", "racing" or "finished".</summary>
    public string state { get; set; } = "countdown";

    /// <summary>The player's place, 1 for the lead.</summary>
    public int place { get; private set; }

    /// <summary>The lap the player is on, 1 to the track's laps.</summary>
    public int lap { get; private set; } = 1;

    public ChaseCamera camera { get; private set; } = null!;

    public void Setup(Tracks tracks, LaunchOptions options, SaveData save)
    {
        Tracks = tracks;
        Options = options;
        Save = save;
    }

    public override void _Ready()
    {
        _trackView = GetNode<TrackView>("Track");
        camera = GetNode<ChaseCamera>("Camera");
        _cars = GetNode<Node2D>("Cars");
        _ghostView = GetNode<CarView>("Ghost");
        _trackLabel = GetNode<Label>("HUD/TrackLabel");
        _lapLabel = GetNode<Label>("HUD/LapLabel");
        _placeLabel = GetNode<Label>("HUD/PositionLabel");
        _timeLabel = GetNode<Label>("HUD/TimeLabel");
        _bestLabel = GetNode<Label>("HUD/BestLabel");
        _countdownLabel = GetNode<Label>("HUD/CountdownLabel");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _flashRect = GetNode<ColorRect>("HUD/Flash");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _resultMenu = GetNode<ResultMenu>("ResultMenu");
        _sfxGo = GetNode<AudioStreamPlayer>("SfxGo");
        _sfxLap = GetNode<AudioStreamPlayer>("SfxLap");
        _sfxPass = GetNode<AudioStreamPlayer>("SfxPass");

        Options ??= LaunchOptions.FromCommandLine();
        Tracks ??= Tracks.FromFiles();
        _ghostView.Ghost = true;
        _ghostView.Color = new Color(1, 1, 1, 0.6f);
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.RestartPressed += restart;
        _pauseMenu.QuitPressed += () => MenuRequested?.Invoke();
        _resultMenu.NextPressed += next_track;
        _resultMenu.RetryPressed += restart;
        _resultMenu.MenuPressed += () => MenuRequested?.Invoke();
        RefreshText();
        start_track(Options.Track);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _pauseButton.Text = Tr("HUD_PAUSE");
        UpdateHud();
    }

    /// <summary>A new race on a track, with the run's next seed.</summary>
    /// <remarks>An overload, not a default argument: the engine (a flow's call step) calls a C# method only with all its arguments.</remarks>
    public void start_track(int id) => start_track(id, -1);

    /// <summary>A new race on a track; seed -1 takes the run's next seed.</summary>
    public void start_track(int id, long seed)
    {
        if (!Tracks.HasTrack(id))
        {
            GD.PushError($"There is no track {id}");
            return;
        }
        track = id;
        long raceSeed = seed >= 0 ? seed : NextSeed();
        GD.Print($"[Run] track {id}, seed {raceSeed}");
        Track circuit = Tracks.Track(id);
        race = new Race(circuit, Tracks.DriversFor(Options.Rivals, raceSeed, _bot), Engine.PhysicsTicksPerSecond);
        _raceSeed = raceSeed;
        race.LapCompleted += OnLapCompleted;
        race.CarFinished += OnCarFinished;
        _trackView.ShowTrack(circuit);
        MakeViews();
        _ghost = Ghost.FromDict(Save.Ghosts.TryGetValue(Key(id), out var saved) ? saved : null);
        RestartGhost();
        state = "countdown";
        _countdown = CountdownSeconds * Engine.PhysicsTicksPerSecond;
        _resultIn = -1;
        lap = 1;
        place = race.PositionOf(0);
        _resultMenu.Close();
        _playerBefore = race.Cars[0].Position;
        camera.ResetTo(race.Cars[0].Position);
        UpdateHud();
    }

    /// <summary>The run's seeds: from --seed, one per race in order, so a bot run replays; at random without it.</summary>
    private long NextSeed()
    {
        _races += 1;
        if (Options.RunSeed > 0)
            return Options.RunSeed * 1009 + _races;
        return GD.Randi() % 1000000;
    }

    public void restart() => start_track(track);

    public void next_track()
    {
        if (Tracks.HasTrack(track + 1))
        {
            start_track(track + 1);
            return;
        }
        GD.Print("[Run] victory");
        Finished?.Invoke(true);
        if (_bot && Finished == null)
            GetTree().Quit();
    }

    /// <summary>Game time in milliseconds: physics ticks, never the wall clock.</summary>
    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    private static string Key(int id) => id.ToString(CultureInfo.InvariantCulture);

    private void MakeViews()
    {
        foreach (CarView view in _views)
        {
            _cars.RemoveChild(view);
            view.QueueFree();
        }
        _views.Clear();
        var colours = new List<string> { "#f2c14e" };
        foreach (int k in Tracks.GridOrder(race!.Cars.Count - 1, _raceSeed))
            colours.Add(Tracks.Rivals[k].Color);
        for (int i = 0; i < race.Cars.Count; i++)
        {
            var view = new CarView
            {
                Name = $"Car{i}",
                Color = i < colours.Count ? new Color(colours[i]) : Colors.Gray,
            };
            _cars.AddChild(view);
            _views.Add(view);
        }
        SyncViews();
        foreach (CarView view in _views)
            view.ResetPhysicsInterpolation();
    }

    public override void _PhysicsProcess(double delta)
    {
        _ticks += 1;
        UpdateEffects(1.0f / Engine.PhysicsTicksPerSecond);
        if (race == null)
            return;
        if (state == "countdown")
        {
            _countdown -= 1;
            if (_countdown <= 0)
            {
                state = "racing";
                Event("race_start");
                FlashScreen(new Color(1, 1, 1, 0.35f));
                Play(_sfxGo);
            }
            UpdateHud();
            return;
        }
        _playerBefore = race.Cars[0].Position;
        race.Step(PlayerInput());
        SyncViews();
        StepGhost();
        int now = race.PositionOf(0);
        if (state == "racing" && now < place)
            GainedPlace();
        place = now;
        if (_resultIn > 0)
        {
            _resultIn -= 1;
            if (_resultIn == 0)
                ShowResult();
        }
        UpdateHud();
    }

    private Vector2 PlayerInput()
    {
        if (_bot || race!.IsFinished(0))
            return Vector2.Zero;
        double throttle = (double)Input.GetActionStrength(AccelerateAction) - Input.GetActionStrength(BrakeAction);
        return new Vector2((float)throttle, Input.GetAxis(SteerLeftAction, SteerRightAction));
    }

    public override void _Process(double delta)
    {
        if (race == null)
            return;
        // Between two ticks, where the car is drawn: physics interpolation's fraction of the way from the last tick.
        Vector2 drawn = _playerBefore.Lerp(race.Cars[0].Position, (float)Engine.GetPhysicsInterpolationFraction());
        camera.Follow(drawn, race.Cars[0].Velocity(), delta);
    }

    private void SyncViews()
    {
        for (int i = 0; i < _views.Count; i++)
        {
            Car car = race!.Cars[i];
            _views[i].Position = car.Position;
            _views[i].Rotation = (float)car.Heading;
        }
    }

    private void RestartGhost()
    {
        _ghostTick = 0;
        _ghostCar = null;
        if (_ghost != null && _ghost.Rate == Engine.PhysicsTicksPerSecond && _ghost.Ticks() > 0)
        {
            _ghostCar = _ghost.StartCar();
            _ghostCar.Index = race!.Track.Nearest(_ghostCar.Position);
        }
        _ghostView.Visible = _ghostCar != null;
        PlaceGhost();
    }

    private void StepGhost()
    {
        if (_ghostCar == null || _ghost == null)
            return;
        if (_ghostTick >= _ghost.Ticks())
        {
            _ghostView.Visible = false;
            return;
        }
        _ghost.Drive(_ghostCar, _ghostTick, race!.Track);
        _ghostTick += 1;
        PlaceGhost();
    }

    private void PlaceGhost()
    {
        if (_ghostCar == null)
            return;
        _ghostView.Position = _ghostCar.Position;
        _ghostView.Rotation = (float)_ghostCar.Heading;
        if (_ghostTick == 0)
            _ghostView.ResetPhysicsInterpolation();
    }

    private void OnLapCompleted(int car, int lapsDone, int ticks)
    {
        if (car != 0)
            return;
        GD.Print(string.Create(CultureInfo.InvariantCulture, $"[Run] track {track} lap {lapsDone} {ticks / (double)race!.Rate:F3}"));
        Event("lap_completed");
        _popLap = 0.4f;
        Feedback("pop");
        Play(_sfxLap);
        lap = Math.Min(lapsDone + 1, race.Track.Laps);
        // The ghost to chase is the best lap there is: this race's, once it beats the saved one.
        if (_ghost == null || race.BestGhost!.Ticks() < _ghost.Ticks() || _ghost.Rate != race.Rate)
            _ghost = race.BestGhost;
        RestartGhost();
    }

    private void OnCarFinished(int car, int finishedPlace)
    {
        if (car != 0)
            return;
        state = "finished";
        place = finishedPlace;
        int total = 0;
        foreach (int t in race!.Trackers[0].LapTimes)
            total += t;
        GD.Print(string.Create(CultureInfo.InvariantCulture, $"[Run] track {track} finished P{finishedPlace} {total / (double)race.Rate:F3}"));
        // The player's car drives on by itself, slowly, behind the result.
        race.Drivers[0] = new AiDriver(0.6);
        _resultIn = (int)(ResultSeconds * race.Rate);
        int bestMs = RoundI(race.Trackers[0].BestLap * 1000.0 / race.Rate);
        RaceFinished?.Invoke(track, finishedPlace, bestMs, race.BestGhost);
    }

    private void ShowResult()
    {
        bool opensNext = place <= TopPlaces;
        if (_bot)
        {
            if (opensNext)
                next_track();
            else
                start_track(track);
            return;
        }
        int bestMs = RoundI(race!.Trackers[0].BestLap * 1000.0 / race.Rate);
        _resultMenu.Open(place, race.Cars.Count, bestMs, opensNext);
    }

    private void GainedPlace()
    {
        Event("position_gained");
        _popPlace = 0.4f;
        Feedback("pop");
        Play(_sfxPass);
    }

    private void UpdateHud()
    {
        if (race == null)
            return;
        _trackLabel.Text = Tr(race.Track.NameKey);
        _lapLabel.Text = TextFormat.Fill(Tr("HUD_LAP"), lap, race.Track.Laps);
        _placeLabel.Text = TextFormat.Fill(Tr("HUD_POSITION"), place, race.Cars.Count);
        LapTracker tracker = race.Trackers[0];
        int running = state == "countdown" ? 0 : race.Tick - tracker.LapStartTick;
        _timeLabel.Text = TextFormat.Fill(Tr("HUD_TIME"), Race.FormatMs(RoundI(running * 1000.0 / race.Rate)));
        int best = Save.Best.TryGetValue(Key(track), out int saved) ? saved : -1;
        if (tracker.BestLap >= 0)
        {
            int thisRace = RoundI(tracker.BestLap * 1000.0 / race.Rate);
            best = best < 0 ? thisRace : Math.Min(best, thisRace);
        }
        _bestLabel.Text = TextFormat.Fill(Tr("HUD_BEST"), best >= 0 ? Race.FormatMs(best) : "-");
        if (state == "countdown")
        {
            _countdownLabel.Visible = true;
            _countdownLabel.Text = ((int)Math.Ceiling(_countdown / (double)Engine.PhysicsTicksPerSecond)).ToString(CultureInfo.InvariantCulture);
        }
        else
        {
            _countdownLabel.Visible = race.Tick < Engine.PhysicsTicksPerSecond;
            _countdownLabel.Text = Tr("HUD_GO");
        }
    }

    // Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
    private void Event(string eventName)
    {
        GD.Print(string.Create(CultureInfo.InvariantCulture, $"[juice] event {eventName} {GameMs():F1}"));
    }

    private void Feedback(string kind)
    {
        GD.Print(string.Create(CultureInfo.InvariantCulture, $"[juice] feedback {kind} {GameMs():F1}"));
    }

    private void FlashScreen(Color color)
    {
        _flash = color.A;
        _flashRect.Color = color;
        Feedback("flash");
    }

    private void Play(AudioStreamPlayer sound)
    {
        sound.Play();
        Feedback("sfx");
    }

    private void UpdateEffects(float delta)
    {
        _flash = Mathf.Max(_flash - delta * 2f, 0f);
        _flashRect.Color = _flashRect.Color with { A = _flash };
        _popLap = Mathf.Max(_popLap - delta * 2f, 0f);
        _lapLabel.Scale = Vector2.One * (1f + _popLap);
        _popPlace = Mathf.Max(_popPlace - delta * 2f, 0f);
        _placeLabel.Scale = Vector2.One * (1f + _popPlace);
    }
}
