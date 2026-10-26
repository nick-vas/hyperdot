namespace SaltmereCrossing;

using System.Collections.Generic;
using Godot;

/// <summary>The history panel: every line of this story so far and the choices taken, newest last.</summary>
public partial class History : CanvasLayer
{
    private Label _title = null!;
    private ScrollContainer _scroll = null!;
    private Label _lines = null!;
    private Button _close = null!;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _scroll = GetNode<ScrollContainer>("Box/Scroll");
        _lines = GetNode<Label>("Box/Scroll/Lines");
        _close = GetNode<Button>("Box/CloseButton");
        Visible = false;
        _close.Pressed += Close;
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("HISTORY_TITLE");
        _close.Text = Tr("HISTORY_CLOSE");
    }

    public async void Open(List<string> lines)
    {
        _lines.Text = string.Join("\n\n", lines);
        Visible = true;
        _close.CallDeferred(Control.MethodName.GrabFocus);
        // The newest line is at the bottom: scroll there once the label has its size.
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        if (IsInstanceValid(_scroll))
            _scroll.ScrollVertical = (int)_scroll.GetVScrollBar().MaxValue;
    }

    public void Close()
    {
        Visible = false;
    }
}
