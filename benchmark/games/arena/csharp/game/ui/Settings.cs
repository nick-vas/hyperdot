namespace Glimmerpit;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>Volume and language. Changes apply at once; Main saves them when the screen closes.</summary>
public partial class Settings : Control
{
    /// <summary>Each language's own name, the same in every table.</summary>
    private static readonly Dictionary<string, string> LanguageNames = new()
    {
        ["en"] = "LANG_EN",
        ["fr"] = "LANG_FR",
        ["de"] = "LANG_DE",
    };

    private SettingsData? _settings;
    private Label _title = null!;
    private Label _volumeLabel = null!;
    private HSlider _volume = null!;
    private Label _languageLabel = null!;
    private HBoxContainer _languages = null!;
    private Button _back = null!;

    public event Action? Closed;

    public void Setup(SettingsData settings)
    {
        _settings = settings;
    }

    public override void _Ready()
    {
        _title = GetNode<Label>("Box/Title");
        _volumeLabel = GetNode<Label>("Box/VolumeLabel");
        _volume = GetNode<HSlider>("Box/VolumeSlider");
        _languageLabel = GetNode<Label>("Box/LanguageLabel");
        _languages = GetNode<HBoxContainer>("Box/Languages");
        _back = GetNode<Button>("Box/BackButton");
        _settings ??= SettingsStore.Defaults();
        _volume.Value = _settings.Volume;
        _volume.ValueChanged += OnVolumeChanged;
        // One button per language the game ships, so adding a translation adds its button.
        var locales = new List<string>(TranslationServer.GetLoadedLocales());
        locales.Sort(string.CompareOrdinal);
        foreach (string locale in locales)
        {
            string chosen = locale;
            var button = new Button
            {
                Name = $"{locale.Capitalize()}Button",
                CustomMinimumSize = new Vector2(170, 88),
            };
            button.SetMeta("locale", locale);
            button.Pressed += () => SetLocale(chosen);
            _languages.AddChild(button);
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
        _title.Text = Tr("SETTINGS_TITLE");
        _volumeLabel.Text = Tr("SETTINGS_VOLUME");
        _languageLabel.Text = Tr("SETTINGS_LANGUAGE");
        _back.Text = Tr("SETTINGS_BACK");
        foreach (Node node in _languages.GetChildren())
        {
            var button = (Button)node;
            string locale = button.GetMeta("locale").AsString();
            button.Text = Tr(LanguageNames.TryGetValue(locale, out string? key) ? key : locale);
        }
    }

    public void SetLocale(string locale)
    {
        _settings!.Locale = locale;
        TranslationServer.SetLocale(locale);
    }

    private void OnVolumeChanged(double value)
    {
        _settings!.Volume = value;
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)value, 0.0001f)));
    }
}
