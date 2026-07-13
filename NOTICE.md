# Notice

KodexBar Suite is a monorepo with two separately maintained packages.

## KodexBar package

`packages/kodexbar` is a fork of [tylxr59/KodexBar](https://github.com/tylxr59/KodexBar). It preserves the original MIT license and attribution. Fork-specific maintenance is provided by Ismael, known publicly as Karasowl. The package intentionally keeps the Plasma plugin ID `org.kde.plasma.kodexbar` so it can replace an installation in place.

The package obtains usage data from the independent [steipete/CodexBar](https://github.com/steipete/CodexBar) CLI. Neither the original KodexBar author nor the CodexBar maintainers endorse this fork.

## ai-cli-control package

`packages/ai-cli-control` is independent original work by Ismael, known publicly as Karasowl. It launches and updates third-party provider CLIs locally. It does not install, authenticate, configure, or represent Codex, Claude, Grok, Gemini, or Antigravity.

Those product names may be trademarks of their respective owners. Their mention does not imply affiliation, sponsorship, or endorsement.

## License files

The package-specific files remain authoritative. See [packages/kodexbar/LICENSE](packages/kodexbar/LICENSE) and [packages/ai-cli-control/LICENSE](packages/ai-cli-control/LICENSE). This notice supplements those files and does not replace them.
