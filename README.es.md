# KodexBar Suite

[Read in English](README.md)

> Monitor de cuotas y uso de IA para Linux, con widget de KDE Plasma 6 para asistentes de programación.

[![Última release](https://img.shields.io/github/v/release/Karasowl/KodexBar-Suite?display_name=tag&sort=semver)](https://github.com/Karasowl/KodexBar-Suite/releases/latest)
[![KDE Plasma 6](https://img.shields.io/badge/KDE%20Plasma-6-1d99f3?style=flat-square)](https://kde.org/plasma-desktop/)
[![Licencia: MIT](https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square)](LICENSE)

KodexBar Suite concentra en un panel de Linux las cuotas y el uso de asistentes de programación con IA. El widget muestra uso en vivo, reinicios, gasto y errores. En Compact panel puedes ocultar un proveedor que está en ERR.

![KodexBar en Plasma 6: chips en la barra, cuotas, Claude en ERR y luego ocultar Claude en Compact panel](docs/kodexbar-demo.gif)

[Clip completo de 26s](docs/kodexbar-demo.mp4)

El widget de KDE Plasma 6 muestra ventanas de uso, reinicios, créditos, costos, cuentas y errores sin obligarte a abrir un panel distinto para cada asistente. La suite admite Arch y CachyOS, Debian y Ubuntu, Fedora, sistemas compatibles con RHEL 9 y 10, y otras distribuciones Linux con Python 3.10 o posterior.

Las vías públicas de instalación son [AUR](https://aur.archlinux.org/packages/kodexbar-suite), los archivos DEB y RPM nativos de [GitHub Releases](https://github.com/Karasowl/KodexBar-Suite/releases/latest), y el instalador local de este repositorio. Si te evita abrir varios paneles de proveedores, marca el proyecto con una estrella para que otros usuarios de Linux puedan encontrarlo.

El repositorio contiene dos paquetes instalables y sus herramientas compartidas:

- `packages/kodexbar` es un widget de KDE Plasma 6 para mostrar cuotas y uso ordenados mediante CodexBar.
- `packages/ai-cli-control` es el selector local `ai` para iniciar y actualizar las CLI de proveedores, con recuperación de conversaciones en solo lectura mediante `ai recover`.
- `local-ai`, instalado junto con `ai-cli-control`, es un monitor JSON opcional para runtimes de modelos locales. No instala runtimes ni descarga pesos.
- `kodexbar-skills`, instalado junto con `ai-cli-control`, inventaría y sincroniza skills entre seis proveedores con confirmación, preflight y respaldo de copias idénticas.

Cada paquete sigue siendo utilizable y comprobable por separado, mientras que el instalador raíz ofrece la experiencia completa.

## Qué monitoriza

La suite tiene rutas dedicadas de cuotas para estos proveedores:

| Proveedor | Cobertura |
| --- | --- |
| Claude Code | Lectura nativa de cuotas con perfiles de varias cuentas |
| OpenAI Codex | Lectura nativa de cuotas, créditos y perfiles de varias cuentas |
| Cursor | Uso nativo del ciclo mensual con vistas de Models, Other, Total, Auto y API |
| Grok | Datos nativos de uso y facturación desde la sesión local |
| OpenCode Go | Detección nativa de cuota e identidad del proveedor |
| Antigravity | Ruta opcional mediante la CLI CodexBar upstream |

El widget también puede mostrar otros proveedores devueltos por CodexBar cuando están habilitados. La suite no inventa valores de cuota cuando un proveedor no devuelve datos reales.

Además del monitor de cuotas, la suite incluye:

- **Perfiles de varias cuentas** para Codex y Claude sin guardar secretos de proveedores en la suite.
- **Monitor de modelos locales** mediante `local-ai`, con métricas del runtime y controles seguros.
- **Inventario y sincronización de skills** entre Codex, Claude, Grok, Gemini CLI, OpenCode y Hermes.
- **AI CLI Control** para iniciar y actualizar las CLI de proveedores desde el directorio actual.

## Instalar el conjunto

**¿Nuevo en esto? Sigue la [guía de instalación paso a paso](INSTALL.es.md).**

La vía portable funciona en cualquier distribución Linux admitida y no necesita acceso de administrador:

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

El instalador:

- instala o actualiza el applet de Plasma cuando está `kpackagetool6`.
- igual instala el motor de datos, la bandeja y las herramientas de panel si Plasma no está, para que GNOME, COSMIC, Hyprland/Waybar y XFCE puedan usar la suite.
- instala `ai` en `~/.local/share/ai-cli-control/ai`.
- crea `~/.local/bin/ai` solo cuando el enlace no existe o ya pertenece a este proyecto.
- nunca usa `sudo` ni reemplaza un `~/.local/bin/ai` ajeno.
- avisa si `~/.local/bin` no está en `PATH`.

El ID compartido de Plasma es intencional. Este paquete reemplaza en el mismo lugar una instalación upstream de KodexBar y conserva la configuración de Plasma asociada a ese ID.

Después de instalar, agrega **KodexBar Suite** a un panel de Plasma si todavía no aparece. Abre el popup del widget para consultar las cuotas. Usa el botón AI o el menú contextual de Plasma para abrir `ai-cli-control` y actualizar las CLI de proveedores.

El popup Signal Console usa los destinos con etiqueta Proveedores, Local y Skills. Local lee su inventario mediante `local-ai`, que admite raíces explícitas y runtimes comunes en localhost. Muestra solo métricas reales del runtime, conserva atenuados los modelos instalados sin montar y expone solo acciones que el runtime puede realizar de forma segura. Consulta [la documentación del monitor local](packages/ai-cli-control/README.es.md#monitor-de-modelos-locales) y las plantillas portables en `packages/ai-cli-control/examples/`.

El tab **Skills** usa `kodexbar-skills` para comparar Codex, Claude, Grok, Gemini CLI, OpenCode y Hermes. Una matriz permite preparar cambios por skill y proveedor, seleccionar todos los destinos seguros o una columna completa y revisar el lote antes de aplicarlo. Refrescar solo lee. Las copias idénticas se respaldan, los enlaces compartidos pueden desactivarse sin borrar la fuente y el contenido divergente queda bloqueado. Consulta [el contrato del motor de skills](packages/ai-cli-control/README.es.md#inventario-y-sincronización-de-skills).

## Canales de instalación

Usa el formato nativo de tu distribución cuando esté disponible. El instalador portable sigue siendo la alternativa universal.

### AUR (Arch y CachyOS)

Instala la suite desde AUR:

```bash
paru -S kodexbar-suite
```

El mismo paquete también aparece en gestores gráficos de AUR en CachyOS como Shelly u Octopi. Las fuentes de empaquetado están en `packaging/aur/`.

Después de instalar o actualizar, el paquete detecta las sesiones activas que realmente tienen KodexBar en un panel y recarga `plasmashell` automáticamente. Los paneles pueden desaparecer durante unos segundos. Las sesiones que no usan el widget no se reinician.

Qué instala el paquete bajo `/usr`:

- Widget de Plasma, `ai`, `kodexbar-quotas`, `kodexbar-panel`, `kodexbar-tray`, `local-ai`, `kodexbar-skills`, sus controladores integrados e iconos del tray.
- Primer uso sin configuración manual: si no existe `~/.config/codexbar/config.json`, la suite detecta qué CLI de IA ya tienes e habilita sus cuotas sola. No hace falta editar archivos ni leer documentación de proveedores.

Cómo funcionan las cuotas después de instalar:

- **Claude, Codex y Grok** obtienen sus cuotas de forma nativa con `kodexbar-quotas` (Python stdlib). Claude necesita credenciales OAuth de Claude Code. Codex lee `~/.codex/auth.json`. Grok lee `~/.grok/auth.json`. Si las credenciales faltan o caducaron, se muestra un mensaje de re-login (sin refresco automático de OAuth).
- **Antigravity** sigue necesitando la CLI compañera [`codexbar` de steipete](https://github.com/steipete/CodexBar). Esa misma CLI es un respaldo opcional para Codex y Grok cuando la ruta nativa falla por red o infraestructura reintentable. En Arch/CachyOS instálala como `codexbar-cli-bin` (no es el paquete AUR homónimo de otro proyecto).
- Una configuración de CodexBar que ya exista no se sobrescribe. El widget **no** inventa números de cuota.

### DEB (Debian y Ubuntu)

Descarga e instala el paquete oficial de la release con:

```bash
curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.6/kodexbar-suite_0.12.6-1_all.deb
sudo apt install ./kodexbar-suite_0.12.6-1_all.deb
```

Para construir el mismo paquete desde un checkout del repositorio:

```bash
sudo apt install git python3 dpkg-dev
artifact="$(./packaging/deb/build-deb.sh)"
sudo apt install "$artifact"
```

El paquete instala la suite bajo `/usr` y después se puede actualizar o quitar mediante APT. El constructor se comprueba en Debian 12, Ubuntu 22.04 y Ubuntu 24.04.

### RPM (Fedora y sistemas compatibles con RHEL 9 o 10)

En Fedora o un sistema compatible con RHEL 10, descarga e instala el RPM general:

```bash
curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.6/kodexbar-suite-0.12.6-1.noarch.rpm
sudo dnf install ./kodexbar-suite-0.12.6-1.noarch.rpm
```

En un sistema compatible con RHEL 9, como AlmaLinux 9 o Rocky Linux 9, usa el paquete dedicado que depende del Python 3.11 paralelo:

```bash
curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.6/kodexbar-suite-0.12.6-1.el9.noarch.rpm
sudo dnf install ./kodexbar-suite-0.12.6-1.el9.noarch.rpm
```

Para construir el mismo paquete desde un checkout del repositorio:

```bash
sudo dnf install git python3 rpm-build sed tar gzip
artifact="$(./packaging/rpm/build-rpm.sh)"
sudo dnf install "$artifact"
```

Ambos RPM son independientes de la arquitectura. Las compilaciones para Fedora y sistemas compatibles con RHEL 10 usan el `python3` del sistema y exigen la versión 3.10 o posterior. La compilación `.el9` instala la dependencia paralela `python3.11` sin reemplazar el Python 3.9 del sistema. El constructor se comprueba en Fedora, AlmaLinux 9 y AlmaLinux 10.

### GitHub Releases

GitHub Releases proporciona el archivo fuente, DEB, archivos RPM, widget de Plasma y archivo `SHA256SUMS` correspondientes. Verifica los assets descargados con `sha256sum -c SHA256SUMS` desde el mismo directorio.

### KDE Store (canal solo para el widget)

KDE Store es un canal de distribución separado solo para el widget de Plasma. El `.plasmoid` que se publica se genera con `packaging/kde-store/build-plasmoid.sh` y su versión sale de `packages/kodexbar/metadata.json`. Ese canal entrega solo la interfaz del applet. El motor de datos (`kodexbar-quotas` y herramientas relacionadas) viene de AUR, un DEB o RPM nativo, o del `install.sh` del repositorio que se describe abajo. Si el widget se instala sin el motor, el popup muestra una tarjeta de guía con el comando AUR en la familia Arch, o el `./install.sh` portable en otras distros, más el enlace al repositorio. Cuando la suite ya está instalada, el siguiente refresco detecta tus CLI y muestra sus cuotas sin configurar proveedores a mano.

### Instalación manual desde este repositorio

Clona y ejecuta el instalador raíz para un layout de usuario en `~/.local` (sin `sudo`):

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

En una instalación manual (no Arch), para las cuotas de Antigravity (y el respaldo opcional de Codex/Grok) también hay que instalar la CLI oficial de CodexBar y tener `codexbar` en el `PATH`. Consulta la [documentación de la CLI de CodexBar](https://github.com/steipete/CodexBar/blob/main/docs/cli.md).

### Migrar desde una instalación manual en `~/.local` al paquete

Una instalación manual previa bajo `~/.local` tiene prioridad sobre el paquete del sistema: un `PATH` típico pone `~/.local/bin` antes de `/usr/bin`, y Plasma prefiere el applet de usuario sobre `/usr/share/plasma/plasmoids`. Para usar solo los archivos empaquetados:

1. Desde un clon de este repositorio (el mismo árbol con el que instalaste), ejecuta `./uninstall.sh`. Ese script solo toca `~/.local` y respeta sus comprobaciones de propiedad. No elimina un paquete del sistema.
2. Reinicia plasmashell para que Plasma recargue el plasmoid del sistema, por ejemplo: `systemctl --user restart plasma-plasmashell.service` (o cierra sesión y vuelve a entrar).

Después, `which ai` y `which kodexbar-quotas` deberían resolver bajo `/usr/bin` cuando el paquete esté instalado.

## Actualizar

```bash
git pull --ff-only
./install.sh
```

El instalador raíz es idempotente. Actualiza ambos paquetes sin tocar credenciales ni configuración de proveedores y recarga la sesión Plasma actual cuando KodexBar está colocado en un panel.

## Desinstalar

```bash
./uninstall.sh
```

El desinstalador raíz elimina el paquete de Plasma solo cuando el paquete instalado se identifica como KodexBar Suite. Elimina `ai` solo cuando coinciden el marcador de propiedad y el enlace simbólico de este proyecto. Si alguna comprobación falla, rechaza esa eliminación en lugar de tocar otra instalación.

## Usar un paquete por separado

Los directorios conservan sus flujos independientes:

```bash
make -C packages/ai-cli-control check
./packages/ai-cli-control/install.sh

bash packages/kodexbar/scripts/validate.sh
kpackagetool6 -t Plasma/Applet -u packages/kodexbar
```

No instales al mismo tiempo el widget upstream y este fork porque ambos usan `org.kde.plasma.kodexbar`.

## Comprobaciones de desarrollo

```bash
make test
make check
```

`make check` ejecuta las comprobaciones de fixtures, JSON, XML, QML y seguridad de KodexBar, las comprobaciones de Python y shell de `ai-cli-control`, las pruebas del contenido compartido DEB/RPM y la sintaxis y espacios de los scripts raíz. No instala ni desinstala nada.

## Estructura del repositorio

```text
KodexBar-Suite/
├── packages/
│   ├── kodexbar/
│   └── ai-cli-control/
├── packaging/
│   ├── aur/
│   ├── deb/
│   ├── rpm/
│   └── system/
├── install.sh
├── uninstall.sh
├── Makefile
├── LICENSE
└── NOTICE.md
```

El historial de cada paquete se conserva mediante subárboles. `packages/kodexbar` es un fork mantenido de [tylxr59/KodexBar](https://github.com/tylxr59/KodexBar). `ai-cli-control` es trabajo original independiente. Consulta los avisos de cada paquete y el [NOTICE.md](NOTICE.md) raíz para la atribución.

## Licencia

Los archivos de licencia de cada paquete siguen siendo la fuente autoritativa:

- [Licencia del paquete KodexBar](packages/kodexbar/LICENSE)
- [Licencia del paquete ai-cli-control](packages/ai-cli-control/LICENSE)

Ambos paquetes usan la licencia MIT. El [LICENSE](LICENSE) raíz explica el alcance de los archivos de licencia del monorepo.
