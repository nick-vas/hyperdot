namespace SaltmereCrossing;

using System;
using System.Collections.Generic;
using System.Text.Json.Nodes;

/// <summary>A line of the story: its chapter (1-3), who says it and its text, a translation key.</summary>
public sealed record StoryNode(string Id, int Chapter, string Speaker, string Text);

/// <summary>A flag: "count" (raised one at a time) or "switch" (set and cleared).</summary>
public sealed record Flag(string Id, string Kind);

/// <summary>An ending: the node it is, and its title, a translation key.</summary>
public sealed record Ending(string Id, string Node, string Title);

/// <summary>A choice from a node to a node, with its needs and its effects on the flags.</summary>
public sealed class Choice
{
    public string Id { get; init; } = "";
    public string From { get; init; } = "";
    public string To { get; init; } = "";
    public string Text { get; init; } = "";
    /// <summary>In the criteria grammar (Conditions); empty needs always hold.</summary>
    public string Needs { get; init; } = "";
    public IReadOnlyList<string> Raise { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> Set { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> Clear { get; init; } = Array.Empty<string>();
    /// <summary>Offered only until it has been taken in a story.</summary>
    public bool Once { get; init; }
}

/// <summary>
/// The story as data: nodes (a line of text and who says it), choices (from a node to a node, with needs and effects),
/// flags and endings, read from data/*.json. Read-only once loaded; a playthrough's state lives in Story.
/// </summary>
public sealed class StoryGraph
{
    public const string DataDir = "res://data";

    private readonly Dictionary<string, StoryNode> _nodes = new();
    private readonly Dictionary<string, Choice> _choices = new();
    private readonly Dictionary<string, Flag> _flags = new();
    private readonly Dictionary<string, Ending> _endings = new();
    private readonly Dictionary<string, List<Choice>> _from = new();
    private readonly Dictionary<string, string> _endingAt = new();
    private readonly List<string> _nodeIds = new();
    private readonly List<string> _choiceIds = new();
    private readonly List<string> _flagIds = new();
    private readonly List<string> _endingIds = new();

    /// <summary>The first node of nodes.json: where every story begins.</summary>
    public string Start { get; private set; } = "";

    /// <summary>The ids of each table, in file order.</summary>
    public IReadOnlyList<string> NodeIds => _nodeIds;
    public IReadOnlyList<string> ChoiceIds => _choiceIds;
    public IReadOnlyList<string> FlagIds => _flagIds;
    public IReadOnlyList<string> EndingIds => _endingIds;

    public static StoryGraph FromFiles() => FromFiles(DataDir);

    public static StoryGraph FromFiles(string dir)
    {
        return FromData(JsonData.ReadArray(dir + "/nodes.json"), JsonData.ReadArray(dir + "/choices.json"), JsonData.ReadArray(dir + "/flags.json"), JsonData.ReadArray(dir + "/endings.json"));
    }

    /// <summary>A story from the JSON text of its four tables, as tests write small ones.</summary>
    public static StoryGraph FromJson(string nodes, string choices, string flags, string endings)
    {
        return FromData(ParseArray(nodes), ParseArray(choices), ParseArray(flags), ParseArray(endings));
    }

    public static StoryGraph FromData(JsonArray nodeRows, JsonArray choiceRows, JsonArray flagRows, JsonArray endingRows)
    {
        var graph = new StoryGraph();
        foreach (JsonNode? item in nodeRows)
        {
            if (item is not JsonObject row)
                continue;
            string id = JsonData.Text(row["id"], "");
            graph._nodes[id] = new StoryNode(id, JsonData.Int(row["chapter"], 1), JsonData.Text(row["speaker"], "narrator"), JsonData.Text(row["text"], ""));
            graph._nodeIds.Add(id);
            if (graph.Start.Length == 0)
                graph.Start = id;
        }
        foreach (JsonNode? item in flagRows)
        {
            if (item is not JsonObject row)
                continue;
            string id = JsonData.Text(row["id"], "");
            graph._flags[id] = new Flag(id, JsonData.Text(row["kind"], "switch"));
            graph._flagIds.Add(id);
        }
        foreach (JsonNode? item in choiceRows)
        {
            if (item is not JsonObject row)
                continue;
            var choice = new Choice
            {
                Id = JsonData.Text(row["id"], ""),
                From = JsonData.Text(row["from"], ""),
                To = JsonData.Text(row["to"], ""),
                Text = JsonData.Text(row["text"], ""),
                Needs = JsonData.Text(row["needs"], ""),
                Once = JsonData.Bool(row["once"], false),
                Raise = JsonData.Ids(row["raise"]),
                Set = JsonData.Ids(row["set"]),
                Clear = JsonData.Ids(row["clear"]),
            };
            graph._choices[choice.Id] = choice;
            graph._choiceIds.Add(choice.Id);
            if (!graph._from.TryGetValue(choice.From, out List<Choice>? list))
            {
                list = new List<Choice>();
                graph._from[choice.From] = list;
            }
            list.Add(choice);
        }
        foreach (JsonNode? item in endingRows)
        {
            if (item is not JsonObject row)
                continue;
            var ending = new Ending(JsonData.Text(row["id"], ""), JsonData.Text(row["node"], ""), JsonData.Text(row["title"], ""));
            graph._endings[ending.Id] = ending;
            graph._endingIds.Add(ending.Id);
            graph._endingAt[ending.Node] = ending.Id;
        }
        return graph;
    }

    public bool HasNode(string id) => _nodes.ContainsKey(id);

    public bool HasChoice(string id) => _choices.ContainsKey(id);

    public bool HasFlag(string id) => _flags.ContainsKey(id);

    /// <summary>A node, or null when there is none.</summary>
    public StoryNode? Node(string id) => _nodes.TryGetValue(id, out StoryNode? node) ? node : null;

    public Choice? Choice(string id) => _choices.TryGetValue(id, out Choice? choice) ? choice : null;

    public Flag? Flag(string id) => _flags.TryGetValue(id, out Flag? flag) ? flag : null;

    public Ending? Ending(string id) => _endings.TryGetValue(id, out Ending? ending) ? ending : null;

    /// <summary>The choices out of a node, in file order.</summary>
    public IReadOnlyList<Choice> ChoicesFrom(string nodeId) => _from.TryGetValue(nodeId, out List<Choice>? list) ? list : Array.Empty<Choice>();

    /// <summary>The ending a node is, or "" when it is not one.</summary>
    public string EndingAt(string nodeId) => _endingAt.TryGetValue(nodeId, out string? id) ? id : "";

    private static JsonArray ParseArray(string json) => JsonNode.Parse(json) as JsonArray ?? new JsonArray();
}
