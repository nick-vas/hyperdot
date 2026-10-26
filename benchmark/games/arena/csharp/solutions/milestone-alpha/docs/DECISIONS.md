# Decisions

- 2026-10-05 Prototype verdict: PROCEED. Last-one-standing rounds on a small pit give a decision every few seconds.
- Multiplayer from the first commit: an authoritative server, inputs not positions, the same Sim code on both sides.
- The rules and the netcode are plain classes (ArenaMatch, ArenaServer, ArenaClient), so tests play matches without
  a scene or a socket; SimLink adds the delay ENet cannot simulate.
- Positions are whole pixels and walls axis-aligned rectangles, so prediction matches the server exactly.
- Bots fill every empty slot, so a match is always four and nobody waits for players.
