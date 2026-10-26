namespace Glimmerpit;

using System;
using Godot;

/// <summary>Joining a match someone hosts: the host's address, then Join.</summary>
public partial class Join : Control
{
    private Label _title = null!;
    private Label _addressLabel = null!;
    private LineEdit _address = null!;
    private Button _join = null!;
    private Button _back = null!;

    public event Action<string>? JoinPressed;
    public event Action? Closed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _addressLabel = GetNode<Label>("Box/AddressLabel");
        _address = GetNode<LineEdit>("Box/AddressEdit");
        _join = GetNode<Button>("Box/JoinButton");
        _back = GetNode<Button>("Box/BackButton");
        _join.Pressed += OnJoin;
        _address.TextSubmitted += _ => OnJoin();
        _back.Pressed += () => Closed?.Invoke();
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("JOIN_TITLE");
        _addressLabel.Text = Tr("JOIN_ADDRESS");
        _join.Text = Tr("JOIN_JOIN");
        _back.Text = Tr("JOIN_BACK");
    }

    private void OnJoin()
    {
        string address = _address.Text.StripEdges();
        JoinPressed?.Invoke(address != "" ? address : "127.0.0.1");
    }
}
