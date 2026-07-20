# Instalar KodexBar Suite

[Read in English](INSTALL.md)

Esta guía te lleva paso a paso a instalar KodexBar Suite si no tienes experiencia con las herramientas de paquetes de Linux. Describe las ventanas que verás y qué hacer en cada una.

KodexBar Suite muestra resúmenes de cuotas de las CLI de IA en el escritorio e incluye un selector pequeño `ai` para iniciar y actualizar las CLI de los proveedores.

---

## 1. Arch, CachyOS, Manjaro y derivados (vía recomendada)

Esta es la vía principal. El paquete de AUR instala el widget de Plasma, las herramientas `ai` y la CLI compañera para las cuotas de Codex, Grok y Antigravity.

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
   - Si ya tienes instaladas e iniciadas sesión en las CLI de proveedores (por ejemplo Claude, Codex, Grok o Antigravity), sus cuotas aparecen sin editar archivos de configuración.
   - La suite no inventa números de relleno. Solo muestra datos reales de las CLI detectadas.

---

## 2. Solo el widget desde la tienda de KDE

Si solo quieres la interfaz del applet de Plasma desde Get New Widgets:

1. Clic derecho en el panel y abre **Add Widgets** o **Añadir elementos gráficos**.
2. Abre **Get New Widgets** (u Obtener nuevos elementos gráficos).
3. Busca KodexBar e instala el plasmoid.

Ese canal entrega **solo la interfaz del widget**. El motor de datos y las herramientas compañeras vienen del paquete AUR o de la instalación manual (ver abajo).

Si falta el motor, el widget muestra una tarjeta de guía con el comando exacto de instalación:

```bash
paru -S kodexbar-suite
```

Instala la suite con ese comando (o con la vía manual en distros que no son Arch). Tras el siguiente refresco, las cuotas aparecen cuando haya CLI disponibles.

---

## 3. Debian, Ubuntu, Fedora y otras distros sin AUR

Todavía **no hay paquete nativo** para estas distribuciones.

### Requisitos

- `python3`
- `git`
- **Plasma 6** si quieres el widget
- Las piezas de terminal, el ayudante de panel para Waybar y el indicador de bandeja pueden funcionar sin Plasma

### Pasos

1. Clona el repositorio y ejecuta el instalador de usuario (instala en el directorio home, **sin sudo**):

```bash
git clone https://github.com/Karasowl/KodexBar-Suite.git
cd KodexBar-Suite
./install.sh
```

2. Para los números de cuota de Codex, Grok y Antigravity, instala también la CLI oficial de CodexBar y deja `codexbar` en tu `PATH`. Consulta la [documentación de la CLI de CodexBar](https://github.com/steipete/CodexBar/blob/main/docs/cli.md).

Luego añade el widget al panel igual que en [Después de instalar](#después-de-instalar).

---

## 4. Desinstalar

Cómo quitar la suite depende de cómo la instalaste.

### Instalada con pacman / AUR (`kodexbar-suite`)

```bash
sudo pacman -R kodexbar-suite codexbar-cli-bin
```

Quita `codexbar-cli-bin` solo si nada más lo necesita.

### Instalada con `./install.sh`

Desde un clon de este repositorio:

```bash
./uninstall.sh
```

Ese script solo elimina la instalación de usuario bajo `~/.local` y se niega a tocar archivos que no pertenecen a este proyecto.

---

## 5. Problemas conocidos

**El gestor gráfico de AUR falla con "Permission denied" en su caché**

Algunos gestores (incluido Shelly) han fallado cuando un directorio de caché como `~/.cache/Shelly` es propiedad de root. Eso es un problema de la caché del gestor, no un fallo de KodexBar Suite.

Qué hacer: instala desde la terminal:

```bash
paru -S kodexbar-suite
```

**Reportar problemas**

Abre un issue en el repositorio del proyecto:

https://github.com/Karasowl/KodexBar-Suite/issues

Incluye tu distribución, cómo intentaste instalar (Shelly, paru, yay o `./install.sh`) y el texto exacto del error.
