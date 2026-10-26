namespace SaltmereCrossing;

using System;
using System.Collections.Generic;
using System.Text;

/// <summary>Every state a search reached from a story.</summary>
public sealed class StorySearch
{
    public HashSet<string> Nodes { get; } = new();
    public HashSet<string> Endings { get; } = new();
    /// <summary>Ending id -> the choice ids of a shortest way there.</summary>
    public Dictionary<string, List<string>> Paths { get; } = new();
    /// <summary>Node id -> the flags of a state there where no choice is open.</summary>
    public SortedDictionary<string, string> DeadEnds { get; } = new(StringComparer.Ordinal);
    /// <summary>The search gave up after StoryCheck.MaxStates states.</summary>
    public bool Truncated { get; set; }
}

/// <summary>
/// What the data runner cannot see in the story: every node and ending reachable by some order of choices, no state
/// where no choice is open short of an ending, and every flag both written and read. The search plays every order of
/// choices from the start (flags capped just above the largest number any needs compare with, so loops end), and finds
/// the bot its way to each ending.
/// </summary>
public static class StoryCheck
{
    public const int MaxStates = 20000;

    /// <summary>Everything wrong with a story, as sentences; empty when it is sound.</summary>
    public static List<string> Problems(StoryGraph graph)
    {
        var output = new List<string>();
        if (graph.Start.Length == 0)
        {
            output.Add("the story has no nodes");
            return output;
        }
        foreach (string id in graph.ChoiceIds)
        {
            Choice choice = graph.Choice(id)!;
            if (!graph.HasNode(choice.From))
                output.Add($"choice '{id}' starts at '{choice.From}', which is no node");
            if (!graph.HasNode(choice.To))
                output.Add($"choice '{id}' leads to '{choice.To}', which is no node");
        }
        foreach (string id in graph.EndingIds)
        {
            string at = graph.Ending(id)!.Node;
            if (!graph.HasNode(at))
                output.Add($"ending '{id}' is at '{at}', which is no node");
            else if (graph.ChoicesFrom(at).Count > 0)
                output.Add($"ending '{id}' at '{at}' has choices out of it");
        }
        foreach (string id in graph.NodeIds)
        {
            if (graph.EndingAt(id).Length == 0 && graph.ChoicesFrom(id).Count == 0)
                output.Add($"node '{id}' is no ending and has no choice out of it");
        }
        // Flags in the order first met, each with the last choice that reads or writes it.
        var readOrder = new List<string>();
        var writtenOrder = new List<string>();
        var readBy = new Dictionary<string, string>();
        var writtenBy = new Dictionary<string, string>();
        foreach (string id in graph.ChoiceIds)
        {
            Choice choice = graph.Choice(id)!;
            foreach (string flag in Conditions.Keys(choice.Needs))
                Note(readOrder, readBy, flag, id);
            foreach (IReadOnlyList<string> effects in new[] { choice.Raise, choice.Set, choice.Clear })
            {
                foreach (string flag in effects)
                    Note(writtenOrder, writtenBy, flag, id);
            }
        }
        var named = new List<string>(readOrder);
        named.AddRange(writtenOrder);
        foreach (string flag in named)
        {
            if (!graph.HasFlag(flag))
                output.Add($"flag '{flag}' of choice '{(readBy.TryGetValue(flag, out string? reader) ? reader : writtenBy[flag])}' is not in flags.json");
        }
        foreach (string flag in graph.FlagIds)
        {
            if (!writtenBy.ContainsKey(flag))
                output.Add($"flag '{flag}' is never set");
            if (!readBy.ContainsKey(flag))
                output.Add($"flag '{flag}' is never read");
        }
        StorySearch found = Search(graph);
        foreach (string id in graph.NodeIds)
        {
            if (!found.Nodes.Contains(id))
                output.Add($"node '{id}' cannot be reached");
        }
        foreach (string id in graph.EndingIds)
        {
            if (!found.Endings.Contains(id))
                output.Add($"ending '{id}' cannot be reached");
        }
        foreach (KeyValuePair<string, string> pair in found.DeadEnds)
            output.Add($"a story can get stuck at '{pair.Key}' ({pair.Value}): no choice is open");
        if (found.Truncated)
            output.Add($"the story has more than {MaxStates} states");
        return output;
    }

