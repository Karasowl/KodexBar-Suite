# ai-cli-control

Documentación en español. La documentación completa en inglés está en [README.md](README.md).

`ai-cli-control` es un selector local para iniciar Codex, Claude, Grok o Antigravity desde el directorio actual de la terminal. Conserva el directorio de trabajo y el entorno de la CLI elegida. Es trabajo original y no es un fork de KodexBar.

Este paquete también se mantiene dentro del [monorepo KodexBar Suite](../../README.es.md). Desde la raíz de ese repositorio, usa `./install.sh` para instalarlo junto con el widget de Plasma. El `install.sh` del paquete sigue disponible para uso independiente.

## Funciones

- Selecciona proveedor, modelo, esfuerzo de razonamiento y modo de permisos.
- Usa KDialog cuando está disponible, Yad como respaldo gráfico y un selector interactivo de terminal como último respaldo.
- Lee los modelos de Codex desde la caché local y consulta los catálogos de Grok y Antigravity al seleccionarlos.
- Ejecuta una o varias actualizaciones de CLI en orden fijo y continúa después de un fallo.
- Recupera historiales locales de conversación de Codex, Claude, Grok y Antigravity en modo de solo lectura con `ai recover`.
- Muestra comandos de inicio y actualización con `--dry-run`.
- Usa inglés de forma predeterminada. Los entornos en español reciben texto en español. `--language en` y `--language es` sustituyen la detección de locale.
- Conserva cada comando de inicio y actualización como arreglo de argumentos sin evaluación de shell.
- Incluye `kodexbar-quotas`, un motor local de cuotas para el widget KodexBar Suite, y `kodexbar-panel`, un adaptador compacto para barras no KDE.

## Requisitos

- Python 3.10 o posterior.
- Al menos una CLI de proveedor compatible en `PATH` cuando se vaya a iniciar.
- `kdialog` o `yad` opcionales para selección gráfica.
- Una caché legible de modelos Codex en `~/.codex/models_cache.json` al seleccionar Codex.

Antigravity debe estar disponible como `agy` y autenticado antes de consultar su catálogo. Este proyecto no instala, elimina, autentica ni configura ninguna CLI de proveedor.

## Inicio rápido

Ejecuta desde un clon o una versión extraída:

```bash
./ai
./ai --text
./ai --dry-run
./ai --language es --text
./ai --version
```

El selector gráfico usa primero KDialog y después Yad. Sin sesión gráfica usa el selector de texto. Cancelar cualquier paso termina correctamente y no inicia una CLI.

El selector de texto acepta opciones numeradas. Para la lista de actualizaciones acepta números separados por comas, `all` o `0` para cancelar.

## Recuperar conversaciones

`ai recover` es un motor independiente y de solo lectura para transportar una conversación local previa al contexto actual. Lee los historiales de los proveedores sin modificarlos. Funciona desde el clon o después de instalarlo:

```bash
./ai recover claude
ai recover claude last
ai recover codex 3 --save
ai recover grok ID_DE_SESION --stdout --max-chars 800
```

Usa primero la recuperación posicional:

- `ai recover PROVEEDOR` lista las sesiones del proyecto actual, de más reciente a más antigua, con índices estables desde 1.
- `ai recover PROVEEDOR last`, un índice o un id de sesión recupera esa conversación. En una terminal ofrece copiar, guardar Markdown o mostrar el dump. `--copy`, `--save [RUTA]` y `--stdout` eligen el destino directamente.
- En un pipe o redirección siempre imprime el dump normalizado sin menú, para que la automatización siga siendo segura. `--cwd` y `--max-chars` funcionan también con esta forma.

La interfaz avanzada para máquinas se conserva: `ai recover list --provider PROVEEDOR` y `ai recover dump --provider PROVEEDOR --id last`. Los proveedores son `codex`, `claude`, `grok`, `agy` y `antigravity` como alias de `agy`. Para Claude, `last` omite la sesión que parece activa y toma la sesión pasada más reciente. Los dumps muestran `[TRUNCADO: ...]` cuando la salida fue recortada.

