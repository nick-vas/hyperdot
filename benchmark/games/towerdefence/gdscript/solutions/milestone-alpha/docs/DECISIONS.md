# Decisions

- 2026-10-01 Prototype verdict: PROCEED. Building a maze that the pests visibly follow is the fun part; keep it.
- The battle lives in plain classes (Battle, PathMap, Enemy), so tests and the bot play whole maps without a scene; the game node only feeds it ticks.
- Paths come from AStarGrid2D on four neighbours. A placement re-paths every pest at once; a placement that would cut off the gate or any pest is refused.
- Towers, upgrades, pests, maps and waves are data checked by the data runner; what the numbers mean (upgrades better and dearer, a way through every map) is a test.
- Each battle draws its pests' speeds from its own seeded generator, so a --seed replays a map exactly.
