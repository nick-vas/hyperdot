---
description: A vague report of a bug that the unit tests do not catch and only the scene check does. Measures whether the kit's full check run finds and verifies what reading and the unit tests miss.
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Edit, Write]
---

Players of this Godot 4.7 game say scoring feels off since the last update, but they could not say how. Find what is
wrong and fix it, without changing the project's tests or checks.
Godot 4.7.2 is installed at the path in the environment variable EVAL_GODOT_BIN.
Before you finish, run all of the project's checks and write only PASS or FAIL, the result of that final run, to
result.txt.
