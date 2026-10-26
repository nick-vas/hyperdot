namespace Duskhive;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// The hive: the glow counter, Gather and the producers. The rules live in Economy; this node ticks them in
/// _PhysicsProcess (60 ticks a second) and shows them.
/// </summary>
/// <remarks>
/// <c>economy</c>, <c>buy_mode</c> and the methods <c>gather</c>, <c>buy</c>, <c>next_mode</c> and <c>add_glow</c> keep
/// the names the UI flows and the GDScript version use: the flows are shared, word for word.
/// </remarks>
public partial class Game : Control
{
    /// <summary>The buy amounts the mode button steps through.</summary>
    private static readonly int[] Modes = { 1, 10 };

    private readonly Dictionary<string, ProducerRow> _rows = new();

    private Label _glow = null!;
    private Label _rate = null!;
    private Button _gather = null!;
    private Label _pageTitle = null!;
    private Button _mode = null!;
    private VBoxContainer _producerList = null!;
    private Sky _sky = null!;

    public Catalog Catalog { get; private set; } = null!;

    public Economy economy { get; private set; } = null!;

    /// <summary>The amount the producer rows buy.</summary>
    public int buy_mode { get; set; } = 1;

    public override void _Ready()
    {
        _glow = GetNode<Label>("Safe/Column/Top/GlowLabel");
        _rate = GetNode<Label>("Safe/Column/Top/RateLabel");
        _gather = GetNode<Button>("Safe/Column/GatherButton");
        _pageTitle = GetNode<Label>("Safe/Column/Header/PageTitle");
        _mode = GetNode<Button>("Safe/Column/Header/BuyModeButton");
        _producerList = GetNode<VBoxContainer>("Safe/Column/ProducerPage/List");
        _sky = GetNode<Sky>("Sky");

        Catalog = Catalog.FromFiles();
        economy = new Economy(Catalog);
        _gather.Pressed += gather;
        _mode.Pressed += next_mode;
        foreach (ProducerData producer in Catalog.Producers)
        {
            var row = new ProducerRow();
            row.Setup(producer);
            row.BuyPressed += id => buy(id);
            _producerList.AddChild(row);
            _rows[row.Id] = row;
        }
        economy.Bought += (id, amount) => Refresh();
        Refresh();
    }

    public override void _PhysicsProcess(double delta)
    {
        economy.Tick(delta);
        Refresh();
    }

    /// <summary>Gather: a press of the big button.</summary>
    public void gather()
    {
        economy.Tap();
        Refresh();
    }

    /// <summary>Buys the buy mode's amount of a producer.</summary>
    public bool buy(string id) => economy.Buy(id, buy_mode);

    public void next_mode()
    {
        buy_mode = Modes[(Array.IndexOf(Modes, buy_mode) + 1) % Modes.Length];
        Refresh();
    }

    /// <summary>Glow for tests and flows: as if it had been earned.</summary>
    public void add_glow(double amount)
    {
        economy.Earn(amount);
        Refresh();
    }

    /// <summary>Shows the economy as it is now; the rows are refreshed from here, never by themselves.</summary>
    internal void Refresh()
    {
        if (economy == null || !IsNodeReady())
            return;
        ProducerRow.SetText(_glow, TextFormat.Fill(Tr("HUD_GLOW"), Numbers.Format(economy.Glow)));
        ProducerRow.SetText(_rate, TextFormat.Fill(Tr("HUD_RATE"), Numbers.FormatRate(economy.Rate())));
        ProducerRow.SetText(_gather, TextFormat.Fill(Tr("GATHER"), Numbers.Format(economy.TapValue())));
        ProducerRow.SetText(_pageTitle, Tr("PAGE_PRODUCERS"));
        ProducerRow.SetText(_mode, Tr(buy_mode == 10 ? "MODE_TEN" : "MODE_ONE"));
        foreach (ProducerData producer in Catalog.Producers)
            _rows[producer.Id].Refresh(economy, buy_mode);
        _sky.Glow = economy.Glow;
    }
}
