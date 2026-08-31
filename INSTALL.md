# Install KodexBar Suite

[Leer en español](INSTALL.es.md)

This guide walks you through installing KodexBar Suite when you are new to Linux package tools. It describes the windows you will see and what to do in each one.

KodexBar Suite shows AI CLI quota summaries on the desktop and includes a small `ai` selector for launching and updating provider CLIs.

---

## 1. Arch, CachyOS, Manjaro, and derivatives (recommended)

This is the main path. The AUR package installs the Plasma widget, the `ai` tools, and the companion CLI for Codex, Grok, and Antigravity quotas.

Package name: `kodexbar-suite`

Dependency it pulls in: `codexbar-cli-bin`

### Option A: Graphical install with Shelly (CachyOS)

Shelly is the graphical package manager many CachyOS desktops ship with. Steps:

1. Open **Shelly**.
2. In the left sidebar, open the **AUR** section (the icon labeled **A**).
3. Open the **Install** tab.
4. Search for `kodexbar-suite`.
5. Check the box next to the package name.
6. Click **Install Aur Package(s)**.

#### Windows that appear and what to do

You may see these dialogs in order. Names can vary slightly by helper version, but the meaning is the same.

**a. "Review PKGBUILD changes"**

This is the standard AUR safety step. It shows the package recipe so anyone can review what will be built and installed.

- It can appear **twice**: once for `kodexbar-suite` and once for its dependency `codexbar-cli-bin`.
- What to do: read it if you want, then click **Confirm**.

**b. "Select Optional Dependencies"**

This lists optional components for different desktops.

What to do:

- On **KDE Plasma**, you usually do not need to check anything if items already show as **already installed**.
- On **GNOME** or **COSMIC**, mark `python-gobject` and `libayatana-appindicator` if you want the system tray indicator.
- Mark `konsole` only if you want the widget to open the `ai` selector in a terminal.
- Then click **Confirm**.

**c. Password for sudo**

Pacman needs administrator rights to install system packages. Enter your user password when asked. This is normal.

