# Bramblegate

**Pitch:** pests march through a hedge garden to its seed store; plant thorns, pollen puffs and acorn mortars on the
field, steer the pests into a long way round, and keep the store full through three maps.

**Pillars:** every placement changes the way the pests walk, shown at once on the field; sap is tight, so every tower is
a choice; a map is won or lost in a few minutes.

## Features

### F1 The field
Priority: must
Done when:
- a grid of cells; pests walk the shortest way from the gate to the store (AStarGrid2D), drawn on the field
- a tower may never leave the gate, or any pest on the field, without a way to the store
- a placement re-paths every pest at once, so the way drawn is the way they walk

### F2 Towers and sap
Priority: must
Done when:
- three towers, each with two upgrades, in data/towers.json and data/upgrades.json, checked by the data runner
- a fallen pest pays its reward, a cleared wave its bonus once; selling gives back 70% of what the tower cost

### F3 Waves
Priority: must
Done when:
- three maps of 4, 5 and 6 waves, the last ending with the slug queen; a wave comes after a 10 s break or when called

### F4 Balance
Priority: must
Done when:
- the bot's build clears every map over several seeds and loses a few seeds on the way; a field with no tower loses

### F5 Menus, pause, settings, saves
Priority: must
Done when:
- menu, map select, pause, volume and language; each map's best stars are saved; old saves still load

### F6 Languages
Priority: should
Done when:
- English, French and German, every visible text through tr()
