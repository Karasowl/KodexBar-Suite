# Local runtime templates

These templates are intentionally not installed. Copy and adapt them to the user's configuration directory after reviewing the model paths and runtime versions.

- `local-ai.json` defines explicit inventory roots and localhost runtimes. An empty `roots` list means the scanner only uses runtime catalogs and conventional directories that exist.
- `llama-router.service` is a user service template for llama.cpp. It keeps one LLM resident at most and sleeps it after 120 seconds. The model directory is a portable `%h` systemd specifier, not a personal path.
- `opencode.local.jsonc` documents a local OpenAI-compatible endpoint and explicit agent permissions. It references the canonical machine rules externally. Do not copy a rules file into an OpenCode configuration.

The `local-ai` JSON interface is stable across these templates. It does not require OpenCode or llama.cpp to be installed.
