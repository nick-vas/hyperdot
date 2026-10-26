namespace Cinderloop;

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;
using Godot;

/// <summary>Who made what, from credits.json (written by the kit's credits command from assets.json).</summary>
public partial class Credits : Control
{
    public const string CreditsPath = "res://credits.json";

    private Label _title = null!;
    private Label _text = null!;
    private Button _back = null!;

    public event Action? Closed;

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _text = GetNode<Label>("Box/Text");
        _back = GetNode<Button>("Box/BackButton");
        _back.Pressed += () => Closed?.Invoke();
        _text.Text = string.Join("\n", ReadLines(CreditsPath));
        RefreshText();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("CREDITS_TITLE");
        _back.Text = Tr("CREDITS_BACK");
    }

    /// <summary>The credits as lines: each section's heading (a translation key) and its entries, empty sections left out.</summary>
    public static List<string> ReadLines(string path)
    {
        var lines = new List<string>();
        if (!Godot.FileAccess.FileExists(path))
            return lines;
        JsonNode? parsed;
        try
        {
            parsed = JsonNode.Parse(Godot.FileAccess.GetFileAsString(path));
        }
        catch (JsonException)
        {
            return lines;
        }
        if (parsed is not JsonObject root || root["sections"] is not JsonArray sections)
            return lines;
        foreach (JsonNode? node in sections)
        {
            if (node is not JsonObject section || section["entries"] is not JsonArray entries || entries.Count == 0)
                continue;
            lines.Add(TranslationServer.Translate(JsonData.Text(section["heading"], "")).ToString());
            foreach (JsonNode? item in entries)
            {
                if (item is JsonObject entry)
                    lines.Add($"{JsonData.Text(entry["text"], JsonData.Text(entry["title"], ""))} ({JsonData.Text(entry["licence"], "")})");
            }
            lines.Add("");
        }
        return lines;
    }
}