Cuando existe el directorio de configuración de la CLI correspondiente, la instalación agrega adaptadores delgados `recover-chat` para Claude en `~/.claude/skills/recover-chat/` y Grok en `~/.grok/skills/recover-chat/`. El adaptador de Claude usa su herramienta de preguntas interactivas para seleccionar y el de Grok presenta una lista numerada en el chat. Los usuarios de Codex y Antigravity invocan `ai recover` directamente, porque no hay un mecanismo de adaptadores de usuario verificado para ellos.

## Inicio no interactivo

Los argumentos ocultos de automatización se admiten para scripts y pruebas reproducibles:

```bash
./ai --dry-run --provider codex --model gpt-5 --effort high --permissions ask
./ai --dry-run --provider claude --model opus --effort high --permissions accept-edits
./ai --dry-run --provider grok --model grok-4 --effort medium --permissions default
./ai --dry-run --provider antigravity --model 'Gemini 3.1 Pro (High)' --effort included --permissions plan
```

Los nombres de modelo de Antigravity ya incluyen su nivel. El flujo interactivo no pide esfuerzo para Antigravity y `--effort included` no agrega una bandera de esfuerzo.

## Permisos y argumentos de inicio

El selector construye comandos como arreglos de argumentos. Estas asignaciones se pasan exactamente a la CLI del proveedor:

| Proveedor | ID de permiso | Argumentos |
| --- | --- | --- |
| Codex | `read-only` | `--sandbox read-only --ask-for-approval never` |
| Codex | `ask` | `--sandbox workspace-write --ask-for-approval on-request` |
| Codex | `automatic` | `--sandbox workspace-write --ask-for-approval never` |
| Codex | `full` | `--dangerously-bypass-approvals-and-sandbox` |
| Claude y Grok | `plan`, `manual` o `default`, `accept-edits`, `auto`, `dont-ask`, `bypass` | `--permission-mode` con el valor del proveedor |
| Antigravity | `manual` | Sin argumento de permiso |
| Antigravity | `plan` | `--mode plan` |
| Antigravity | `accept-edits` | `--mode accept-edits` |
| Antigravity | `sandbox` | `--sandbox` |
| Antigravity | `full` | `--dangerously-skip-permissions` |

La disponibilidad del proveedor, el entitlement del modelo y el comportamiento de cada proveedor siguen bajo control de ese proveedor.

## Actualizar CLIs de proveedor

Elige **Actualizar CLIs** en el selector principal o usa una lista no interactiva:

```bash
./ai --update codex,grok
./ai --update all --dry-run
```

Los identificadores válidos son `codex`, `claude`, `grok` y `antigravity`. Las actualizaciones siempre se ejecutan en ese orden aunque el orden de entrada sea distinto. Los arreglos exactos de actualización son `codex update`, `claude update`, `grok update` y `agy update`.

Antes y después de cada actualización real, el selector intenta ejecutar `<cli> --version`. La salida estándar y de error de cada actualización permanece conectada a la terminal. Una CLI ausente o fallida se reporta y las CLIs restantes continúan. El estado final es `0` solo si todas las actualizaciones seleccionadas tienen éxito. `--dry-run` imprime los arreglos de actualización sin consultar versiones ni ejecutar actualizaciones.

## Instalación y eliminación

La instalación copia el ejecutable a una ubicación duradera de propiedad del usuario. Nunca deja `~/.local/bin/ai` apuntando al clon o directorio de la versión.

```bash
./install.sh
ai --version
./uninstall.sh
# Si el clon ya no existe:
~/.local/share/ai-cli-control/uninstall.sh
```

El ejecutable instalado queda en `~/.local/share/ai-cli-control/ai` y `~/.local/bin/ai` es su enlace simbólico. El motor independiente `recover.py`, `kodexbar-quotas`, `kodexbar-panel` y una copia de `uninstall.sh` quedan junto al ejecutable para eliminarlos después de borrar el clon. No usa `sudo`. La instalación no sustituye un comando local existente que no pertenezca al proyecto. Solo instala adaptadores si existe el directorio de su CLI y nunca reemplaza un skill `recover-chat` ajeno. La eliminación verifica los marcadores de propiedad y borra solo archivos del proyecto. Ambos scripts son idempotentes.

## Motor de cuotas

