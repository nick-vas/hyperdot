# Decisions

- 2026-10-01 Prototype verdict: PROCEED. One crossing with a handful of choices is enough to feel each one matter.
- The story is data (nodes, choices, flags, endings) read by plain classes (StoryGraph, Story), so tests play whole
  stories without a scene; the story scene only types the lines out and shows the choices.
- Needs are written in the kit's criteria grammar, so the data runner checks their syntax.
- What the data runner cannot see (reachability, dead ends, flags never read) is StoryCheck's search, run by a test;
  the bot uses the same search to find its way to each ending.
- The story is saved at every line: the node, the flags and the history.
