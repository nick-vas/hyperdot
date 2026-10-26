namespace Bramblegate;

using System.Collections.Generic;

/// <summary>
/// What a save says about the maps: each one's best result (stars and the seeds kept), and which maps are open. The
/// first map is always open; the next opens once the one before it is cleared.
/// </summary>
public static class Progress
{
    /// <summary>Stars for a cleared map: 3 with no seed lost, 2 with at least half kept, 1 otherwise.</summary>
    public static int StarsFor(int lives, int startLives)
    {
        if (lives >= startLives)
            return 3;
        return lives * 2 >= startLives ? 2 : 1;
    }

    /// <summary>Records a cleared map, keeping the best result: more stars, then more seeds kept.</summary>
    public static void Record(SaveData save, string mapId, int lives, int startLives)
    {
        SortedDictionary<string, MapResult> progress = save.Progress;
        progress[mapId] = new MapResult { Stars = StarsFor(lives, startLives), Lives = lives };
    }

    public static int Stars(SaveData save, string mapId) => save.Progress.TryGetValue(mapId, out MapResult? result) ? result.Stars : 0;

    public static bool IsCleared(SaveData save, string mapId) => Stars(save, mapId) > 0;

    /// <summary>Whether the map at this place in the campaign (from 1) may be played.</summary>
    public static bool IsUnlocked(SaveData save, Catalog catalog, int index)
    {
        if (index <= 1)
            return true;
        MapRow? before = catalog.MapAt(index - 1);
        return before != null && IsCleared(save, before.Id);
    }

    public static int TotalStars(SaveData save)
    {
        int total = 0;
        foreach (MapResult result in save.Progress.Values)
            total += result.Stars;
        return total;
    }
}