    private static void Note(List<string> order, Dictionary<string, string> by, string flag, string choiceId)
    {
        if (!by.ContainsKey(flag))
            order.Add(flag);
        by[flag] = choiceId;
    }

    /// <summary>Every state reachable from a new story.</summary>
    public static StorySearch Search(StoryGraph graph) => Search(graph, null);

    /// <summary>Every state reachable from a story (a new one when null), breadth first, choices tried in file order.</summary>
    public static StorySearch Search(StoryGraph graph, Story? from)
    {
        int cap = Cap(graph);
        Story first = from == null ? new Story(graph) : Story.FromDict(graph, from.ToDict());
        Clamp(first, cap);
        var result = new StorySearch();
        var seen = new HashSet<string> { Key(first) };
        var queue = new List<(Story Story, List<string> Path)> { (first, new List<string>()) };
        int head = 0;
        while (head < queue.Count)
        {
            (Story story, List<string> path) = queue[head];
            head += 1;
            result.Nodes.Add(story.NodeId);
            if (story.IsOver())
            {
                if (result.Endings.Add(story.Ending()))
                    result.Paths[story.Ending()] = path;
                continue;
            }
            List<Choice> open = story.Available();
            if (open.Count == 0)
            {
                result.DeadEnds[story.NodeId] = FlagText(story);
                continue;
            }
            foreach (Choice choice in open)
            {
                Story next = Story.FromDict(graph, story.ToDict());
                next.Choose(choice.Id);
                Clamp(next, cap);
                string key = Key(next);
                if (seen.Contains(key))
                    continue;
                if (seen.Count >= MaxStates)
                {
                    result.Truncated = true;
                    return result;
                }
                seen.Add(key);
                var nextPath = new List<string>(path) { choice.Id };
                queue.Add((next, nextPath));
            }
        }
        return result;
    }

    /// <summary>The choices of a shortest way from a new story to an ending; empty when there is none.</summary>
    public static List<string> PathTo(StoryGraph graph, string endingId) => PathTo(graph, endingId, null);

    /// <summary>The choices of a shortest way from a story (a new one when null) to an ending; empty when there is none.</summary>
    public static List<string> PathTo(StoryGraph graph, string endingId, Story? from)
    {
        return Search(graph, from).Paths.TryGetValue(endingId, out List<string>? path) ? path : new List<string>();
    }

    /// <summary>One above the largest number any needs compare with: values above it behave alike.</summary>
    private static int Cap(StoryGraph graph)
    {
        int cap = 1;
        foreach (string id in graph.ChoiceIds)
        {
            foreach (Criterion criterion in Conditions.Parse(graph.Choice(id)!.Needs))
                cap = Math.Max(cap, criterion.Value + 1);
        }
        return cap;
    }

    private static void Clamp(Story story, int cap)
    {
        foreach (string flag in new List<string>(story.Flags.Keys))
            story.Flags[flag] = Math.Min(story.Flags[flag], cap);
    }

    /// <summary>A state: the node, the flags, and which once-only choices are spent.</summary>
    private static string Key(Story story)
    {
        var spent = new List<string>();
        foreach (string id in story.History)
        {
            if ((story.Graph.Choice(id)?.Once ?? false) && !spent.Contains(id))
                spent.Add(id);
        }
        spent.Sort(StringComparer.Ordinal);
        var values = new List<string>();
        foreach (KeyValuePair<string, int> pair in story.Flags)
            values.Add($"{pair.Key}={pair.Value}");
        return $"{story.NodeId}|{string.Join(",", values)}|{string.Join(",", spent)}";
    }

    /// <summary>The flags as the GDScript version prints them: {"flag":value,...}.</summary>
    private static string FlagText(Story story)
    {
        var text = new StringBuilder("{");
        foreach (KeyValuePair<string, int> pair in story.Flags)
        {
            if (text.Length > 1)
                text.Append(',');
            text.Append('"').Append(pair.Key).Append("\":").Append(pair.Value);
        }
        return text.Append('}').ToString();
    }
}
