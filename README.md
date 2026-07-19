# KodexBar Suite

[Leer en español](README.es.md)

KodexBar Suite is a small Linux desktop toolkit with two independent packages:

- `packages/kodexbar` is a KDE Plasma 6 widget for ordered CodexBar quota summaries.
- `packages/ai-cli-control` is the local `ai` selector for launching and updating provider CLIs, including read-only conversation recovery with `ai recover`.

The packages are maintained in one repository and can be installed together from the repository root. Each package remains usable and testable on its own.

## Install the suite

On CachyOS, Arch Linux, or another Linux system with KDE Plasma 6:

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

The installer:

- installs or updates the Plasma applet with the technical ID `org.kde.plasma.kodexbar`.
- installs `ai` at `~/.local/share/ai-cli-control/ai`.
- creates `~/.local/bin/ai` only when that link is absent or already belongs to this project.
- never uses `sudo` and never replaces an unrelated `~/.local/bin/ai`.

The shared Plasma ID is intentional. This package replaces an existing upstream KodexBar installation in place, while preserving the Plasma configuration associated with that ID.

After installation, add **KodexBar Suite** to a Plasma panel if it is not already present. Open the widget popup to view quotas. Use the AI button or the Plasma context menu to open `ai-cli-control` and update provider CLIs.

## Installation channels

KodexBar Suite will ship through three channels. This repository already contains the packaging sources. AUR and KDE Store listings become usable only after the matching release is published.

### AUR (full suite, Arch and CachyOS)

When the package is published, install the full suite from the AUR:

```bash
paru -S kodexbar-suite
```

The same package also appears in graphical AUR helpers on CachyOS such as Shelly or Octopi. The package installs the Plasma widget, `ai`, `kodexbar-quotas`, `kodexbar-panel`, `kodexbar-tray`, and the tray icons under `/usr`. Packaging sources live in `packaging/aur/`.

### KDE Store (widget only)

The Plasma widget alone can be published to [store.kde.org](https://store.kde.org) as a `.plasmoid` built by `packaging/kde-store/build-plasmoid.sh`. That channel delivers the applet UI. The data engine (`kodexbar-quotas` and related tools) still comes from the AUR package or from the repository `install.sh` below.

### Manual install from this repository

Clone and run the root installer for a user-local layout under `~/.local` (no `sudo`):

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

## Update

```bash
git pull --ff-only
./install.sh
```

The root installer is idempotent. It updates both packages without touching provider credentials or configuration.

## Uninstall

```bash
./uninstall.sh
```

The root uninstaller removes the Plasma package only when the installed package identifies itself as KodexBar Suite and removes `ai` only when its ownership marker and symlink match this project. If either ownership check fails, it refuses that removal instead of touching another installation.

## Use a package independently

The package directories retain their standalone workflows:

```bash
make -C packages/ai-cli-control check
./packages/ai-cli-control/install.sh

bash packages/kodexbar/scripts/validate.sh
kpackagetool6 -t Plasma/Applet -u packages/kodexbar
```

Do not install the upstream widget and this fork at the same time because both use `org.kde.plasma.kodexbar`.

## Development checks

```bash
make test
make check
```

`make check` runs the KodexBar fixture, JSON, XML, QML, and safety checks, the `ai-cli-control` Python and shell checks, and root script syntax and whitespace checks. It does not install or uninstall anything.

## Repository layout

```text
KodexBar-Suite/
├── packages/
│   ├── kodexbar/
│   └── ai-cli-control/
├── install.sh
├── uninstall.sh
├── Makefile
├── LICENSE
└── NOTICE.md
```

The subtree history preserves the original package histories. `packages/kodexbar` is a maintained fork of [tylxr59/KodexBar](https://github.com/tylxr59/KodexBar). `ai-cli-control` is independent original work. See the package notices and the root [NOTICE.md](NOTICE.md) for attribution.

## License

The package-specific license files remain authoritative:

- [KodexBar package license](packages/kodexbar/LICENSE)
- [ai-cli-control package license](packages/ai-cli-control/LICENSE)

Both packages use the MIT License. The root [LICENSE](LICENSE) explains the scope of the monorepo license files.
