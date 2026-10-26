namespace Duskhive;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json.Nodes;
using Godot;

/// <summary>
/// The hive: the glow counter, Gather, the producer and upgrade pages, the dawn, and the panels for time away and for
/// the dawn. Main gives it the saved economy with Setup(); on its own (a flow, a test, the editor) it starts a new one.
/// The rules live in Economy; this node ticks them in _PhysicsProcess (60 ticks a second, times --speed), shows them,
/// gives each event its feedback and, with --autoplay, lets the bot play.
/// </summary>
/// <remarks>
/// <c>economy</c>, <c>buy_mode</c>, <c>page</c> and the methods <c>restore</c>, <c>gather</c>, <c>buy</c>,
/// <c>buy_upgrade</c>, <c>next_mode</c>, <c>show_page</c>, <c>ask_dawn</c>, <c>confirm_dawn</c>, <c>show_welcome</c>
/// and <c>add_glow</c> keep the names the UI flows and the GDScript version use: the flows are shared, word for word.
/// </remarks>
public partial class Game : Control
{
    /// <summary>The bot's goal: this much glow earned over all runs.</summary>
    public const double GoalGlow = 1e9;
    private const double PopSeconds = 0.15;
    private const double FlashSeconds = 0.35;
    private const double ShakeSeconds = 0.35;

    /// <summary>The buy amounts the mode button steps through; 0 is as many as the glow pays for.</summary>
    private static readonly int[] Modes = { 1, 10, 0 };

    private readonly Dictionary<string, ProducerRow> _rows = new();
    private readonly Dictionary<string, UpgradeRow> _upgradeRows = new();
    private readonly List<Control> _pops = new();
    private readonly Dictionary<Control, double> _popTime = new();
    private JsonObject _saved = new();
    private int _ticks;
    private double _flash;
    private double _shake;
    private double _welcomeSeconds;
    private double _welcomeGlow;

    private MarginContainer _safe = null!;
    private Label _glow = null!;
    private Label _rate = null!;
    private Label _embers = null!;
    private Button _gather = null!;
    private Label _pageTitle = null!;
    private Button _mode = null!;
    private ScrollContainer _producerPage = null!;
    private VBoxContainer _producerList = null!;
    private ScrollContainer _upgradePage = null!;
    private VBoxContainer _upgradeList = null!;
    private HBoxContainer _bar = null!;
    private Button _producersTab = null!;
    private Button _upgradesTab = null!;
    private Button _dawnButton = null!;
    private Button _settingsButton = null!;
    private ColorRect _flashRect = null!;
    private PanelContainer _welcome = null!;
    private Label _welcomeTitle = null!;
    private Label _welcomeMessage = null!;
    private Button _collect = null!;
    private PanelContainer _dawnPanel = null!;
    private Label _dawnTitle = null!;
    private Label _dawnMessage = null!;
    private Button _confirm = null!;
    private Button _cancel = null!;
    private Sky _sky = null!;
    private AudioStreamPlayer _sfxBuy = null!;
    private AudioStreamPlayer _sfxUpgrade = null!;
    private AudioStreamPlayer _sfxDawn = null!;
    private AudioStreamPlayer _sfxGather = null!;

    /// <summary>A dawn happened: Main saves at once, since the run before it is gone.</summary>
    public event Action<double>? Dawned;

    public event Action? SettingsRequested;

    /// <summary>The bot reached its goal (--autoplay).</summary>
    public event Action? Finished;

    public Catalog Catalog { get; private set; } = null!;

    public LaunchOptions Options { get; private set; } = null!;

    public Economy economy { get; private set; } = null!;

    /// <summary>The amount the producer rows buy: 1, 10 or 0 (as many as the glow pays for).</summary>
    public int buy_mode { get; set; } = 1;

    /// <summary>The page shown: "producers" or "upgrades".</summary>
    public string page { get; private set; } = "producers";

    public bool GoalReached { get; private set; }

    /// <summary>Called by Main before the game enters the tree: the data, the flags and the saved economy (Economy.ToDict()).</summary>
    public void Setup(Catalog catalog, LaunchOptions options, JsonObject saved)
    {
        Catalog = catalog;
        Options = options;
        _saved = saved;
    }

