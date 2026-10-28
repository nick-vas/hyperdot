# Security

The kit downloads Godot and tools from their official release locations, runs your project's code (tests execute it), and in
workflows uses the permissions the calling workflow grants. Downloads are over HTTPS from the official hosts, and Godot's editor and export templates are checked against the `SHA512-SUMS.txt`
Godot publishes beside each release (a mismatch stops with `checksum-mismatch`; a release that publishes none, such as 4.0, is used with a note in the log). `init -Mcp` writes `npx -y` entries for `@satelliteoflove/godot-mcp`
and `@ryanmazzolini/minimal-godot-mcp` that fetch the latest published package when the editor bridge starts; only the `uvx`
Aseprite server is pinned. Run it only on code you trust, and give workflows the minimum
(`contents: read`; add `pull-requests: write` for the comment and `contents: write` only for releases). Do not commit signing keys or
store credentials; use Actions secrets.

Report vulnerabilities privately through GitHub's "Report a vulnerability" on this repository.
