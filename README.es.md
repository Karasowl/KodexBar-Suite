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

### AUR (suite completa, Arch y CachyOS)

Cuando el paquete esté publicado, instala la suite completa desde AUR:

```bash
paru -S kodexbar-suite
```

El mismo paquete también aparece en gestores gráficos de AUR en CachyOS como Shelly u Octopi. El paquete instala el widget de Plasma, `ai`, `kodexbar-quotas`, `kodexbar-panel`, `kodexbar-tray` y los iconos del tray bajo `/usr`. Las fuentes de empaquetado están en `packaging/aur/`.

### KDE Store (solo el widget)

El widget de Plasma se puede publicar en [store.kde.org](https://store.kde.org) como un `.plasmoid` generado por `packaging/kde-store/build-plasmoid.sh`. Ese canal entrega solo la interfaz del applet. El motor de datos (`kodexbar-quotas` y herramientas relacionadas) sigue viniendo del paquete AUR o del `install.sh` del repositorio que se describe abajo.

### Instalación manual desde este repositorio

Clona y ejecuta el instalador raíz para un layout de usuario en `~/.local` (sin `sudo`):

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

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
