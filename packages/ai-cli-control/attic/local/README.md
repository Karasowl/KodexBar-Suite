# Local model monitor (parked)

This directory parks the `local-ai` system without deleting it.

Parked on 2026-09-19 because the Local tab was hard to maintain across
machines and the widget now ships Providers + Skills only.

Contents:

- `local-ai`: JSON inventory and safe control surface for local runtimes.
- `local_ai_drivers/`: built-in runtime drivers and descriptor contract.
- `examples/`: portable `local-ai.json` template and llama.cpp router unit.
- `tests/test_local_ai.py`: unit tests for the parked engine.

Nothing in this directory is installed, packaged, or called by the widget.
`install.sh`, `uninstall.sh`, `Makefile`, packaging scripts, and the Plasma
UI skip it on purpose.

To bring it back:

1. Move the files back to `packages/ai-cli-control/`.
2. Re-add the install, packaging, widget tab, docs, and test wiring.
3. Run `make -C packages/ai-cli-control check`.
