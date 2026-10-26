namespace SaltmereCrossing;

using System;
using System.Collections.Generic;
using System.Text.Json.Nodes;

/// <summary>
/// One playthrough of the story: the node it is at, the flags and the choices taken so far (the history). Engine-light,
/// so tests play whole stories without a scene; the story scene only shows it.
/// </summary>
public sealed class Story
{
    public Story(StoryGraph graph)
    {
        Graph = graph;
        Reset();
    }

    /// <summary>The story moved to a node.</summary>
    public event Action<string>? NodeEntered;
    /// <summary>A flag changed value through a choice's effects: the flag, its value before and after.</summary>
    public event Action<string, int, int>? FlagChanged;
    /// <summary>The story reached an ending node.</summary>
    public event Action<string>? Ended;

    public StoryGraph Graph { get; }

    public string NodeId { get; private set; } = "";

    /// <summary>Flag id -> value; every flag of the graph is present, 0 until a choice changes it.</summary>
    public SortedDictionary<string, int> Flags { get; } = new(StringComparer.Ordinal);

    /// <summary>The ids of the choices taken, in order.</summary>
    public List<string> History { get; } = new();

    /// <summary>Back to the first node with every flag at 0 and no history.</summary>
    public void Reset()
    {
        NodeId = Graph.Start;
        Flags.Clear();
        foreach (string flag in Graph.FlagIds)
            Flags[flag] = 0;
        History.Clear();
    }

    /// <summary>A flag's value; 0 when the story does not have it.</summary>
    public int Flag(string id) => Flags.TryGetValue(id, out int value) ? value : 0;

    public StoryNode? Current() => Graph.Node(NodeId);

    /// <summary>The ending this story is at, or "".</summary>
    public string Ending() => Graph.EndingAt(NodeId);

    public bool IsOver() => Ending().Length > 0;

    /// <summary>The choices the player is offered now: those out of this node whose needs hold. None at an ending.</summary>
    public List<Choice> Available()
    {
        var output = new List<Choice>();
        if (IsOver())
            return output;
        foreach (Choice choice in Graph.ChoicesFrom(NodeId))
        {
            if (IsOpen(choice))
                output.Add(choice);
        }
        return output;
    }

    public bool IsOpen(Choice choice)
    {
        // A choice into a node the story does not have would leave the player with nothing: never offer it.
        if (!Graph.HasNode(choice.To))
            return false;
        return Conditions.Holds(choice.Needs, Flags);
    }

    public bool CanChoose(string choiceId)
    {
        foreach (Choice choice in Available())
        {
            if (choice.Id == choiceId)
                return true;
        }
        return false;
    }

    /// <summary>
    /// Takes a choice offered now: its effects (raise, then set, then clear), the history, then the node it leads to.
    /// False when the choice is not offered.
    /// </summary>
    public bool Choose(string choiceId)
    {
        if (!CanChoose(choiceId))
            return false;
        Choice choice = Graph.Choice(choiceId)!;
        foreach (string flag in choice.Raise)
            Change(flag, Flag(flag) + 1);
        foreach (string flag in choice.Set)
            Change(flag, 1);
        foreach (string flag in choice.Clear)
            Change(flag, 0);
        History.Add(choiceId);
        NodeId = choice.To;
        NodeEntered?.Invoke(NodeId);
        if (IsOver())
            Ended?.Invoke(Ending());
        return true;
    }

    private void Change(string flag, int value)
    {
        int before = Flag(flag);
        Flags[flag] = value;
        if (before != value)
            FlagChanged?.Invoke(flag, before, value);
    }

    /// <summary>The story as the save keeps it: node, flags (flag -> value) and history.</summary>
    public JsonObject ToDict()
    {
        return new JsonObject
        {
            ["node"] = NodeId,
            ["flags"] = FlagValues(),
            ["history"] = HistoryIds(),
        };
    }

    private JsonObject FlagValues()
    {
        var flags = new JsonObject();
        foreach (KeyValuePair<string, int> pair in Flags)
            flags[pair.Key] = pair.Value;
        return flags;
    }

    private JsonArray HistoryIds()
    {
        var ids = new JsonArray();
        foreach (string id in History)
            ids.Add(JsonValue.Create(id));
        return ids;
    }

    /// <summary>A story carried on from ToDict(); flags the save lacks start at 0, and a node the story no longer has is the start.</summary>
    public static Story FromDict(StoryGraph graph, JsonObject data)
    {
        var story = new Story(graph);
        string saved = JsonData.Text(data["node"], graph.Start);
        story.NodeId = graph.HasNode(saved) ? saved : graph.Start;
        if (data["flags"] is JsonObject flags)
        {
            foreach (KeyValuePair<string, JsonNode?> pair in flags)
                story.Flags[pair.Key] = JsonData.Int(pair.Value, 0);
        }
        foreach (string id in JsonData.Ids(data["history"]))
            story.History.Add(id);
        return story;
    }

    /// <summary>A new story with these choices taken in order; it stops at the first one that is not offered.</summary>
    public static Story Replay(StoryGraph graph, IEnumerable<string> choiceIds)
    {
        var story = new Story(graph);
        foreach (string id in choiceIds)
        {
            if (!story.Choose(id))
                break;
        }
        return story;
    }
}
