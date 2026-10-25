namespace Bramblegate;

using System;
using Godot;

/// <summary>The end of the campaign: every map cleared, and the stars of the whole save counted.</summary>
public partial class Victory : Control
{
    private int _total;
    private Label _title = null!;
    private Label _message = null!;
    private Button _menu = null!;

    public event Action? MenuPressed;

    public void Setup(int totalStars)
    {
        _total = totalStars;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _message = GetNode<Label>("Box/MessageLabel");
        _menu = GetNode<Button>("Box/MenuButton");
        _menu.Pressed += () => MenuPressed?.Invoke();
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("VICTORY_TITLE");
        _message.Text = TextFormat.Fill(Tr("VICTORY_MESSAGE"), _total);
        _menu.Text = Tr("VICTORY_MENU");
    }
}
