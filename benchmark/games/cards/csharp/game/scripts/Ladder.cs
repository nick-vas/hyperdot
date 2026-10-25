namespace Lanternfen;

/// <summary>
/// What a save says about the rivals: each one's wins and losses, and which are open. Rival 1 is always open; the next
/// opens once the one before it is beaten.
/// </summary>
public static class Ladder
{
    /// <summary>Records a finished duel against a rival.</summary>
    public static void Record(SaveData save, int rival, bool won)
    {
        string key = rival.ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (!save.Record.TryGetValue(key, out RivalRecord? entry))
        {
            entry = new RivalRecord();
            save.Record[key] = entry;
        }
        if (won)
            entry.Wins += 1;
        else
            entry.Losses += 1;
    }

    public static int Wins(SaveData save, int rival) => Find(save, rival)?.Wins ?? 0;

    public static int Losses(SaveData save, int rival) => Find(save, rival)?.Losses ?? 0;

    public static bool IsBeaten(SaveData save, int rival) => Wins(save, rival) > 0;

    public static bool IsUnlocked(SaveData save, int rival) => rival <= 1 || IsBeaten(save, rival - 1);

    /// <summary>Every win against every rival, for the victory screen.</summary>
    public static int TotalWins(SaveData save)
    {
        int total = 0;
        foreach (RivalRecord entry in save.Record.Values)
            total += entry.Wins;
        return total;
    }

    private static RivalRecord? Find(SaveData save, int rival) =>
        save.Record.TryGetValue(rival.ToString(System.Globalization.CultureInfo.InvariantCulture), out RivalRecord? entry) ? entry : null;
}
