# Glimmerpit

**Pitch:** up to four glimmers duel in a walled pit, over the network or against bots: dodge round the pillars, fire
sparks, and be the last one standing; three rounds win the match.

**Pillars:** your own glimmer answers at once, whatever the connection (prediction, never a visible correction); the
server alone decides who was hit; a match is always four, bots filling the empty slots, so nobody waits.

## Features

### F1 Moving and shooting
Priority: must
Done when:
- eight-way movement, aim with the mouse or a stick, sparks on a cooldown and a dash, the same code on server and client

### F2 Rounds and the match
Priority: must
Done when:
- five hits put a glimmer out; the last one standing wins the round; three rounds win the match; the courts alternate

### F3 Netcode
Priority: must
Done when:
- an authoritative server; client prediction and reconciliation with no correction at 100 ms; hits decided on the server

### F4 Players and bots
Priority: must
Done when:
- bots fill every empty slot; players join and leave in the middle of a match, and a round still ends when one is left

### F5 Dedicated server
Priority: must
Done when:
- --server runs headless match after match; `soak` with three clients joining and leaving passes for minutes

### F6 Menus, pause, settings
Priority: must
Done when:
- menu, host, join, pause, volume and language; settings and the record saved; old settings still load

### F7 Languages
Priority: should
Done when:
- English, French and German, every visible text through tr()

## Soak

The dedicated server is soaked on every change (the workflow's soak job) with three clients that leave and rejoin every
few seconds: `hyperdot.ps1 soak -Clients 3 -Seconds 120 -Warmup 3 -MaxGrowthMbPerHour 200`. The server reports players,
peer_records, matches and refused_claims, and fails when it keeps more peer records than it has players.
