namespace Lanternfen;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// One duel against the first rival on the table, with the player's hand and End turn.
/// The rules live in Duel; this node only paces them. Each Draw, Clash strike and End waits a few ticks so it can be
/// seen, the rival's AI thinks before each play, and the player's Main phase waits for a card or End turn.
/// </summary>
/// <remarks>
/// <c>rival</c>, <c>state</c>, <c>phase</c>, <c>active</c>, <c>turn</c> and the methods <c>start_rival</c>,
/// <c>play_card</c> and <c>end_turn</c> keep the names the GDScript version uses.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>Ticks a Draw, the end of a Main phase or an End takes on screen.</summary>
    public const int PhaseTicks = 8;
    /// <summary>Ticks between two strikes of a Clash.</summary>
    public const int StrikeTicks = 9;
    /// <summary>Ticks the rival's AI thinks before each play.</summary>
    public const int ThinkTicks = 10;
    private static readonly StringName EndTurnAction = "end_turn";

    private Ai _rivalAi = new();
    private int _wait;

    private Label _rivalLabel = null!;
    private Label _rivalLight = null!;
    private Label _playerLight = null!;
    private Label _kindlingLabel = null!;
    private Label _turnLabel = null!;
    private HBoxContainer _hand = null!;
    private Button _endTurn = null!;

    public Rivals Rivals { get; private set; } = null!;
    public Cards Cards { get; private set; } = null!;
    public Table Table { get; private set; } = null!;

    public Duel? duel { get; private set; }

    public int rival { get; private set; } = 1;

    /// <summary>"playing" or "over".</summary>
    public string state { get; private set; } = "playing";

    public string phase => duel?.PhaseName ?? "";

    public int active => duel?.Active ?? 0;

    public int turn => duel?.Turn ?? 0;

    public override void _Ready()
    {
        Table = GetNode<Table>("Table");
        _rivalLabel = GetNode<Label>("HUD/RivalLabel");
        _rivalLight = GetNode<Label>("HUD/RivalLight");
        _playerLight = GetNode<Label>("HUD/PlayerLight");
        _kindlingLabel = GetNode<Label>("HUD/KindlingLabel");
        _turnLabel = GetNode<Label>("HUD/TurnLabel");
        _hand = GetNode<HBoxContainer>("HUD/Hand");
        _endTurn = GetNode<Button>("HUD/EndTurnButton");
        Rivals = Rivals.FromFiles();
        Cards = Cards.FromFile();
        _endTurn.Pressed += end_turn;
        start_rival(1);
    }

    /// <summary>A new duel against a rival, as start_rival(id, -1).</summary>
    /// <remarks>An overload, not a default argument: the engine (a flow's call step) calls a C# method only with all its arguments.</remarks>
    public void start_rival(int id) => start_rival(id, -1);

    /// <summary>A new duel against a rival; seed -1 shuffles at random.</summary>
    public void start_rival(int id, long seed)
    {
        rival = id;
        duel = Rivals.StartDuel(Cards, id, seed >= 0 ? seed : GD.Randi() % 1000000);
        duel.PhaseChanged += OnPhaseChanged;
        _rivalAi = Rivals.AiFor(id);
        state = "playing";
        _wait = PhaseTicks;
        Table.ShowDuel(duel, Cards);
        Refresh();
    }

    private bool IsPlayersMain() => state == "playing" && duel!.Phase == Phase.Main && duel.Active == 0;

    /// <summary>Plays a card of the player's hand; false when it is not the player's Main phase or the rules refuse it.</summary>
    public bool play_card(int index)
    {
        if (!IsPlayersMain() || !duel!.Play(0, index))
            return false;
        Refresh();
        return true;
    }

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
                if (duel.Active == 1)
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

    /// <summary>The rival makes one play, or ends its Main phase.</summary>
    private void AiTurn()
    {
        int index = _rivalAi.Choose(duel!, 1);
        if (index < 0)
        {
            duel!.EndMain();
            _wait = PhaseTicks;
            return;
        }
        duel!.Play(1, index);
        Refresh();
        _wait = ThinkTicks;
    }

    private void OnPhaseChanged(Phase from, Phase to)
    {
        if (to == Phase.Over)
            state = "over";
        Refresh();
    }

    private void Refresh()
    {
        if (duel == null || !IsNodeReady())
            return;
        _rivalLabel.Text = $"Rival {rival}";
        _rivalLight.Text = $"Light: {duel.Keepers[1].Light}";
        _playerLight.Text = $"Light: {duel.Keepers[0].Light}";
        _kindlingLabel.Text = $"Kindling: {duel.Keepers[0].Kindling} / {Math.Min(duel.Keepers[0].Turns, Duel.MaxKindling)}";
        if (state == "over")
            _turnLabel.Text = duel.Winner == 0 ? "You won" : "You lost";
        else
            _turnLabel.Text = $"Turn {duel.Turn}: {Duel.PhaseNames[(int)duel.Phase]} ({(duel.Active == 0 ? "you" : "rival")})";
        _endTurn.Disabled = !IsPlayersMain();
        RefreshHand();
        Table.QueueRedraw();
    }

    /// <summary>One button per card of the player's hand, Card0 first; only playable ones are enabled.</summary>
    private void RefreshHand()
    {
        List<string> hand = duel!.Keepers[0].Hand;
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
                AutowrapMode = TextServer.AutowrapMode.WordSmart,
            };
            button.AddThemeFontSizeOverride("font_size", 17);
            button.Pressed += () => play_card(index);
            _hand.AddChild(button);
        }
        for (int index = 0; index < hand.Count; index++)
        {
            var button = (Button)_hand.GetChild(index);
            Card card = Cards.Get(hand[index]);
            string stats = card.Kind == Cards.Wisp ? $"{card.Power} / {card.Guard}" : $"{card.Effect.Capitalize()} {card.Amount}";
            button.Text = $"{card.Id.Capitalize()}\nCost {card.Cost}\n{stats}";
            button.Disabled = !(IsPlayersMain() && duel!.CanPlay(0, index));
        }
    }
}
