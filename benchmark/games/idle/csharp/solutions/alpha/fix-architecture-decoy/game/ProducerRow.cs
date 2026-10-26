namespace Duskhive;

using System;
using Godot;

/// <summary>
/// One producer in the shop: its name, how many are owned and what they make, and a button that buys the amount the
/// buy mode asks for at its price. It keeps itself up to date from the game.
/// </summary>
public partial class ProducerRow : PanelContainer
{
    private readonly Label _name = new();
    private readonly Label _detail = new();
    private readonly Button _buy = new();
    private string _nameKey = "";
    private Game? _game;

    public event Action<string>? BuyPressed;

    public string Id { get; private set; } = "";

    public void Setup(ProducerData producer)
    {
        Id = producer.Id;
        _nameKey = producer.Name;
        Name = $"{Id.ToPascalCase()}Row";
        CustomMinimumSize = new Vector2(0, 104);
        var box = new HBoxContainer { Name = "Box" };
        box.AddThemeConstantOverride("separation", 12);
        AddChild(box);
        var info = new VBoxContainer { Name = "Info", SizeFlagsHorizontal = SizeFlags.ExpandFill };
        box.AddChild(info);
        _name.Name = "NameLabel";
        _name.AddThemeFontSizeOverride("font_size", 30);
        info.AddChild(_name);
        _detail.Name = "DetailLabel";
        _detail.AddThemeFontSizeOverride("font_size", 24);
        _detail.Modulate = new Color(0.85f, 0.82f, 1.0f);
        info.AddChild(_detail);
        _buy.Name = "BuyButton";
        _buy.CustomMinimumSize = new Vector2(230, 96);
        _buy.AddThemeFontSizeOverride("font_size", 26);
        _buy.Pressed += () => BuyPressed?.Invoke(Id);
        box.AddChild(_buy);
    }

    public override void _Ready()
    {
        _game = GetNode<Game>("../../../../..");
    }

    public override void _Process(double delta)
    {
        if (_game != null)
            Refresh(_game.economy, _game.buy_mode);
    }

    public Button BuyButton() => _buy;

    /// <summary>Shows the producer as the economy has it, for a buy amount of mode (0: as many as the glow pays for).</summary>
    public void Refresh(Economy economy, int mode)
    {
        int amount = mode > 0 ? mode : Math.Max(1, economy.MaxAffordable(Id));
        SetText(_name, Tr(_nameKey));
        SetText(_detail, TextFormat.Fill(Tr("ROW_DETAIL"), economy.Count(Id), Numbers.FormatRate(economy.ProducerRate(Id))));
        SetText(_buy, TextFormat.Fill(Tr("ROW_BUY"), amount, Numbers.Format(economy.Cost(Id, amount))));
        _buy.Disabled = !economy.CanBuy(Id, amount);
    }

    /// <summary>Sets a label's text only when it changes, so a refresh every tick costs no relayout.</summary>
    internal static void SetText(Label label, string text)
    {
        if (label.Text != text)
            label.Text = text;
    }

    /// <summary>Sets a button's text only when it changes.</summary>
    internal static void SetText(Button button, string text)
    {
        if (button.Text != text)
            button.Text = text;
    }
}
