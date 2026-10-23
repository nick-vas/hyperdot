namespace Lanternfen;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json.Nodes;
using Godot;

/// <summary>
/// One duel against a rival on the table: the hand, the HUD, pause and the result panel. Main starts it with Setup(); on
/// its own (a flow, a test, the editor) it reads the command line and the data itself.
/// The rules live in Duel; this node only paces them. Each Draw, Clash strike and End waits a few ticks so it can be
/// seen, the rival's AI thinks before each play, and the player's Main phase waits for a card or End turn. Everything
/// runs in _PhysicsProcess at 60 ticks, so a bot run replays the same on every machine.
/// </summary>
/// <remarks>
/// <c>rival</c>, <c>state</c>, <c>phase</c>, <c>active</c>, <c>turn</c>, <c>suggested</c>, <c>suggest_checks</c> and the
/// methods <c>start_rival</c>, <c>resume</c>, <c>play_card</c>, <c>end_turn</c>, <c>next_rival</c> and <c>rematch</c> keep
/// the names the UI flows and the GDScript version use: the flows are shared, word for word.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>Ticks a Draw, the end of a Main phase or an End takes on screen.</summary>
    public const int PhaseTicks = 8;
    /// <summary>Ticks between two strikes of a Clash: more than the juice window, so each strike's feedback is its own.</summary>
    public const int StrikeTicks = 9;
    /// <summary>Ticks an AI thinks before each play.</summary>
    public const int ThinkTicks = 10;
    /// <summary>How long a bot run shows a finished duel before the next one.</summary>
    public const int AutoplayNextTicks = 40;
    /// <summary>The translation keys of Duel's phases, in Phase order, and of what each rite does.</summary>
    private static readonly string[] PhaseKeys = { "PHASE_DRAW", "PHASE_MAIN", "PHASE_CLASH", "PHASE_END", "PHASE_OVER" };
    private static readonly Dictionary<string, string> EffectKeys = new()
    {
        ["bolt"] = "EFFECT_BOLT",
        ["mend"] = "EFFECT_MEND",
        ["draw"] = "EFFECT_DRAW",
        ["douse"] = "EFFECT_DOUSE",
        ["rekindle"] = "EFFECT_REKINDLE",
    };
    private static readonly StringName EndTurnAction = "end_turn";
    private static readonly Color SuggestedTint = new(1f, 0.92f, 0.55f);

    /// <summary>A duel ended: Main records it on the ladder.</summary>
    public event Action<int, bool>? DuelOver;
    /// <summary>The player's Main phase began: Main keeps this duel in the save, for Continue.</summary>
    public event Action<JsonObject>? Checkpoint;
    /// <summary>The run is over: victory after the last rival.</summary>
    public event Action<bool>? Finished;
    public event Action? MenuRequested;

    private int _firstRival;
    private JsonObject? _saved;
    private Ai _rivalAi = new();
    private readonly Ai _hintAi = new();
    /// <summary>The player's seat played by the AI too, with --autoplay.</summary>
    private Ai? _bot;
    private int _duels;
    private int _ticks;
    private int _wait;
    private int _nextIn = -1;
    private float _shake;
    private float _flash;
    private readonly RandomNumberGenerator _rng = new();

    private Camera2D _camera = null!;
    private Label _rivalLabel = null!;
    private Label _rivalLight = null!;
    private Label _playerLight = null!;
    private Label _kindlingLabel = null!;
    private Label _turnLabel = null!;
    private HBoxContainer _hand = null!;
    private Button _endTurn = null!;
    private Button _pauseButton = null!;
    private ColorRect _flashRect = null!;
    private PauseMenu _pauseMenu = null!;
    private ResultMenu _resultMenu = null!;
    private AudioStreamPlayer _sfxPlay = null!;
    private AudioStreamPlayer _sfxHit = null!;
    private AudioStreamPlayer _sfxFall = null!;
    private AudioStreamPlayer _sfxWin = null!;

    public Rivals Rivals { get; private set; } = null!;
    public Cards Cards { get; private set; } = null!;
    public LaunchOptions Options { get; private set; } = null!;
    public Table Table { get; private set; } = null!;

    public Duel? duel { get; private set; }

    public int rival { get; private set; } = 1;

    /// <summary>"playing", "over" (the result is shown) or "done".</summary>
    public string state { get; private set; } = "playing";

    /// <summary>The card of the hand the player's AI would play: the HUD marks it. -1 when there is none.</summary>
    public int suggested { get; private set; } = -1;

    /// <summary>How many times the game asked the AI for a suggestion, for the performance test.</summary>
    public int suggest_checks { get; private set; }

    public string phase => duel?.PhaseName ?? "";

    public int active => duel?.Active ?? 0;

    public int turn => duel?.Turn ?? 0;

    /// <summary>firstRival: the rival to face (the command line's --rival when 0); saved: a duel from the save to carry on instead.</summary>
    public void Setup(Rivals rivals, Cards cards, LaunchOptions options, int firstRival = 0, JsonObject? saved = null)
    {
        Rivals = rivals;
        Cards = cards;
        Options = options;
        _firstRival = firstRival;
        _saved = saved;
    }

    public override void _Ready()
    {
        Table = GetNode<Table>("Table");
        _camera = GetNode<Camera2D>("Camera");
        _rivalLabel = GetNode<Label>("HUD/RivalLabel");
        _rivalLight = GetNode<Label>("HUD/RivalLight");
        _playerLight = GetNode<Label>("HUD/PlayerLight");
        _kindlingLabel = GetNode<Label>("HUD/KindlingLabel");
        _turnLabel = GetNode<Label>("HUD/TurnLabel");
        _hand = GetNode<HBoxContainer>("HUD/Hand");
        _endTurn = GetNode<Button>("HUD/EndTurnButton");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _flashRect = GetNode<ColorRect>("HUD/Flash");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _resultMenu = GetNode<ResultMenu>("ResultMenu");
        _sfxPlay = GetNode<AudioStreamPlayer>("SfxPlay");
        _sfxHit = GetNode<AudioStreamPlayer>("SfxHit");
        _sfxFall = GetNode<AudioStreamPlayer>("SfxFall");
        _sfxWin = GetNode<AudioStreamPlayer>("SfxWin");

        Options ??= LaunchOptions.FromCommandLine();
        Rivals ??= Rivals.FromFiles();
        Cards ??= Cards.FromFile();
        _rng.Seed = (ulong)Options.RunSeed;
        if (Options.Autoplay)
            _bot = new Ai();
        _endTurn.Pressed += end_turn;
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => MenuRequested?.Invoke();
        _resultMenu.NextPressed += next_rival;
        _resultMenu.RematchPressed += rematch;
        _resultMenu.MenuPressed += () => MenuRequested?.Invoke();
        RefreshText();
        if (_saved != null)
            resume(_saved);
        else
            start_rival(_firstRival > 0 ? _firstRival : Options.Rival);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _endTurn.Text = Tr("HUD_END_TURN");
        _pauseButton.Text = Tr("HUD_PAUSE");
        Refresh();
    }

    /// <summary>A new duel against a rival; seed -1 takes the run's next seed.</summary>
    public void start_rival(int id, long seed = -1)
    {
        if (!Rivals.HasRival(id))
        {
            GD.PushError($"There is no rival {id}");
            return;
        }
        rival = id;
        long duelSeed = seed >= 0 ? seed : NextSeed();
        GD.Print($"[Run] rival {id}, seed {duelSeed}");
        Begin(Rivals.StartDuel(Cards, id, duelSeed));
    }

    /// <summary>Carries on a duel kept in the save (Duel.ToDict plus "rival").</summary>
    public void resume(JsonObject data)
    {
        rival = JsonData.Int(data["rival"], 1);
        if (!Rivals.HasRival(rival))
            rival = 1;
        Begin(Duel.FromDict(Cards, data));
        if (duel!.Phase == Phase.Main && duel.Active == 0)
            Suggest();
    }

    private void Begin(Duel next)
    {
        duel = next;
        duel.PhaseChanged += OnPhaseChanged;
        duel.CardPlayed += OnCardPlayed;
        duel.KeeperHit += OnKeeperHit;
        duel.WispFell += OnWispFell;
        _rivalAi = Rivals.AiFor(rival);
        state = "playing";
        suggested = -1;
        _wait = PhaseTicks;
        _nextIn = -1;
        _resultMenu.Close();
        Table.ShowDuel(duel, Cards);
        Refresh();
    }

    /// <summary>The run's seeds: from --seed, one per duel in order, so a bot run replays; at random without it.</summary>
    private long NextSeed()
    {
        _duels += 1;
        if (Options.RunSeed > 0)
            return Options.RunSeed * 1009 + _duels;
        return GD.Randi() % 1000000;
    }

    public void next_rival()
    {
        if (state != "over")
            return;
        if (Rivals.HasRival(rival + 1))
        {
            start_rival(rival + 1);
        }
        else
        {
            GD.Print("[Run] victory");
            Finish(true);
        }
    }

    public void rematch()
    {
        if (state == "over")
            start_rival(rival);
    }

    /// <summary>Game time in milliseconds: physics ticks, never the wall clock.</summary>
    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    private bool IsPlayersMain() => state == "playing" && _bot == null && duel!.Phase == Phase.Main && duel.Active == 0;

    /// <summary>Plays a card of the player's hand; false when it is not the player's Main phase or the rules refuse it.</summary>
    public bool play_card(int index)
    {
        if (!IsPlayersMain() || !duel!.Play(0, index))
            return false;
        Suggest();
        Refresh();
        return true;
    }

    /// <summary>Ends the player's Main phase.</summary>
    public void end_turn()
    {
        if (IsPlayersMain())
            duel!.EndMain();
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event.IsActionPressed(EndTurnAction) && IsPlayersMain())
        {
            end_turn();
            GetViewport().SetInputAsHandled();
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        _ticks += 1;
        UpdateEffects((float)delta);
        if (state == "over")
        {
            if (_nextIn > 0)
            {
                _nextIn -= 1;
                if (_nextIn == 0)
                    BotNext();
            }
            return;
        }
        if (state != "playing")
            return;
        if (_wait > 0)
        {
            _wait -= 1;
            return;
        }
        switch (duel!.Phase)
        {
            case Phase.Main:
                if (duel.Active == 1 || _bot != null)
                    AiTurn();
                break;
            case Phase.Clash:
                duel.Advance();
                _wait = StrikeTicks;
                break;
            case Phase.Over:
                break;
            default:
                duel.Advance();
                _wait = PhaseTicks;
                break;
        }
    }

    /// <summary>The AI whose turn it is makes one play, or ends its Main phase.</summary>
    private void AiTurn()
    {
        int seat = duel!.Active;
        Ai ai = seat == 1 ? _rivalAi : _bot!;
        int index = ai.Choose(duel, seat);
        GD.Print($"[AI] turn {duel.Turn} seat {seat}: {ai.Describe()} -> {(index >= 0 ? duel.Keepers[seat].Hand[index] : "pass")}");
        if (index < 0)
        {
            duel.EndMain();
            _wait = PhaseTicks;
            return;
        }
        duel.Play(seat, index);
        Refresh();
        _wait = ThinkTicks;
    }

    private void OnPhaseChanged(Phase from, Phase to)
    {
        Refresh();
        if (to == Phase.Main && duel!.Active == 0 && _bot == null)
        {
            JsonObject data = duel.ToDict();
            data["rival"] = rival;
            Checkpoint?.Invoke(data);
            Suggest();
        }
        else if (to == Phase.Over)
        {
            Over();
        }
    }

    /// <summary>Asks the AI which card it would play in the player's place, once per change: the HUD marks that card.</summary>
    private void Suggest()
    {
        suggest_checks += 1;
        suggested = IsPlayersMain() ? _hintAi.Choose(duel!, 0) : -1;
        RefreshHand();
    }

    private void Over()
    {
        state = "over";
        bool won = duel!.Winner == 0;
        GD.Print($"[Run] rival {rival} {(won ? "won" : "lost")}");
        if (won)
            _sfxWin.Play();
        DuelOver?.Invoke(rival, won);
        if (_bot != null)
            _nextIn = AutoplayNextTicks;
        else
            _resultMenu.Open(won, Rivals.HasRival(rival + 1) ? "RESULT_NEXT" : "RESULT_FINISH");
    }

    /// <summary>A bot run goes on: the next rival after a win, the same one again after a loss, victory after the last.</summary>
    private void BotNext()
    {
        if (duel!.Winner == 0)
            next_rival();
        else
            start_rival(rival);
    }

    private void Finish(bool victory)
    {
        state = "done";
        Finished?.Invoke(victory);
        // On its own (a flow, or the game scene run alone) nobody listens; a bot run then ends here.
        if (Options.Autoplay && Finished == null)
            GetTree().Quit();
    }

    private void Refresh()
    {
        if (duel == null || !IsNodeReady())
            return;
        string nameKey = Rivals.Rival(rival)?.Name ?? "";
        _rivalLabel.Text = Tr(nameKey);
        _rivalLight.Text = TextFormat.Fill(Tr("HUD_LIGHT"), duel.Keepers[1].Light);
        _playerLight.Text = TextFormat.Fill(Tr("HUD_LIGHT"), duel.Keepers[0].Light);
        _kindlingLabel.Text = TextFormat.Fill(Tr("HUD_KINDLING"), duel.Keepers[0].Kindling, Math.Min(duel.Keepers[0].Turns, Duel.MaxKindling));
        _turnLabel.Text = TextFormat.Fill(Tr("HUD_TURN"), duel.Turn, Tr(PhaseKeys[(int)duel.Phase]), duel.Active == 0 ? Tr("HUD_YOU") : Tr(nameKey));
        _endTurn.Disabled = !IsPlayersMain();
        RefreshHand();
        Table.QueueRedraw();
    }

    /// <summary>One button per card of the player's hand, Card0 first; only playable ones are enabled, the suggested one marked.</summary>
    private void RefreshHand()
    {
        if (duel == null)
            return;
        List<string> hand = duel.Keepers[0].Hand;
        while (_hand.GetChildCount() > hand.Count)
        {
            Node extra = _hand.GetChild(_hand.GetChildCount() - 1);
            _hand.RemoveChild(extra);
            extra.QueueFree();
        }
        while (_hand.GetChildCount() < hand.Count)
        {
            int index = _hand.GetChildCount();
            var button = new Button
            {
                Name = $"Card{index}",
                CustomMinimumSize = new Vector2(150, 130),
                FocusMode = Control.FocusModeEnum.All,
                AutowrapMode = TextServer.AutowrapMode.WordSmart,
            };
            button.AddThemeFontSizeOverride("font_size", 17);
            button.Pressed += () => play_card(index);
            _hand.AddChild(button);
        }
        for (int index = 0; index < hand.Count; index++)
        {
            var button = (Button)_hand.GetChild(index);
            button.Text = CardText(Cards.Get(hand[index]));
            button.Disabled = !(IsPlayersMain() && duel.CanPlay(0, index));
            button.Modulate = index == suggested ? SuggestedTint : Colors.White;
        }
    }

    /// <summary>A card's face as text: its name, cost, and power / guard for a wisp or what a rite does.</summary>
    public string CardText(Card card)
    {
        string stats = card.Kind == Cards.Wisp
            ? $"{card.Power} / {card.Guard}"
            : TextFormat.Fill(Tr(EffectKeys.TryGetValue(card.Effect, out string? key) ? key : ""), card.Amount);
        return $"{Tr(card.Name)}\n{TextFormat.Fill(Tr("CARD_COST"), card.Cost)}\n{stats}";
    }

    private void OnCardPlayed(int seat, Card card)
    {
        Event("card_played");
        Play(_sfxPlay);
        Table.QueueRedraw();
    }

    private void OnKeeperHit(int seat, int amount)
    {
        Event("keeper_hit");
        FlashScreen(seat == 0 ? new Color(1f, 0.3f, 0.2f, 0.35f) : new Color(1f, 0.85f, 0.4f, 0.3f));
        ShakeCamera(8f);
        Play(_sfxHit);
        Refresh();
    }

    private void OnWispFell(int seat, int lane)
    {
        Event("wisp_fell");
        Table.Pop(seat, lane);
        Feedback("pop");
        Play(_sfxFall);
        Table.QueueRedraw();
    }

    // Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
    private void Event(string name)
    {
        GD.Print($"[juice] event {name} {GameMs().ToString("0.0", CultureInfo.InvariantCulture)}");
    }

    private void Feedback(string kind)
    {
        GD.Print($"[juice] feedback {kind} {GameMs().ToString("0.0", CultureInfo.InvariantCulture)}");
    }

    private void FlashScreen(Color color)
    {
        _flash = color.A;
        _flashRect.Color = color;
        Feedback("flash");
    }

    private void ShakeCamera(float amount)
    {
        _shake = amount;
        Feedback("shake");
    }

    private void Play(AudioStreamPlayer player)
    {
        player.Play();
        Feedback("sfx");
    }

    private void UpdateEffects(float delta)
    {
        _flash = Mathf.Max(_flash - delta * 2f, 0f);
        Color color = _flashRect.Color;
        color.A = _flash;
        _flashRect.Color = color;
        _shake = Mathf.Max(_shake - delta * 40f, 0f);
        _camera.Offset = _shake > 0f ? new Vector2(_rng.RandfRange(-_shake, _shake), _rng.RandfRange(-_shake, _shake)) : Vector2.Zero;
    }
}
