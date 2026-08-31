# Native system packages

KodexBar Suite uses one system payload for its Debian and RPM packages. The shared staging script is `packaging/system/stage-package.sh`. It installs only runtime files under `/usr` and leaves package ownership, upgrades, and removal to the distribution package manager.

## Coverage

| Distribution family | Installation path | Automated validation |
| --- | --- | --- |
| Arch, CachyOS, Manjaro | AUR recipe in `packaging/aur` | Arch package metadata and portable install |
| Debian and Ubuntu | `packaging/deb/build-deb.sh` | Debian 12, Ubuntu 22.04, Ubuntu 24.04 |
| Fedora and RHEL 9 or 10 compatible systems | `packaging/rpm/build-rpm.sh` | Fedora, AlmaLinux 9, AlmaLinux 10 |
| Other Linux systems with Python 3.10 or newer | Root `install.sh` under `~/.local` | Portable container matrix |

Official DEB and RPM files are attached to tagged [GitHub Releases](https://github.com/Karasowl/KodexBar-Suite/releases/latest), together with the Plasma widget and `SHA256SUMS`. These recipes reproduce those system packages from source.

## Build a DEB

Install Bash, Python 3.10 or newer, and `dpkg-deb`. On Debian and Ubuntu, `dpkg-deb` is provided by `dpkg` and the complete package build toolset is available through `dpkg-dev`.

```bash
artifact="$(./packaging/deb/build-deb.sh)"
sudo apt install "$artifact"
```

The result is written to `packaging/deb/dist/` unless `KODEXBAR_OUTPUT_DIR` is set.

## Build an RPM

Install Bash, Python, `rpm-build`, `sed`, `tar`, and `gzip`. Fedora and RHEL 10 compatible builds require system Python 3.10 or newer. RHEL 9 compatible builds depend on the parallel `python3.11` package and do not replace the system Python 3.9 interpreter.

```bash
artifact="$(./packaging/rpm/build-rpm.sh)"
sudo dnf install "$artifact"
```

The result is written to `packaging/rpm/dist/` unless `KODEXBAR_OUTPUT_DIR` is set. Fedora and RHEL 10 compatible systems produce the general `kodexbar-suite-VERSION-RELEASE.noarch.rpm`. RHEL 9 compatible systems produce `kodexbar-suite-VERSION-RELEASE.el9.noarch.rpm` with a parallel Python 3.11 dependency.

## Package contract

Both native packages install the same commands, Plasma applet, local model drivers, tray icons, licenses, and documentation. Plasma is optional. On a non-Plasma desktop, the data engine, tray, and panel adapters remain usable.

The package version comes from `packages/kodexbar/metadata.json`. `KODEXBAR_PACKAGE_RELEASE` can increment the distribution package release without changing the application version.

Run the shared payload validation with:

```bash
make system-package-check
```
