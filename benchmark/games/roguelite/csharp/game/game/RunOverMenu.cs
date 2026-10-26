namespace Wickerdeep;

using System;
using Godot;

/// <summary>
/// The panel at the end of a run: out or through, how deep and how many embers go to the bank; Descend again or Back to
/// menu.
/// </summary>
public partial class RunOverMenu : CanvasLayer
{
    private bool _won;
    private int _floor = 1;
    private int _embers;
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
        _title.Text = _won ? Tr("RUN_WON") : Tr("RUN_LOST");
        _message.Text = _won ? TextFormat.Fill(Tr("RUN_WON_MESSAGE"), _embers) : TextFormat.Fill(Tr("RUN_LOST_MESSAGE"), _floor, _embers);
        _again.Text = Tr("RUN_AGAIN");
        _menu.Text = Tr("RUN_MENU");
    }

    /// <summary>embers: what goes to the bank.</summary>
    public void Open(bool won, int floorNumber, int embers)
    {
        _won = won;
        _floor = floorNumber;
        _embers = embers;
        RefreshText();
        Visible = true;
    }

    public void Close()
    {
        Visible = false;
    }
}
