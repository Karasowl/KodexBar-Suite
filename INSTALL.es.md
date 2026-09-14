# Instalar KodexBar Suite

[Read in English](INSTALL.md)

Esta guía te lleva paso a paso a instalar KodexBar Suite si no tienes experiencia con las herramientas de paquetes de Linux. Describe las ventanas que verás y qué hacer en cada una.

KodexBar Suite muestra resúmenes de cuotas de las CLI de IA en el escritorio, incluidos los créditos restantes nativos de Hermes y los porcentajes restantes de Devin, e incluye un selector pequeño `ai` para iniciar y actualizar las CLI de los proveedores.

---

## 1. Arch, CachyOS, Manjaro y derivados (vía recomendada)

Esta es la vía principal. El paquete de AUR instala el widget de Plasma, las herramientas `ai` y la lectura nativa de cuotas de Claude, Codex, Cursor, Grok, OpenCode Go, Hermes y Devin. Antigravity sigue usando la CLI compañera opcional.

Nombre del paquete: `kodexbar-suite`

Dependencia que trae: `codexbar-cli-bin`

### Opción A: instalación gráfica con Shelly (CachyOS)

Shelly es el gestor gráfico de paquetes que traen muchos escritorios de CachyOS. Pasos:

1. Abre **Shelly**.
2. En la barra lateral izquierda, abre la sección **AUR** (el icono con la letra **A**).
3. Abre la pestaña **Install**.
4. Busca `kodexbar-suite`.
5. Marca la casilla junto al nombre del paquete.
6. Pulsa **Install Aur Package(s)**.

#### Ventanas que aparecen y qué hacer

Pueden salir estos diálogos en orden. Los nombres pueden variar un poco según la versión del gestor, pero el significado es el mismo.

**a. "Review PKGBUILD changes"**

Es el paso de seguridad estándar del AUR. Muestra la receta del paquete para que cualquiera pueda revisar qué se va a construir e instalar.

- Puede salir **dos veces**: una por `kodexbar-suite` y otra por su dependencia `codexbar-cli-bin`.
- Qué hacer: léela si quieres y pulsa **Confirm**.

**b. "Select Optional Dependencies"**

Lista componentes opcionales según el escritorio.

Qué hacer:

- En **KDE Plasma**, por lo general no hace falta marcar nada si los elementos ya aparecen como **already installed**.
- En **GNOME** o **COSMIC**, marca `python-gobject` y `libayatana-appindicator` si quieres el indicador de la bandeja del sistema.
- Marca `konsole` solo si quieres que el widget abra el selector `ai` en una terminal.
- Luego pulsa **Confirm**.

**c. Contraseña de sudo**

Pacman necesita permisos de administrador para instalar paquetes del sistema. Introduce la contraseña de tu usuario cuando la pida. Es normal.