After the install finishes, go to [After installation](#after-installation).

### Option B: Terminal

If you prefer the command line, or if a graphical helper fails:

```bash
paru -S kodexbar-suite
```

If you use `yay` instead of `paru`:

```bash
yay -S kodexbar-suite
```

`paru` and `yay` are helpers that let pacman install packages from the AUR. They are not separate repositories.

The terminal flow asks the same things as Shelly:

1. Show or review the PKGBUILD (press Enter to accept the default).
2. Optional dependencies (press Enter to skip extras unless you need them).
3. Your sudo password so pacman can install.

Press **Enter** to accept default answers at each prompt unless you know you need a different choice.

---

### After installation

1. **Add the widget to a Plasma panel**
   - Right-click an empty area of the panel.
   - Choose **Add Widgets** (wording may vary slightly by Plasma version).
   - Search for **KodexBar**.
   - Drag the widget onto the panel, or double-click it to add it.

2. **Quotas appear automatically**
   - Open the widget popup.
   - If you already have provider CLIs installed and signed in (for example Claude, Codex, Grok, or Antigravity), their quotas show up without editing config files.
   - The suite does not invent placeholder numbers. Only real data from detected CLIs appears.

---

## 2. Widget only from the KDE Store

If you only want the Plasma applet UI from Get New Widgets:

1. Right-click the panel and open **Add Widgets**.
2. Open **Get New Widgets** (or the equivalent store entry).
3. Search for KodexBar and install the plasmoid.

That channel delivers the **widget UI only**. The data engine and companion tools come from the AUR package or from a manual install (see below).

If the engine is missing, the widget shows a setup card with the install command for your distro. Arch family systems get `paru -S kodexbar-suite`. Other Linux systems get the portable clone command below. After the next refresh, quotas appear when CLIs are available.

---

## 3. Debian, Ubuntu, Fedora, and other distros without AUR

The repository contains native DEB and RPM builders plus the universal `./install.sh`. A DEB or RPM is public only when it appears in the assets of a tagged GitHub release. Until then, you can build it from the source checkout or use the portable option.

### Option A: native DEB on Debian or Ubuntu

This installs the suite under `/usr` and lets APT own upgrades and removal.

```bash
sudo apt update
sudo apt install git python3 dpkg-dev
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
artifact="$(./packaging/deb/build-deb.sh)"
sudo apt install "$artifact"
```

The DEB builder is checked on Debian 12, Ubuntu 22.04, and Ubuntu 24.04.

### Option B: native RPM on Fedora or a RHEL 9 or 10 compatible system

This installs the suite under `/usr` and lets DNF own upgrades and removal.

```bash
sudo dnf install git python3 rpm-build sed tar gzip
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
artifact="$(./packaging/rpm/build-rpm.sh)"
sudo dnf install "$artifact"
```

The RPM builder is checked on Fedora, AlmaLinux 9, and AlmaLinux 10. Fedora and RHEL 10 compatible builds use the system `python3` and require version 3.10 or newer. On RHEL 9 compatible systems, DNF installs `python3.11` alongside the system Python 3.9 and KodexBar uses only that parallel interpreter.

### Option C: portable user install on any supported distribution

This installs under your home directory and does not use `sudo`:

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

### Requirements and optional desktop integrations

- Python 3.10 or newer
- `git` when installing from a source checkout
- `kpackagetool6` only when the portable installer should add the Plasma widget
- For the tray on GNOME or COSMIC: PyGObject plus Ayatana AppIndicator (`gir1.2-ayatanaappindicator3-0.1` on Debian/Ubuntu, `libayatana-appindicator-gtk3` on Fedora, `libayatana-appindicator` on Arch). GNOME also needs the AppIndicator extension.

### What each desktop gets

| Desktop | Result |
| --- | --- |
| Plasma 6 | Widget plus data engine. The portable installer needs `kpackagetool6` |
| GNOME or COSMIC | Data engine plus `kodexbar-tray --autostart-install` |
| Hyprland + Waybar | Data engine plus `kodexbar-panel --waybar-snippet` |
| XFCE | Data engine plus Generic Monitor: `kodexbar-panel --format text --pango`, 60s period |

If `kpackagetool6` is missing, the installer still succeeds. It installs the engine, tray, and panel tools, and tells you which command to use on your desktop.

If `~/.local/bin` is not on `PATH`, the portable installer prints the exact warning. Add that directory so `ai`, `kodexbar-quotas`, `kodexbar-panel`, and `kodexbar-tray` can be found.

For Codex, Grok, and Antigravity quota numbers, also install the official CodexBar CLI and keep `codexbar` on your `PATH`. See the [CodexBar CLI documentation](https://github.com/steipete/CodexBar/blob/main/docs/cli.md).

On Plasma, add the widget the same way as in [After installation](#after-installation). On GNOME or COSMIC run `kodexbar-tray --autostart-install`. On Hyprland paste the snippet from `kodexbar-panel --waybar-snippet`.

---

## 4. Uninstall

How you remove the suite depends on how you installed it.

### Installed with pacman / AUR (`kodexbar-suite`)

```bash
sudo pacman -R kodexbar-suite codexbar-cli-bin
```

Remove `codexbar-cli-bin` only if nothing else needs it.

### Installed with APT / DEB (`kodexbar-suite`)

```bash
sudo apt remove kodexbar-suite
```

### Installed with DNF / RPM (`kodexbar-suite`)

```bash
sudo dnf remove kodexbar-suite
```

### Installed with `./install.sh`

From a clone of this repository:

```bash
./uninstall.sh
```

That script only removes the user-local install under `~/.local` and refuses to touch files that do not belong to this project.

---

## 5. Known problems

**Graphical AUR helper fails with "Permission denied" on its cache**

Some helpers (including Shelly) have been seen to fail when a cache directory such as `~/.cache/Shelly` is owned by root. That is a helper cache issue, not a KodexBar Suite bug.

What to do: install from the terminal instead:

```bash
paru -S kodexbar-suite
```

**Report problems**

Open an issue on the project repository:

https://github.com/Karasowl/KodexBar-Suite/issues

Include your distribution, how you tried to install (Shelly, paru, yay, APT, DNF, or `./install.sh`), and the exact error text.