    public override void _Ready()
    {
        _safe = GetNode<MarginContainer>("Safe");
        _glow = GetNode<Label>("Safe/Column/Top/GlowLabel");
        _rate = GetNode<Label>("Safe/Column/Top/RateLabel");
        _embers = GetNode<Label>("Safe/Column/Top/EmbersLabel");
        _gather = GetNode<Button>("Safe/Column/GatherButton");
        _pageTitle = GetNode<Label>("Safe/Column/Header/PageTitle");
        _mode = GetNode<Button>("Safe/Column/Header/BuyModeButton");
        _producerPage = GetNode<ScrollContainer>("Safe/Column/ProducerPage");
        _producerList = GetNode<VBoxContainer>("Safe/Column/ProducerPage/List");
        _upgradePage = GetNode<ScrollContainer>("Safe/Column/UpgradePage");
        _upgradeList = GetNode<VBoxContainer>("Safe/Column/UpgradePage/List");
        _bar = GetNode<HBoxContainer>("Safe/Column/Bar");
        _producersTab = GetNode<Button>("Safe/Column/Bar/ProducersTab");
        _upgradesTab = GetNode<Button>("Safe/Column/Bar/UpgradesTab");
        _dawnButton = GetNode<Button>("Safe/Column/Bar/DawnButton");
        _settingsButton = GetNode<Button>("Safe/Column/Bar/SettingsButton");
        _flashRect = GetNode<ColorRect>("Flash");
        _welcome = GetNode<PanelContainer>("WelcomePanel");
        _welcomeTitle = GetNode<Label>("WelcomePanel/Box/Title");
        _welcomeMessage = GetNode<Label>("WelcomePanel/Box/MessageLabel");
        _collect = GetNode<Button>("WelcomePanel/Box/CollectButton");
        _dawnPanel = GetNode<PanelContainer>("DawnPanel");
        _dawnTitle = GetNode<Label>("DawnPanel/Box/Title");
        _dawnMessage = GetNode<Label>("DawnPanel/Box/MessageLabel");
        _confirm = GetNode<Button>("DawnPanel/Box/ConfirmButton");
        _cancel = GetNode<Button>("DawnPanel/Box/CancelButton");
        _sky = GetNode<Sky>("Sky");
        _sfxBuy = GetNode<AudioStreamPlayer>("SfxBuy");
        _sfxUpgrade = GetNode<AudioStreamPlayer>("SfxUpgrade");
        _sfxDawn = GetNode<AudioStreamPlayer>("SfxDawn");
        _sfxGather = GetNode<AudioStreamPlayer>("SfxGather");

        Catalog ??= Catalog.FromFiles();
        Options ??= LaunchOptions.FromCommandLine();
        _gather.Pressed += gather;
        _mode.Pressed += next_mode;
        _producersTab.Pressed += () => show_page("producers");
        _upgradesTab.Pressed += () => show_page("upgrades");
        _dawnButton.Pressed += ask_dawn;
        _settingsButton.Pressed += () => SettingsRequested?.Invoke();
        _collect.Pressed += _welcome.Hide;
        _confirm.Pressed += confirm_dawn;
        _cancel.Pressed += _dawnPanel.Hide;
        // Long translations wrap inside the bar instead of pushing it off a phone screen.
        foreach (Node node in _bar.GetChildren())
            ((Button)node).AutowrapMode = TextServer.AutowrapMode.WordSmart;
        foreach (ProducerData producer in Catalog.Producers)
        {
            var row = new ProducerRow();
            row.Setup(producer);
            row.BuyPressed += id => buy(id);
            _producerList.AddChild(row);
            _rows[row.Id] = row;
        }
        foreach (UpgradeData upgrade in Catalog.Upgrades)
        {
            var row = new UpgradeRow();
            row.Setup(upgrade, Catalog);
            row.BuyPressed += id => buy_upgrade(id);
            _upgradeList.AddChild(row);
            _upgradeRows[row.Id] = row;
        }
        restore(_saved);
        show_page("producers");
    }

    /// <summary>Replaces the economy with a saved one (Economy.ToDict()); an empty one starts a new game.</summary>
    public void restore(JsonObject saved)
    {
        economy = Economy.FromDict(Catalog, saved);
        economy.Bought += OnBought;
        economy.Upgraded += OnUpgraded;
        economy.Dawned += OnDawned;
        Refresh();
    }