Cuando termine la instalación, pasa a [Después de instalar](#después-de-instalar).

### Opción B: terminal

Si prefieres la línea de comandos, o si el gestor gráfico falla:

```bash
paru -S kodexbar-suite
```

Si usas `yay` en lugar de `paru`:

```bash
yay -S kodexbar-suite
```

`paru` y `yay` son ayudantes que permiten a pacman instalar paquetes del AUR. No son repositorios aparte.

El flujo en terminal pregunta lo mismo que Shelly:

1. Mostrar o revisar el PKGBUILD (pulsa Enter para aceptar el valor por defecto).
2. Dependencias opcionales (pulsa Enter para omitir extras salvo que las necesites).
3. Tu contraseña de sudo para que pacman pueda instalar.

Pulsa **Enter** para aceptar las respuestas por defecto en cada pregunta, salvo que sepas que necesitas otra opción.

---

### Después de instalar

1. **Añadir el widget al panel de Plasma**
   - Clic derecho en un espacio vacío del panel.
   - Elige **Add Widgets** o **Añadir elementos gráficos** (el texto puede variar según la versión de Plasma).
   - Busca **KodexBar**.
   - Arrastra el widget al panel, o haz doble clic para añadirlo.

2. **Las cuotas aparecen solas**
   - Abre el popup del widget.
   - Si ya tienes instaladas e iniciadas sesión en las CLI de proveedores (por ejemplo Claude, Codex, Cursor, Grok, Hermes, Devin o Antigravity), sus cuotas aparecen sin editar archivos de configuración.
   - Hermes aparece cuando `hermes` está en el `PATH` o `~/.hermes/auth.json` tiene un login de Nous Portal (`hermes setup --portal`). El widget muestra los créditos restantes. El porcentaje mensual solo aparece si Portal manda remaining y el tope del mes.
   - Devin aparece cuando `devin` está en el `PATH` o `~/.local/share/devin/credentials.toml` tiene un `windsurf_api_key` (`devin auth login`). El widget muestra los porcentajes restantes diarios y semanales que reporta Devin. No inventa tamaños de cuota.
   - La suite no inventa números de relleno. Solo muestra datos reales de las CLI detectadas.

---

## 2. Solo el widget desde la tienda de KDE

Si solo quieres la interfaz del applet de Plasma desde Get New Widgets:

1. Clic derecho en el panel y abre **Add Widgets** o **Añadir elementos gráficos**.
2. Abre **Get New Widgets** (u Obtener nuevos elementos gráficos).
3. Busca KodexBar e instala el plasmoid.

Ese canal entrega **solo la interfaz del widget**. El motor de datos y las herramientas compañeras vienen del paquete AUR o de la instalación manual (ver abajo).

Si falta el motor, el widget muestra una tarjeta de guía con el comando de instalación de tu distro. En la familia Arch aparece `paru -S kodexbar-suite`. En el resto de Linux aparece el comando portable de clonar el repositorio. Tras el siguiente refresco, las cuotas aparecen cuando haya CLI disponibles.

---

## 3. Debian, Ubuntu, Fedora y otras distros sin AUR

Los archivos DEB y RPM oficiales se publican en [GitHub Releases](https://github.com/Karasowl/KodexBar-Suite/releases/latest). El repositorio también contiene los constructores nativos y el `./install.sh` universal.

### Opción A: DEB nativo en Debian o Ubuntu

Esto instala la suite bajo `/usr` y deja que APT administre las actualizaciones y la desinstalación.

```bash
curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/kodexbar-suite_0.12.10-1_all.deb
sudo apt install ./kodexbar-suite_0.12.10-1_all.deb
```

Para construirlo desde el código fuente:

```bash
sudo apt update
sudo apt install git python3 dpkg-dev
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
paquete="$(./packaging/deb/build-deb.sh)"
sudo apt install "$paquete"
```

El constructor DEB se comprueba en Debian 12, Ubuntu 22.04 y Ubuntu 24.04.

### Opción B: RPM nativo en Fedora o un sistema compatible con RHEL 9 o 10

Esto instala la suite bajo `/usr` y deja que DNF administre las actualizaciones y la desinstalación. Usa el RPM general en Fedora y sistemas compatibles con RHEL 10:

```bash
curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/kodexbar-suite-0.12.10-1.noarch.rpm
sudo dnf install ./kodexbar-suite-0.12.10-1.noarch.rpm
```

Usa el RPM `.el9` dedicado en sistemas compatibles con RHEL 9:

```bash
curl -LO https://github.com/Karasowl/KodexBar-Suite/releases/download/v0.12.10/kodexbar-suite-0.12.10-1.el9.noarch.rpm
sudo dnf install ./kodexbar-suite-0.12.10-1.el9.noarch.rpm
```

Para construirlo desde el código fuente:

```bash
sudo dnf install git python3 rpm-build sed tar gzip
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
paquete="$(./packaging/rpm/build-rpm.sh)"
sudo dnf install "$paquete"
```

El constructor RPM se comprueba en Fedora, AlmaLinux 9 y AlmaLinux 10. Las compilaciones para Fedora y sistemas compatibles con RHEL 10 usan el `python3` del sistema y exigen la versión 3.10 o posterior. En sistemas compatibles con RHEL 9, DNF instala `python3.11` junto al Python 3.9 del sistema y KodexBar usa solo ese intérprete paralelo.

### Opción C: instalación portable de usuario en cualquier distribución admitida

Esto instala bajo tu directorio home y no usa `sudo`:

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

### Requisitos e integraciones opcionales de escritorio

- Python 3.10 o posterior
- `git` cuando se instala desde un checkout del código
- `kpackagetool6` solo cuando el instalador portable debe añadir el widget de Plasma
- Para la bandeja en GNOME o COSMIC: PyGObject más Ayatana AppIndicator (`gir1.2-ayatanaappindicator3-0.1` en Debian/Ubuntu, `libayatana-appindicator-gtk3` en Fedora, `libayatana-appindicator` en Arch). GNOME también necesita la extensión AppIndicator.

### Qué recibe cada escritorio

| Escritorio | Resultado |
| --- | --- |
| Plasma 6 | Widget más motor de datos. El instalador portable necesita `kpackagetool6` |
| GNOME o COSMIC | Motor de datos más `kodexbar-tray --autostart-install` |
| Hyprland + Waybar | Motor de datos más `kodexbar-panel --waybar-snippet` |
| XFCE | Motor de datos más Generic Monitor: `kodexbar-panel --format text --pango`, periodo 60s |

Si falta `kpackagetool6`, el instalador igual termina bien. Instala el motor, la bandeja y las herramientas de panel, y te dice qué comando usar en tu escritorio.

Si `~/.local/bin` no está en `PATH`, el instalador portable imprime el aviso. Añade ese directorio para que se encuentren `ai`, `kodexbar-quotas`, `kodexbar-panel` y `kodexbar-tray`.

Antigravity sigue necesitando la CLI oficial de CodexBar y `codexbar` en el `PATH`. Claude, Codex, Cursor, Grok, OpenCode Go, Hermes y Devin son nativos y no requieren ese compañero. Consulta la [documentación de la CLI de CodexBar](https://github.com/steipete/CodexBar/blob/main/docs/cli.md).

En Plasma, añade el widget igual que en [Después de instalar](#después-de-instalar). En GNOME o COSMIC ejecuta `kodexbar-tray --autostart-install`. En Hyprland pega el snippet de `kodexbar-panel --waybar-snippet`.

---

## 4. Windows 10 y 11

En Windows la suite funciona como una aplicación de bandeja más las herramientas de consola. El widget de KDE Plasma no forma parte del build de Windows.

1. Descarga `KodexBar-Suite-<versión>-windows-setup.exe` (o el zip portátil) desde [GitHub Releases](https://github.com/Karasowl/KodexBar-Suite/releases/latest).
2. Ejecuta el instalador. Se instala por usuario en `%LOCALAPPDATA%\Programs\KodexBar-Suite` y nunca pide permisos de administrador. En el camino aparecen dos tareas opcionales: iniciar KodexBar Tray con Windows y añadir las herramientas al PATH del usuario.
3. `KodexBar Tray` aparece en el área de notificación. Haz clic en el icono o usa su menú para abrir el panel de cuotas; el mismo menú refresca a demanda, abre AI CLI Control y activa el inicio automático.

Python no es necesario: el build publicado es autónomo. Los CLI de proveedores (Claude Code, Codex, Grok, Cursor, Hermes, Devin, ...) se detectan igual que en Linux, desde `~\.claude`, `~\.codex`, `~\.grok`, `~\.hermes`, `%APPDATA%\devin\credentials.toml`, y la base de datos de Cursor en `%APPDATA%\Cursor`. Los perfiles y cuentas viven en `%APPDATA%\kodexbar-suite`.

¿Prefieres no instalar? Extrae el zip donde quieras y ejecuta `KodexBarTray.exe`; la bandeja encuentra sus herramientas hermanas en la misma carpeta. Para compilar ambos artefactos, consulta [la guía de empaquetado para Windows](packaging/windows/README.md).

## 5. Desinstalar

Cómo quitar la suite depende de cómo la instalaste.

### Instalada con pacman / AUR (`kodexbar-suite`)

```bash
sudo pacman -R kodexbar-suite codexbar-cli-bin
```

Quita `codexbar-cli-bin` solo si nada más lo necesita.

### Instalada con APT / DEB (`kodexbar-suite`)

```bash
sudo apt remove kodexbar-suite
```

### Instalada con DNF / RPM (`kodexbar-suite`)

```bash
sudo dnf remove kodexbar-suite
```

### Instalada en Windows

Usa "Aplicaciones y características" (busca KodexBar Suite) o ejecuta `Uninstall.exe` dentro de `%LOCALAPPDATA%\Programs\KodexBar-Suite`. La entrada opcional del PATH y el valor de inicio automático en el registro se eliminan con la app.

### Instalada con `./install.sh`

Desde un clon de este repositorio:

```bash
./uninstall.sh
```

Ese script solo elimina la instalación de usuario bajo `~/.local` y se niega a tocar archivos que no pertenecen a este proyecto.

---

## 6. Problemas conocidos

**El gestor gráfico de AUR falla con "Permission denied" en su caché**

Algunos gestores (incluido Shelly) han fallado cuando un directorio de caché como `~/.cache/Shelly` es propiedad de root. Eso es un problema de la caché del gestor, no un fallo de KodexBar Suite.

Qué hacer: instala desde la terminal:

```bash
paru -S kodexbar-suite
```

**Reportar problemas**

Abre un issue en el repositorio del proyecto:

https://github.com/Karasowl/KodexBar-Suite/issues

Incluye tu distribución, cómo intentaste instalar (Shelly, paru, yay, APT, DNF o `./install.sh`) y el texto exacto del error.
