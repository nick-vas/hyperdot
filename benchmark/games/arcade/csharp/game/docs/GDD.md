# Orbit Patrol

**Pitch:** an arcade shooter in one screen: hold the bottom of the orbit against five sectors of raider formations,
keep a combo going for bigger scores, and beat the warden at the end.

**Pillars:** readable at a glance; one more run; every hit felt (flash, shake, sound).

## Features

### F1 Ship and shots
Priority: must
Fun: sensation, challenge
Done when:
- the ship moves left and right along the bottom and fires upward

### F2 Score and combo
Priority: must
Fun: challenge
Done when:
- a destroyed enemy scores its points times 1 + combo / 5, and a miss or a hit resets the combo

### F3 Lives
Priority: must
Fun: challenge
Done when:
- an enemy or its shot costs a life, then 2 seconds of invulnerability; at zero lives the game is over

### F4 Levels and the boss
Priority: must
Fun: challenge, discovery
Done when:
- five levels from data/levels.json, the fifth ending in the boss; clearing it is victory

### F5 Menus, pause, settings, saves
Priority: could
Fun: none
Done when:
- menu, pause, volume and language settings; the best score is saved, old saves still load

### F6 Languages
Priority: could
Fun: none
Done when:
- English, French and German, every visible text through tr()
