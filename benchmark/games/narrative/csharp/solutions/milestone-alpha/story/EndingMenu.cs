namespace SaltmereCrossing;

using System;
using Godot;

/// <summary>The panel over an ending: its title, how many endings are found, Cross again and Back to menu.</summary>
public partial class EndingMenu : CanvasLayer
{
    private string _titleKey = "";
    private int _found;
    private int _total;
    private Label _title = null!;
    private Label _message = null!;
    private Button _again = null!;
    private Button _menu = null!;

    public event Action? AgainPressed;
    public event Action? MenuPressed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _message = GetNode<Label>("Box/MessageLabel");
        _again = GetNode<Button>("Box/AgainButton");
        _menu = GetNode<Button>("Box/MenuButton");
        Visible = false;
        _again.Pressed += () => AgainPressed?.Invoke();
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
        _title.Text = _titleKey.Length > 0 ? Tr(_titleKey) : "";
        _message.Text = TextFormat.Fill(Tr("MENU_ENDINGS"), _found, _total);
        _again.Text = Tr("ENDING_AGAIN");
        _menu.Text = Tr("ENDING_MENU");
    }

    public void Open(string titleKey, int found, int total)
    {
        _titleKey = titleKey;
        _found = found;
        _total = total;
        RefreshText();
        Visible = true;
        _again.CallDeferred(Control.MethodName.GrabFocus);
    }

    public void Close()
    {
        Visible = false;
    }
}
