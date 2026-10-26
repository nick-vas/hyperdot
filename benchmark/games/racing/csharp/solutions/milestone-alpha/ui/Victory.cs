namespace Cinderloop;

using System;
using Godot;

/// <summary>The end of the championship: every track finished in the top places.</summary>
public partial class Victory : Control
{
    private Label _title = null!;
    private Label _message = null!;
    private Button _menu = null!;

    public event Action? MenuPressed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _message = GetNode<Label>("Box/Message");
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
        _message.Text = Tr("VICTORY_MESSAGE");
        _menu.Text = Tr("VICTORY_MENU");
    }
}
