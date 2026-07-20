# KodexBar Suite

[Read in English](README.md)

KodexBar Suite es un pequeño conjunto de herramientas de escritorio para Linux con dos paquetes independientes:

- `packages/kodexbar` es un widget de KDE Plasma 6 para mostrar cuotas ordenadas mediante CodexBar.
- `packages/ai-cli-control` es el selector local `ai` para iniciar y actualizar las CLI de proveedores, con recuperación de conversaciones en solo lectura mediante `ai recover`.

Los paquetes se mantienen en un solo repositorio y pueden instalarse juntos desde la raíz. Cada paquete sigue siendo utilizable y comprobable por separado.

## Instalar el conjunto

En CachyOS, Arch Linux u otro sistema Linux con KDE Plasma 6:

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

El instalador:

- instala o actualiza el applet de Plasma con el ID técnico `org.kde.plasma.kodexbar`.
- instala `ai` en `~/.local/share/ai-cli-control/ai`.
- crea `~/.local/bin/ai` solo cuando el enlace no existe o ya pertenece a este proyecto.
- nunca usa `sudo` ni reemplaza un `~/.local/bin/ai` ajeno.

El ID compartido de Plasma es intencional. Este paquete reemplaza en el mismo lugar una instalación upstream de KodexBar y conserva la configuración de Plasma asociada a ese ID.

Después de instalar, agrega **KodexBar Suite** a un panel de Plasma si todavía no aparece. Abre el popup del widget para consultar las cuotas. Usa el botón AI o el menú contextual de Plasma para abrir `ai-cli-control` y actualizar las CLI de proveedores.

## Canales de instalación

KodexBar Suite se distribuirá por tres canales. Este repositorio ya incluye las fuentes de empaquetado. Las entradas de AUR y de KDE Store solo serán utilizables cuando se publique la versión correspondiente.

### AUR (Arch y CachyOS)

Cuando el paquete esté publicado, instala la suite desde AUR:

```bash
paru -S kodexbar-suite
```

El mismo paquete también aparece en gestores gráficos de AUR en CachyOS como Shelly u Octopi. Las fuentes de empaquetado están en `packaging/aur/`.

Qué instala el paquete bajo `/usr`:

- Widget de Plasma, `ai`, `kodexbar-quotas`, `kodexbar-panel`, `kodexbar-tray` e iconos del tray.
- **Cuotas nativas de Claude** dentro de `kodexbar-quotas` cuando hay credenciales OAuth de Claude en `~/.claude/.credentials.json` (por ejemplo tras iniciar sesión en Claude Code). La configuración de proveedores de CodexBar en `~/.config/codexbar/config.json` elige qué proveedores están habilitados cuando ese archivo existe.
- Para **Codex, Grok y Antigravity**, `kodexbar-quotas` también requiere la CLI upstream [`codexbar` de steipete](https://github.com/steipete/codexbar). Esa CLI **no** forma parte de este paquete y **no** es el paquete AUR homónimo de otro proyecto. Si necesitas esos proveedores, instala el `codexbar` de steipete por tu cuenta.

En una instalación limpia sin `~/.config/codexbar/config.json`, las cuotas de Claude funcionan de inmediato si ya hay una sesión de Claude Code iniciada (ruta nativa, sin configuración extra). El resto de proveedores sigue necesitando el `codexbar` upstream de steipete en el `PATH` o la configuración de proveedores de CodexBar. Si la CLI upstream está presente y no hay archivo de configuración, la solicitud completa se sigue delegando a esa CLI. Sin configuración, sin upstream y sin credenciales de Claude, el widget muestra un error de guía de configuración para Claude en vez de un fallo silencioso. El widget **no** inventa números de cuota.

### KDE Store (solo el widget)

El widget de Plasma se puede publicar en [store.kde.org](https://store.kde.org) como un `.plasmoid` generado por `packaging/kde-store/build-plasmoid.sh`. Ese canal entrega solo la interfaz del applet. El motor de datos (`kodexbar-quotas` y herramientas relacionadas) sigue viniendo del paquete AUR o del `install.sh` del repositorio que se describe abajo. Con sesión de Claude Code iniciada, las cuotas de Claude funcionan sin archivo de configuración de CodexBar. Codex, Grok y Antigravity necesitan el `codexbar` upstream de steipete en el `PATH` o la configuración de proveedores de CodexBar. Cuando esa CLI upstream está presente y falta la configuración, la solicitud completa se delega a ella.

### Instalación manual desde este repositorio

Clona y ejecuta el instalador raíz para un layout de usuario en `~/.local` (sin `sudo`):

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

### Migrar desde una instalación manual en `~/.local` al paquete

Una instalación manual previa bajo `~/.local` tiene prioridad sobre el paquete del sistema: un `PATH` típico pone `~/.local/bin` antes de `/usr/bin`, y Plasma prefiere el applet de usuario sobre `/usr/share/plasma/plasmoids`. Para usar solo los archivos empaquetados:

1. Desde un clon de este repositorio (el mismo árbol con el que instalaste), ejecuta `./uninstall.sh`. Ese script solo toca `~/.local` y respeta sus comprobaciones de propiedad. No elimina el paquete de pacman.
2. Reinicia plasmashell para que Plasma recargue el plasmoid del sistema, por ejemplo: `systemctl --user restart plasma-plasmashell.service` (o cierra sesión y vuelve a entrar).

Después, `which ai` y `which kodexbar-quotas` deberían resolver bajo `/usr/bin` cuando el paquete esté instalado.

## Actualizar

```bash
git pull --ff-only
./install.sh
```

El instalador raíz es idempotente. Actualiza ambos paquetes sin tocar credenciales ni configuración de proveedores.

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

`make check` ejecuta las comprobaciones de fixtures, JSON, XML, QML y seguridad de KodexBar, las comprobaciones de Python y shell de `ai-cli-control`, y la sintaxis y espacios de los scripts raíz. No instala ni desinstala nada.

## Estructura del repositorio

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

El historial de cada paquete se conserva mediante subárboles. `packages/kodexbar` es un fork mantenido de [tylxr59/KodexBar](https://github.com/tylxr59/KodexBar). `ai-cli-control` es trabajo original independiente. Consulta los avisos de cada paquete y el [NOTICE.md](NOTICE.md) raíz para la atribución.

## Licencia

Los archivos de licencia de cada paquete siguen siendo la fuente autoritativa:

- [Licencia del paquete KodexBar](packages/kodexbar/LICENSE)
- [Licencia del paquete ai-cli-control](packages/ai-cli-control/LICENSE)

Ambos paquetes usan la licencia MIT. El [LICENSE](LICENSE) raíz explica el alcance de los archivos de licencia del monorepo.