`kodexbar-quotas` es el comando local predeterminado del widget. Lee los proveedores habilitados desde `~/.config/codexbar/config.json`. Consulta Claude directamente en `https://api.anthropic.com/api/oauth/usage` con el token OAuth de Claude y un límite de 15 segundos. Codex, Antigravity, Grok, credenciales ausentes, respuestas inesperadas y fallos normales de solicitud usan `codexbar` upstream por proveedor. El HTTP 429 de Claude se conserva como error de proveedor para que el widget mantenga la lectura en caché. `cost --format json --json-only` se reenvía a upstream, o devuelve `[]` si upstream no está instalado.

Codex, Antigravity y Grok siguen como pasos directos a upstream en esta versión. Durante el port desde el código Swift, sus rutas de adquisición dependían de cookies y sesiones del dashboard, además de esquemas de respuesta privados de cada proveedor, incluidos endpoints protobuf, que no se pueden reproducir fielmente con Python de la biblioteca estándar. Solo Claude expuso la solicitud OAuth JSON directa que se implementa aquí.

Las invocaciones de uso con banderas que el motor no implementa, como `--status`, se delegan por completo a `codexbar` upstream.

El instalador lo coloca en `~/.local/share/ai-cli-control/kodexbar-quotas` y enlaza `~/.local/bin/kodexbar-quotas` solo cuando ese enlace pertenece a este paquete.

## Adaptadores de panel

`kodexbar-panel` invoca primero el motor `kodexbar-quotas` que está a su lado y después el comando disponible en `PATH`. Muestra la línea compacta de cuotas `Cx`, `Cl`, `Gk` y `Ag` usada por el conjunto, con uso de sesión y semanal cuando está disponible. Tiene un límite total de 20 segundos para el motor y devuelve un error corto en vez de un traceback cuando no hay datos de cuotas.

```bash
kodexbar-panel --format text
kodexbar-panel --format text --pango
kodexbar-panel --format waybar
kodexbar-panel --format json --providers codex,claude
kodexbar-panel --waybar-snippet
```

### Waybar en Hyprland y Omarchy

Imprime el módulo listo para pegar y el ejemplo CSS con `kodexbar-panel --waybar-snippet`. Agrega el bloque `custom/kodexbar` a la configuración de Waybar y añade `custom/kodexbar` a `modules-left`, `modules-center` o `modules-right`. El módulo ejecuta `kodexbar-panel --format waybar`, usa el tipo de retorno JSON de Waybar y se actualiza cada 60 segundos. Su carga de texto y tooltip ya está escapada para Pango, así que deja desactivada la opción `escape` de Waybar para evitar un doble escape.

En Hyprland, agrega las reglas CSS comentadas del snippet a la hoja de estilo usada por tu configuración de Waybar, normalmente `~/.config/waybar/style.css`. En Omarchy, los temas sobrescriben el CSS de Waybar mediante `~/.config/omarchy/current/theme/waybar.css`, así que agrega las reglas en ese punto de enganche del tema. El instalador nunca modifica ninguna de esas configuraciones de usuario.

### Monitor genérico de XFCE

Agrega el complemento de panel **Generic Monitor**, abre sus propiedades y define **Command** como:

```bash
kodexbar-panel --format text --pango
```

Activa el marcado Pango en el complemento cuando esa opción esté disponible y usa un periodo de 60 segundos. El comando también funciona sin Pango, pero los colores de severidad solo se muestran con Pango activado.

## Desarrollo

```bash
make test
make check
make install
make uninstall
```

`make test` ejecuta pruebas unitarias de Python. `make check` ejecuta pruebas unitarias, compilación de Python, comprobaciones de sintaxis Bash y comprobaciones estáticas de seguridad. Las pruebas usan ejecutables temporales y nunca ejecutan actualizaciones reales de proveedores.

## Seguridad

Este proyecto no usa `eval`, `shell=True` ni `os.system`. No incluye credenciales ni configuración de proveedores. Lee [SECURITY.md](SECURITY.md) para reportar vulnerabilidades.

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md) antes de proponer un cambio. Las versiones se documentan en [CHANGELOG.md](CHANGELOG.md).

## Licencia y avisos

Copyright 2026 Ismael (Karasowl). Se publica bajo la [licencia MIT](LICENSE). Los avisos de productos de terceros están en [NOTICE.md](NOTICE.md).
