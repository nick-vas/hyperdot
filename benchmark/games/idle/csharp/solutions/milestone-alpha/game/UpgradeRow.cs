namespace Duskhive;

using System;
using System.Globalization;
using Godot;

/// <summary>
/// One upgrade on offer: what it multiplies, its price and a button. Shown once its producer is owned often enough,
/// hidden once bought.
/// </summary>
public partial class UpgradeRow : PanelContainer
{
    private readonly Label _name = new();
    private readonly Label _detail = new();
    private readonly Button _buy = new();
    private UpgradeData _upgrade = null!;
    private string _targetKey = "";

    public event Action<string>? BuyPressed;

    public string Id { get; private set; } = "";

    public void Setup(UpgradeData upgrade, Catalog catalog)
    {
        Id = upgrade.Id;
        _upgrade = upgrade;
        _targetKey = TargetKey(upgrade.Target, catalog);
        Name = $"{Id.ToPascalCase()}Row";
        CustomMinimumSize = new Vector2(0, 96);
        var box = new HBoxContainer { Name = "Box" };
        box.AddThemeConstantOverride("separation", 12);
        AddChild(box);
        var info = new VBoxContainer { Name = "Info", SizeFlagsHorizontal = SizeFlags.ExpandFill };
        box.AddChild(info);
        _name.Name = "NameLabel";
        _name.AddThemeFontSizeOverride("font_size", 28);
        info.AddChild(_name);
        _detail.Name = "DetailLabel";
        _detail.AddThemeFontSizeOverride("font_size", 22);
        _detail.Modulate = new Color(0.85f, 0.82f, 1.0f);
        info.AddChild(_detail);
        _buy.Name = "BuyButton";
        _buy.CustomMinimumSize = new Vector2(200, 88);
        _buy.AddThemeFontSizeOverride("font_size", 26);
        _buy.Pressed += () => BuyPressed?.Invoke(Id);
        box.AddChild(_buy);
    }

    public Button BuyButton() => _buy;

    public void Refresh(Economy economy)
    {
        Visible = economy.UpgradeUnlocked(Id);
        if (!Visible)
            return;
        ProducerRow.SetText(_name, Tr(_upgrade.Name));
        ProducerRow.SetText(_detail, TextFormat.Fill(Tr("UPGRADE_DETAIL"), Tr(_targetKey), Times(_upgrade.Multiplier)));
        ProducerRow.SetText(_buy, Numbers.Format(_upgrade.Cost));
        _buy.Disabled = !economy.CanUpgrade(Id);
    }

    private static string TargetKey(string target, Catalog catalog)
    {
        if (target == "all" || target == "tap")
            return $"TARGET_{target.ToUpperInvariant()}";
        return catalog.Producer(target)?.Name ?? target;
    }

    /// <summary>2 as "2", 1.5 as "1.5".</summary>
    private static string Times(double m) =>
        m == Math.Floor(m) ? ((long)m).ToString(CultureInfo.InvariantCulture) : m.ToString(CultureInfo.InvariantCulture);
}