    public override void _PhysicsProcess(double delta)
    {
        _ticks++;
        economy.Tick(delta * Options.Speed);
        if (Options.Autoplay)
            PlayBot();
        UpdateEffects(delta);
        Refresh();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            Refresh();
    }

    /// <summary>Gather: a press of the big button.</summary>
    public void gather()
    {
        economy.Tap();
        Event("gathered");
        Play(_sfxGather);
        Pop(_gather);
        Refresh();
    }

    /// <summary>Buys the buy mode's amount of a producer.</summary>
    public bool buy(string id)
    {
        if (buy_mode == 0)
            return economy.BuyMax(id) > 0;
        return economy.Buy(id, buy_mode);
    }

    public bool buy_upgrade(string id) => economy.BuyUpgrade(id);

    public void next_mode()
    {
        buy_mode = Modes[(Array.IndexOf(Modes, buy_mode) + 1) % Modes.Length];
        Refresh();
    }

    public void show_page(string which)
    {
        page = which;
        _producerPage.Visible = which == "producers";
        _upgradePage.Visible = which == "upgrades";
        _mode.Visible = which == "producers";
        Refresh();
    }

    /// <summary>Opens the dawn's panel, which says what it would give.</summary>
    public void ask_dawn()
    {
        if (economy.CanDawn())
        {
            _dawnPanel.Show();
            Refresh();
        }
    }

    public void confirm_dawn()
    {
        _dawnPanel.Hide();
        economy.Dawn();
    }

    /// <summary>The time away and what it earned, on the welcome panel (Main calls it after the save is read).</summary>
    public void show_welcome(double seconds, double glow)
    {
        if (glow <= 0.0)
            return;
        _welcomeSeconds = seconds;
        _welcomeGlow = glow;
        _welcome.Show();
        Refresh();
    }

    /// <summary>Glow for tests and flows: as if it had been earned.</summary>
    public void add_glow(double amount)
    {
        economy.Earn(amount);
        Refresh();
    }

    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    private void PlayBot()
    {
        BotAction action = Bot.Act(economy);
        if (action.Kind == "gather")
        {
            Event("gathered");
            Play(_sfxGather);
            Pop(_gather);
        }
        if (!GoalReached && economy.TotalEarned >= GoalGlow)
        {
            GoalReached = true;
            GD.Print($"[Run] goal: {Numbers.Format(economy.TotalEarned)} glow after {economy.Dawns} dawns");
            Finished?.Invoke();
        }
    }

    /// <summary>Shows the economy as it is now; the rows are refreshed from here, never by themselves.</summary>
    internal void Refresh()
    {
        if (economy == null || !IsNodeReady())
            return;
        ProducerRow.SetText(_glow, TextFormat.Fill(Tr("HUD_GLOW"), Numbers.Format(economy.Glow)));
        ProducerRow.SetText(_rate, TextFormat.Fill(Tr("HUD_RATE"), Numbers.FormatRate(economy.Rate())));
        ProducerRow.SetText(_embers, TextFormat.Fill(Tr("HUD_EMBERS"), Numbers.Format(economy.Embers), Percent(economy.EmberMultiplier() - 1.0)));
        ProducerRow.SetText(_gather, TextFormat.Fill(Tr("GATHER"), Numbers.Format(economy.TapValue())));
        ProducerRow.SetText(_pageTitle, Tr(page == "producers" ? "PAGE_PRODUCERS" : "PAGE_UPGRADES"));
        ProducerRow.SetText(_mode, Tr(ModeKey(buy_mode)));
        ProducerRow.SetText(_producersTab, Tr("BAR_PRODUCERS"));
        ProducerRow.SetText(_upgradesTab, Tr("BAR_UPGRADES"));
        ProducerRow.SetText(_dawnButton, Tr("BAR_DAWN"));
        ProducerRow.SetText(_settingsButton, Tr("BAR_SETTINGS"));
        _dawnButton.Disabled = !economy.CanDawn();
        foreach (ProducerData producer in Catalog.Producers)
            _rows[producer.Id].Refresh(economy, buy_mode);
        foreach (UpgradeData upgrade in Catalog.Upgrades)
            _upgradeRows[upgrade.Id].Refresh(economy);
        if (_welcome.Visible)
        {
            ProducerRow.SetText(_welcomeTitle, Tr("WELCOME_TITLE"));
            ProducerRow.SetText(_welcomeMessage, TextFormat.Fill(Tr("WELCOME_MESSAGE"), Duration(_welcomeSeconds), Numbers.Format(_welcomeGlow)));
            ProducerRow.SetText(_collect, Tr("WELCOME_COLLECT"));
        }
        if (_dawnPanel.Visible)
        {
            ProducerRow.SetText(_dawnTitle, Tr("DAWN_TITLE"));
            ProducerRow.SetText(_dawnMessage, TextFormat.Fill(Tr("DAWN_MESSAGE"), Numbers.Format(economy.DawnGain()), Percent(Catalog.Setting("ember_bonus"))));
            ProducerRow.SetText(_confirm, Tr("DAWN_CONFIRM"));
            ProducerRow.SetText(_cancel, Tr("DAWN_CANCEL"));
        }
        _sky.Glow = economy.Glow;
    }

