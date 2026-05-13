# Godot MCP Notes

This folder keeps safe, local-only MCP configuration examples for Godot agent work.

Use `gopeak.codex.example.json` as a template only. Copy it into the MCP client config location used by the current client, then adjust `GODOT_PATH` if the Godot binary moves.

Safety rules for this project:

- Keep `GOPEAK_TOOL_PROFILE=compact` unless a task explicitly needs a broader tool group.
- Keep bridge host on `127.0.0.1`; do not expose the bridge to LAN/WAN.
- Do not run scene/resource write tools as a substitute for repo patches during normal code tasks.
- Do not use runtime input, screenshot, or debugger tools to mutate save data unless the task explicitly asks for runtime testing.
- Treat MCP output as runtime evidence, not as canonical documentation.
