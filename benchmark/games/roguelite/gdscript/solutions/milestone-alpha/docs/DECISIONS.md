# Decisions

- 2026-10-01 Prototype verdict: PROCEED. A grid with one step every tenth of a second reads like an action game and still
  tests like a board game.
- The rules live in plain classes (Dungeon, World, Bot), so tests play whole floors without a scene; the game node only
  feeds them input and draws them.
- A floor is generated from the run's seed and its number alone, so a saved run is a few numbers and a --seed replays a
  floor exactly; the enemies wander on a stream of their own.
- Enemies hunt down one distance field, searched again only when the wick changes cell, so a swarm costs one search.
- Floors and enemies are data checked by the data runner; the generator's hard rules are a test over a sweep of seeds.
