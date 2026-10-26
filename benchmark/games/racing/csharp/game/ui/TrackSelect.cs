namespace Cinderloop;

using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;

/// <summary>One button per track, open once the track before was finished in the top places, with each track's best lap.</summary>
public partial class TrackSelect : Control
{
    private Tracks? _tracks;
    private int _unlocked = 1;
    private IReadOnlyDictionary<string, int> _best = new Dictionary<string, int>();
    private Label _title = null!;
    private GridContainer _grid = null!;
    private Button _back = null!;

    public event Action<int>? Chosen;
    public event Action? Closed;

    public void Setup(Tracks tracks, int unlocked, IReadOnlyDictionary<string, int> best)
    {
        _tracks = tracks;
        _unlocked = unlocked;
        _best = best;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _grid = GetNode<GridContainer>("Box/Grid");
        _back = GetNode<Button>("Box/BackButton");
        _tracks ??= Tracks.FromFiles();
        foreach (TrackRow row in _tracks.Rows)
        {
            int id = row.Id;
            var button = new Button
            {
                Name = $"Track{id}Button",
                CustomMinimumSize = new Vector2(420, 88),
                Disabled = id > _unlocked,
            };
            button.AddThemeFontSizeOverride("font_size", 26);
            button.Pressed += () => Chosen?.Invoke(id);
            button.SetMeta("track", id);
            _grid.AddChild(button);
        }
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
        _title.Text = Tr("SELECT_TITLE");
        _back.Text = Tr("SELECT_BACK");
        foreach (Node node in _grid.GetChildren())
        {
            var button = (Button)node;
            int id = button.GetMeta("track").AsInt32();
            string text = Tr(_tracks!.Row(id)?.Name ?? "");
            if (_best.TryGetValue(id.ToString(CultureInfo.InvariantCulture), out int best))
                text += "  " + TextFormat.Fill(Tr("SELECT_BEST"), Race.FormatMs(best));
            button.Text = text;
        }
    }
}
