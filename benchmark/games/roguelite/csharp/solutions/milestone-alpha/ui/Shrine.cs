namespace Wickerdeep;

using System;
using Godot;

/// <summary>
/// The shrine between runs: banked embers buy vigor, each level one more hp for the wick in every run after. Main saves
/// the bank when the screen closes.
/// </summary>
public partial class Shrine : Control
{
    private SaveData? _save;
    private Label _title = null!;
    private Label _embers = null!;
    private Label _vigorLabel = null!;
    private Button _vigor = null!;
    private Button _back = null!;

    public event Action? Closed;

    public void Setup(SaveData save)
    {
        _save = save;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _embers = GetNode<Label>("Box/EmbersLabel");
        _vigorLabel = GetNode<Label>("Box/VigorLabel");
        _vigor = GetNode<Button>("Box/VigorButton");
        _back = GetNode<Button>("Box/BackButton");
        _save ??= new SaveData();
        _vigor.Pressed += BuyVigor;
        _back.Pressed += () => Closed?.Invoke();
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    public void BuyVigor()
    {
        if (Meta.BuyVigor(_save!))
            RefreshText();
    }

    private void RefreshText()
    {
        MetaProgress meta = _save!.Meta;
        int level = meta.Vigor;
        _title.Text = Tr("SHRINE_TITLE");
        _embers.Text = TextFormat.Fill(Tr("SHRINE_EMBERS"), meta.Embers);
        _vigorLabel.Text = TextFormat.Fill(Tr("SHRINE_VIGOR"), level, Meta.VigorMax, Meta.MaxHp(_save));
        _vigor.Text = level < Meta.VigorMax ? TextFormat.Fill(Tr("SHRINE_BUY"), Meta.VigorCost(level)) : Tr("SHRINE_FULL");
        _vigor.Disabled = level >= Meta.VigorMax || meta.Embers < Meta.VigorCost(level);
        _back.Text = Tr("SHRINE_BACK");
    }
}
