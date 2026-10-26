namespace Cinderloop;

using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;
using static Cinderloop.Maths;

/// <summary>
/// One race on Ashfall Oval: the car on the keys against three AI rivals, the chase camera and a small HUD.
/// The race lives in Race; this node only counts down, feeds it the player's input once a physics tick and shows it.
/// After the flag it waits a moment and starts again.
/// </summary>
/// <remarks><c>track</c>, <c>state</c>, <c>race</c>, <c>lap</c>, <c>camera</c> and <c>start_track</c> keep the GDScript version's names.</remarks>
public partial class Game : Node2D
{
    public const int CountdownSeconds = 3;
    public const double RestartSeconds = 2.0;
    public const int Rivals = 3;

    private static readonly StringName AccelerateAction = "accelerate";
    private static readonly StringName BrakeAction = "brake";
    private static readonly StringName SteerLeftAction = "steer_left";
    private static readonly StringName SteerRightAction = "steer_right";

    private int _countdown;
    private int _restartIn = -1;
    private readonly List<CarView> _views = new();
    private Vector2 _playerBefore = Vector2.Zero;

    private TrackView _trackView = null!;
    private Node2D _cars = null!;
    private Label _trackLabel = null!;
    private Label _lapLabel = null!;
    private Label _timeLabel = null!;
    private Label _bestLabel = null!;
    private Label _countdownLabel = null!;

    public Tracks Tracks { get; private set; } = null!;

    public Race? race { get; private set; }

    public int track { get; private set; } = 1;

    /// <summary>"countdown", "racing" or "finished".</summary>
    public string state { get; set; } = "countdown";

    /// <summary>The lap the player is on, 1 to the track's laps.</summary>
    public int lap { get; private set; } = 1;

    public ChaseCamera camera { get; private set; } = null!;

    public override void _Ready()
    {
        _trackView = GetNode<TrackView>("Track");
        camera = GetNode<ChaseCamera>("Camera");
        _cars = GetNode<Node2D>("Cars");
        _trackLabel = GetNode<Label>("HUD/TrackLabel");
        _lapLabel = GetNode<Label>("HUD/LapLabel");
        _timeLabel = GetNode<Label>("HUD/TimeLabel");
        _bestLabel = GetNode<Label>("HUD/BestLabel");
        _countdownLabel = GetNode<Label>("HUD/CountdownLabel");
        Tracks = Tracks.FromFiles();
        start_track(track);
    }

    public void start_track(int id)
    {
        track = id;
        Track circuit = Tracks.Track(id);
        race = new Race(circuit, Tracks.DriversFor(Rivals, GD.Randi()), Engine.PhysicsTicksPerSecond);
        race.LapCompleted += OnLapCompleted;
        race.CarFinished += OnCarFinished;
        _trackView.ShowTrack(circuit);
        foreach (CarView view in _views)
        {
            _cars.RemoveChild(view);
            view.QueueFree();
        }
        _views.Clear();
        Color[] colours = { new("#f2c14e"), new("#e4572e"), new("#4c9f70"), new("#7b6ccf") };
        for (int i = 0; i < race.Cars.Count; i++)
        {
            var view = new CarView { Name = $"Car{i}", Color = colours[i % colours.Length] };
            _cars.AddChild(view);
            _views.Add(view);
        }
        SyncViews();
        state = "countdown";
        _countdown = CountdownSeconds * Engine.PhysicsTicksPerSecond;
        _restartIn = -1;
        lap = 1;
        _playerBefore = race.Cars[0].Position;
        camera.ResetTo(race.Cars[0].Position);
        UpdateHud();
    }

    public override void _PhysicsProcess(double delta)
    {
        if (race == null)
            return;
        if (state == "countdown")
        {
            _countdown -= 1;
            if (_countdown <= 0)
                state = "racing";
            UpdateHud();
            return;
        }
        _playerBefore = race.Cars[0].Position;
        race.Step(PlayerInput());
        SyncViews();
        if (_restartIn > 0)
        {
            _restartIn -= 1;
            if (_restartIn == 0)
            {
                start_track(track);
                return;
            }
        }
        UpdateHud();
    }

    private static Vector2 PlayerInput()
    {
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
            _views[i].Position = race!.Cars[i].Position;
            _views[i].Rotation = (float)race.Cars[i].Heading;
        }
    }

    private void OnLapCompleted(int car, int lapsDone, int ticks)
    {
        if (car != 0)
            return;
        GD.Print(string.Create(CultureInfo.InvariantCulture, $"[Run] track {track} lap {lapsDone} {ticks / (double)race!.Rate:F3}"));
        lap = Math.Min(lapsDone + 1, race.Track.Laps);
    }

    private void OnCarFinished(int car, int place)
    {
        if (car != 0)
            return;
        state = "finished";
        race!.Drivers[0] = new AiDriver(0.6);
        _restartIn = (int)(RestartSeconds * race.Rate);
    }

    private void UpdateHud()
    {
        _trackLabel.Text = "Ashfall Oval";
        _lapLabel.Text = $"Lap {lap}/{race!.Track.Laps}";
        LapTracker tracker = race.Trackers[0];
        int running = state == "countdown" ? 0 : race.Tick - tracker.LapStartTick;
        _timeLabel.Text = $"Lap {Race.FormatMs(RoundI(running * 1000.0 / race.Rate))}";
        _bestLabel.Text = $"Best {(tracker.BestLap >= 0 ? Race.FormatMs(RoundI(tracker.BestLap * 1000.0 / race.Rate)) : "-")}";
        if (state == "countdown")
            _countdownLabel.Text = ((int)Math.Ceiling(_countdown / (double)Engine.PhysicsTicksPerSecond)).ToString(CultureInfo.InvariantCulture);
        else if (state == "finished")
            _countdownLabel.Text = "Finished";
        else
            _countdownLabel.Text = race.Tick < Engine.PhysicsTicksPerSecond ? "GO!" : "";
    }
}