    private static string ModeKey(int mode) => mode switch
    {
        1 => "MODE_ONE",
        10 => "MODE_TEN",
        _ => "MODE_MAX",
    };

    /// <summary>A fraction as whole percent, rounded half away from zero as GDScript's roundi() does.</summary>
    private static long Percent(double fraction) => (long)Math.Round(fraction * 100.0, MidpointRounding.AwayFromZero);

    /// <summary>2 h 05 min, or 12 min.</summary>
    private string Duration(double seconds)
    {
        long minutes = (long)Math.Floor(seconds / 60.0);
        if (minutes >= 60)
            return TextFormat.Fill(Tr("TIME_HOURS"), minutes / 60, minutes % 60);
        return TextFormat.Fill(Tr("TIME_MINUTES"), minutes);
    }

    private void OnBought(string id, int amount)
    {
        Refresh();
        Event("bought");
        Play(_sfxBuy);
        Pop(_rows[id].BuyButton());
    }

    private void OnUpgraded(string id)
    {
        Refresh();
        Event("upgraded");
        GetTree().CreateTimer(0.25).Timeout += () => Play(_sfxUpgrade);
        Pop(_upgradeRows[id].BuyButton());
    }

    private void OnDawned(double embers)
    {
        GD.Print($"[Run] dawn {economy.Dawns}, {Numbers.Format(economy.Embers)} embers");
        Event("dawn");
        Play(_sfxDawn);
        _flash = FlashSeconds;
        Feedback("flash");
        _shake = ShakeSeconds;
        Feedback("shake");
        Refresh();
        Dawned?.Invoke(embers);
    }

    private void UpdateEffects(double delta)
    {
        _flash = Math.Max(_flash - delta, 0.0);
        _flashRect.Color = _flashRect.Color with { A = (float)(0.6 * _flash / FlashSeconds) };
        _shake = Math.Max(_shake - delta, 0.0);
        double strength = 14.0 * _shake / ShakeSeconds;
        _safe.Position = new Vector2((float)(Math.Sin(_ticks * 1.7) * strength), (float)(Math.Cos(_ticks * 2.3) * strength));
        for (int i = _pops.Count - 1; i >= 0; i--)
        {
            Control control = _pops[i];
            double left = _popTime[control] - delta;
            _popTime[control] = left;
            control.Scale = Vector2.One * (float)(1.0 + 0.12 * Math.Max(left, 0.0) / PopSeconds);
            if (left <= 0.0)
            {
                _pops.RemoveAt(i);
                _popTime.Remove(control);
            }
        }
    }

    private void Pop(Control control)
    {
        control.PivotOffset = control.Size / 2.0f;
        if (!_pops.Contains(control))
            _pops.Add(control);
        _popTime[control] = PopSeconds;
        Feedback("pop");
    }

    private void Play(AudioStreamPlayer player)
    {
        player.Play();
        Feedback("sfx");
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

    public void StopSounds()
    {
        foreach (AudioStreamPlayer player in new[] { _sfxBuy, _sfxUpgrade, _sfxDawn, _sfxGather })
            player.Stop();
    }
}
