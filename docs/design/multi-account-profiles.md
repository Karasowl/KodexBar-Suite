# Diseño normativo: perfiles multi-cuenta de cuotas

**Estado:** normativo. MVP implementado en engine + widget (Codex/Claude first-class, Grok/Cursor por paths, Antigravity/OpenCode Go passthrough). Gestión guiada sin JSON: página **Accounts** en Preferencias (mismo diseño del widget) y acción **Manage AI accounts**. `ai --accounts` queda como vía de terminal opcional.
**Alcance:** `kodexbar-quotas` (engine) + widget KodexBar (caché, selección, etiquetas).
**Fecha:** 2026-08-05.
**Origen:** diseño revisado a partir del código actual de KodexBar Suite y del modelo de instancias de [T3 Code](https://github.com/pingdotgg/t3code) (docs de [Codex](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-codex.md) y [Claude](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-claude.md)).

Este documento define el comportamiento deseado. El código actual es inventario, no el molde que limita el resultado.

**Afirmación del primer release:** multi-cuenta first-class para Codex y Claude. Grok después. Cursor y OpenCode Go experimentales hasta verificar aislamiento. Antigravity y desconocidos según lo que devuelva upstream.

---

## Conclusión

El diseño correcto no es «hacer que cada provider devuelva varias cuentas» de manera ad hoc. Es introducir formalmente tres niveles:

1. **Driver o provider**: `codex`, `claude`, `grok`, etc.
2. **Perfil local de credenciales**: `work`, `personal`, `client-a`.
3. **Cuenta remota real**: email, organización o `account_id`, solamente cuando el proveedor lo reporte.

La clave es que el engine itere **perfiles**, no solo providers, y que cada resultado lleve un `profileId` estable. La UI ya resuelve casi todo lo posterior: conserva entradas repetidas, asigna ordinales, mantiene caché por una clave compuesta y evita repetir el costo por provider. El engine, en cambio, recorre actualmente una lista de IDs de proveedor en forma secuencial y llama una sola vez a `fetch_provider()` por cada uno.

De T3 Code copiaría exactamente una idea: **una instancia configurada no es lo mismo que un driver**. No copiaría su materialización completa de homes. T3 necesita compartir sesiones, worktrees, skills y otros estados porque ejecuta agentes. Por eso construye un overlay Codex donde `auth.json` permanece privado y varios directorios se comparten mediante enlaces. KodexBar solo necesita leer cuotas, por lo que puede apuntar directamente al archivo de autenticación correcto y evitar toda esa complejidad.

---

## 1. Schema de configuración

### Decisión recomendada: sidecar propio

No ampliaría ni subiría de versión `~/.config/codexbar/config.json` en el MVP.

Ese archivo debe seguir siendo la fuente de verdad para:

* Qué providers están habilitados.
* El orden de providers.
* La compatibilidad con upstream CodexBar.
* La auto-configuración actual.

El código actual genera ahí un documento `version: 1` con objetos `{id, enabled}` y no sobrescribe una configuración existente. Apropiarse ahora de ese schema o convertirlo en `version: 2` introduce un acoplamiento innecesario con el decoder de upstream.

Usaría:

```text
~/.config/kodexbar-suite/profiles.json
```

La palabra **profiles** es deliberada. Un perfil normalmente representará una cuenta de suscripción, pero también puede representar un router, una instalación separada o una fuente local distinta. Así no se confunde «Claude mediante OpenRouter» con una segunda cuenta Claude.

### Schema propuesto

```json
{
 "version": 1,
 "providers": {
 "codex": {
 "profiles": [
 {
 "id": "work",
 "label": "Trabajo",
 "enabled": true,
 "credentialSource": {
 "kind": "codex-auth",
 "authFile": "~/.codex/auth.json",
 "settingsFile": "~/.codex/config.toml"
 }
 },
 {
 "id": "personal",
 "label": "Personal",
 "enabled": true,
 "credentialSource": {
 "kind": "codex-auth",
 "authFile": "~/.codex_p/auth.json",
 "settingsFile": "~/.codex/config.toml"
 }
 }
 ]
 },
 "claude": {
 "profiles": [
 {
 "id": "work",
 "label": "Trabajo",
 "credentialSource": {
 "kind": "claude-config-dir",
 "configDir": "~/.claude"
 }
 },
 {
 "id": "personal",
 "label": "Personal",
 "credentialSource": {
 "kind": "claude-config-dir",
 "configDir": "~/.claude_personal"
 }
 }
 ]
 }
 }
}
```

### Semántica exacta

`id` sería obligatorio, único dentro del provider y limitado a un slug como:

```text
[a-z0-9][a-z0-9._-]{0,63}
```

No se derivaría de email, token, `account_id` ni hash del archivo. Es un nombre estable elegido por el usuario.

`label` sería opcional y puramente visual. Puede cambiar sin invalidar la caché.

`enabled` tendría valor predeterminado `true`.

`credentialSource` sería una unión cerrada y validada por provider. No aceptaría un mapa libre de variables de entorno:

```text
default
codex-auth
claude-config-dir
grok-auth
cursor-state-db
opencodego-auth
```

Los campos concretos serían:

| Kind | Campos |
| ------------------- | ------------------------------------------------------- |
| `default` | Ninguno. Conserva el comportamiento convencional actual |
| `codex-auth` | `authFile`. `settingsFile` opcional |
| `claude-config-dir` | `configDir` |
| `grok-auth` | `authFile` |
| `cursor-state-db` | `stateDb` |
| `opencodego-auth` | `authFile` |

Para Antigravity no introduciría todavía un `kind` fingido. En la primera versión seguiría siendo `upstream-defined`: una ejecución de upstream y tantas entradas como upstream realmente entregue.

### Compatibilidad

Las reglas de migración deberían ser simples:

* Si `profiles.json` no existe, cada provider habilitado recibe un perfil sintético `default` y todo funciona exactamente como hoy.
* Si un provider no aparece en `profiles.json`, recibe ese mismo perfil sintético.
* Si aparece con `profiles`, esa lista es autoritativa. No se añade otro perfil implícito.
* Un perfil deshabilitado se omite.
* Un provider deshabilitado en `config.json` se omite durante la adquisición normal aunque tenga perfiles en el sidecar.
* El orden general sale de `config.json`. El orden de cuentas sale del array `profiles`.
* La auto-detección solo crea o usa el perfil convencional. Nunca debe escanear el home buscando posibles `auth.json` secundarios.

Un sidecar presente pero inválido no debe provocar una caída silenciosa al perfil convencional, porque podría terminar mostrando la cuenta activa equivocada. Un perfil individual inválido produce un error para ese perfil y no bloquea a sus hermanos. Un JSON globalmente ilegible debe producir un error de configuración visible, no una lectura engañosa.

También añadiría dos comandos de diagnóstico sin escritura de secretos:

```bash
kodexbar-quotas profiles validate
kodexbar-quotas profiles list --json
```

Mostrarían provider, `profileId`, label, tipo de fuente y si el archivo existe/es legible. Nunca imprimirían tokens, cookies, contenido de `auth.json` ni emails.

La alternativa de meter una extensión namespaced dentro de `config.json`, por ejemplo `extensions.kodexbarSuite`, solo la consideraría después de comprobar contra varias versiones de upstream que los campos desconocidos se preservan o ignoran correctamente. No subiría la versión raíz del archivo.

---

## 2. Cómo debe iterar el engine

### Modelo interno

Introduciría dos objetos internos:

```python
ProviderProfile(
 provider="codex",
 profile_id="personal",
 profile_label="Personal",
 credential_source=...,
 provider_order=0,
 profile_order=1,
)
```

```python
FetchContext(
 base_home=...,
 auth_file=...,
 settings_file=...,
 config_dir=...,
 state_db=...,
)
```

El flujo sería:

```text
config.json
 ↓ providers habilitados y orden
profiles.json
 ↓ perfiles y localizadores de credenciales
lista ordenada de FetchTarget
 ↓
un fetch independiente por target
 ↓
lista JSON ordenada como provider → perfil
```

Las funciones de fetch no deberían volver a consultar variables globales como `CODEX_HOME` o `GROK_HOME`. Deben recibir rutas resueltas explícitamente.

Esto es especialmente importante porque hoy algunos helpers consultan el entorno global del proceso, mientras Claude y Cursor derivan rutas desde un `home`. Ese modelo deja de ser seguro en cuanto se ejecutan cuentas concurrentemente: modificar `os.environ` para una tarea afectaría a todas las demás.

### Paralelismo

El engine actual ejecuta los providers uno detrás de otro. Con varias cuentas, los timeouts existentes de 15-30 segundos podrían acumularse y acercarse al watchdog de dos minutos del widget.

Usaría `ThreadPoolExecutor`, porque las operaciones son HTTP, SQLite y lectura de archivos, no cálculo intensivo.

Una política conservadora:

```text
global_max_workers = 4
Claude por provider = 1 simultáneo
Codex/Grok/OpenCode Go = máximo 2 simultáneos
Cursor = 1 o 2 inicialmente
Antigravity/upstream = 1
```

No expondría esos números como preferencia de usuario en el MVP.

La concurrencia no debe alterar el orden visual. Cada target recibe un índice antes de enviarse al executor. Los resultados se reordenan según esos índices antes de imprimir el JSON.

### Aislamiento de fallos

Cada perfil debe tener un límite de excepción propio:

```text
fetch(work) → entrada sana
fetch(personal) → entrada de error
fetch(client) → entrada sana
```

Un error inesperado debe transformarse en un error sanitizado, sin traceback, ruta local, encabezados HTTP o contenido de credenciales.

Cada fetch nativo configurado debe producir exactamente una entrada:

```json
{
 "provider": "codex",
 "profileId": "work",
 "profileLabel": "Trabajo",
 "source": "oauth",
 "usage": {
 "identity": {
 "providerID": "codex",
 "loginMethod": "pro"
 },
 "primary": {},
 "secondary": {},
 "updatedAt": "2026-08-06T02:30:00Z"
 },
 "engine": "kodexbar"
}
```

El error conserva la misma identidad:

```json
{
 "provider": "codex",
 "profileId": "personal",
 "profileLabel": "Personal",
 "source": "oauth",
 "error": {
 "code": 1,
 "kind": "provider",
 "category": "authentication",
 "retryable": false,
 "message": "Sign in to this Codex profile again to see quotas."
 },
 "engine": "kodexbar"
}
```

No sobrecargaría el campo actual `account` para esta función. Usaría:

* `profileId`: identidad local estable y no sensible.
* `profileLabel`: nombre opcional.
* `usage.identity.accountEmail`: email remoto opcional.
* `account`: compatibilidad con entradas upstream antiguas.

Así se evita que la caché dependa de un email vacío y se evita mostrar accidentalmente `work` dentro de una fila etiquetada como email.

### Regla crítica para fallback

**Un perfil secundario nunca debe caer a un upstream no acotado.**

Actualmente, cuando falla un fetch nativo, el fallback invoca `codexbar` heredando el entorno normal y selecciona la primera entrada utilizable que coincida con el provider. Eso es correcto para una única cuenta activa, pero en multi-cuenta puede devolver las cuotas de la cuenta predeterminada y etiquetarlas como la secundaria.

Aplicaría estas reglas:

* Perfil `default`: puede conservar el fallback existente.
* Perfil secundario: sin fallback upstream en el MVP.
* Fallback scoped futuro: solo si el subprocess se puede iniciar con un contexto verificado, por ejemplo un `CODEX_HOME` propio pasado mediante `env=` a `subprocess.run`, sin modificar `os.environ`.
* Si upstream no puede confirmar que leyó el perfil solicitado, el fallo nativo debe permanecer como error.
* Antigravity y providers desconocidos siguen siendo passthrough puro. Ahí sí se conservan todas las entradas que upstream entregue.

### Caché y reintentos

La caché actual ya distingue `provider + account`, y los errores con cuenta solo recuperan la lectura exacta. Un error sin cuenta puede conservar todas las cuentas del provider. Esa semántica es adecuada.

Hay que cambiar la clave a:

```javascript
provider + "\u001f" + (entry.profileId || entry.account || "")
```

También hay dos correcciones menos evidentes:

1. **Reconciliación del seed.** Actualmente se purga por provider, no por cuenta. Si se elimina `codex.personal` de la configuración pero Codex sigue habilitado, la cuenta vieja puede sobrevivir en caché. El seed completo debe reconciliar un conjunto de claves `provider/profileId`, no solo IDs de provider.

2. **Startup retry.** Actualmente una entrada sana marca sano al provider completo. Con `codex.work` sano y `codex.personal` con timeout, el perfil fallido podría no recibir el reintento inicial porque ya existe un Codex sano. La decisión de si falta caché debe hacerse por perfil. El reintento puede seguir consultando todo el provider en el MVP. No es obligatorio introducir todavía `--profile personal`.

---

## 3. Qué reutilizar de la UI

### Se reutiliza sin rediseño

Se puede conservar:

* Representación de N entradas con el mismo provider.
* Ordinales `Cx #1`, `Cx #2`.
* Tabs desplazables.
* Bloques compactos independientes.
* Filtrado y orden por provider.
* Filas de cuotas, créditos, resets y detalles.
* Estado `ERR`.
* Indicador de dato en caché.
* Cost summary una sola vez por provider.

Los tests ya verifican que las cuentas repetidas mantienen ordinales, que una cuenta filtrada conserva su selección correcta y que el costo solo se adjunta a la primera entrada del provider.

### Cambios necesarios

**Identidad interna.** `providerAccountKey()` debe preferir `profileId`.

**Selección estable.** Hoy el `selectionKey` se construye con la ocurrencia, por ejemplo `codex:2`. Eso funciona mientras el orden no cambie, pero no identifica realmente la cuenta. Para entradas administradas por el engine usaría:

```text
codex:work
codex:personal
```

Las entradas upstream sin `profileId` conservarían la estrategia ordinal como fallback. El código actual construye la selección según la posición de la entrada, así que este cambio mejora además la estabilidad ante errores, reordenamientos o altas/bajas.

**Separación entre perfil y email.** El popup debería tener propiedades distintas:

```text
profileId
profileLabel
accountEmail
```

Actualmente el toggle de email depende de `activeEntry.account`, por lo que no se puede reutilizar ese mismo campo para el ID del perfil sin cambiar la semántica visual.

**Etiquetas.** Mi recomendación visual sería:

* Panel compacto: mantener ordinales para no aumentar ancho.
* Tab del popup: usar `Codex · Trabajo` cuando existe `profileLabel`. En su ausencia, `Codex #1`.
* Fila de identidad: mostrar el label del perfil.
* Email: únicamente cuando el usuario tiene activado `Show email`.

**Errores y caché.** Un fallo de `personal` no debe colorear ni reemplazar `work`. La entrada de error siempre debe conservar `profileId`.

**Costos.** No intentaría convertir el costo local actual en costo por cuenta. Los historiales locales no demuestran necesariamente qué cuenta pagó cada generación. La conducta existente . Resumen una sola vez por provider. Es la honesta.

---

## 4. Orden de implementación

### Fase 0: contrato y pruebas

Antes de tocar fetches:

* Parser versionado de `profiles.json`.
* Validación de IDs, duplicados, kinds y rutas.
* Resolución de perfiles sintéticos `default`.
* `profileId` y `profileLabel` en success y error.
* Claves de caché y selección basadas en `profileId`.
* Seed y startup retry account-aware.
* Comandos `profiles validate` y `profiles list`.

Esto permite probar la arquitectura con fixtures antes de usar dos cuentas reales.

### Fase 1: MVP con Codex y Claude

Es el MVP correcto y ya satisface el criterio de éxito.

**Codex**

* `authFile` explícito.
* `settingsFile` explícito u opcional.
* Un mismo `settingsFile` puede compartirse entre perfiles.
* No crear shadow homes ni enlaces.
* No copiar `auth.json`.
* No usar fallback no acotado para perfiles secundarios.

T3 recomienda un home compartido más un shadow con el segundo `auth.json` para poder ejecutar agentes y compartir sesiones. También recomienda eliminar del shadow todo salvo `auth.json` cuando se copió el home completo. KodexBar puede ir un paso más simple: leer directamente ese segundo archivo, porque no necesita lanzar un agente desde el overlay.

**Claude**

* Resolver directamente `{configDir}/.credentials.json`.
* Nunca cambiar `HOME`.
* No depender del `CLAUDE_CONFIG_DIR` global del proceso.
* Serializar inicialmente los fetches Claude para no lanzar una ráfaga al endpoint.
* Mantener el comportamiento actual de caché ante HTTP 429.

T3 usa una configuración Claude distinta por cuenta, pasa `CLAUDE_CONFIG_DIR` y recalca que no se debe sustituir `HOME`. Además considera cada config dir un entorno separado.

Resultado de esta fase:

```text
Codex Work → cuotas propias
Codex Personal → cuotas propias
Claude Work → cuotas propias
Claude Personal → cuotas propias
```

### Fase 2: Grok

Grok es el siguiente candidato porque el engine ya tiene un fetch nativo y una noción de `GROK_HOME`.

Cambios:

* `grok_access_credentials(auth_file)` explícito.
* Nada de consultar `GROK_HOME` dentro del worker.
* Cada perfil corresponde a un archivo de auth independiente, no a un scope arbitrario dentro del mismo archivo.
* Pruebas con un perfil sano y otro expirado.
* Sin fallback no acotado para perfiles secundarios.

El riesgo principal no es la configuración, sino que el parser de billing gRPC-web es heurístico y dependiente de un wire layout no público. Multiplicar cuentas también multiplica las ocasiones en que puede aparecer schema drift.

### Fase 3: OpenCode Go

Aquí hay que ser especialmente preciso: en este snapshot, OpenCode Go se detecta por su credencial local, pero en el dispatcher no tiene una rama nativa equivalente a Claude/Codex/Grok/Cursor. La entrada se normaliza sobre el resultado de upstream.

Por eso hay dos caminos legítimos:

1. Añadir un fetch Go realmente parametrizable por `authFile`.
2. Ejecutar upstream con un entorno de OpenCode explícitamente aislado, solo si se verifica qué variables/rutas controla realmente la CLI.

Hasta resolver uno, la documentación debe decir:

```text
OpenCode Go multi-account: solo cuando upstream devuelve varias entradas.
```

### Fase 4: Cursor

Implementaría primero soporte de ruta explícita:

```json
{
 "kind": "cursor-state-db",
 "stateDb": "/ruta/al/perfil/User/globalStorage/state.vscdb"
}
```

No aceptaría únicamente un `home` mágico.

El problema no es leer dos DB: el reader actual ya abre SQLite en modo de solo lectura. El problema es demostrar que el usuario puede tener dos perfiles Cursor autenticados e independientes y localizar cada `state.vscdb` de forma reproducible.

Hasta tener ese procedimiento probado:

```text
Cursor multi-account: experimental, mediante stateDb explícito.
```

T3 también refleja la asimetría: su schema actual expone homes claros para Codex y Claude, mientras Cursor, Grok y OpenCode tienen configuraciones diferentes y sin un home de cuenta equivalente.

### Fase 5: Antigravity y desconocidos

Antigravity debe seguir significando:

```text
una consulta upstream → cero, una o N entradas upstream
```

No haría:

```text
N perfiles configurados → N veces el mismo agy activo
```

Solo se promovería a multi-perfil configurado cuando `agy` o upstream tengan un selector de perfil, home o credencial verificable.

Para los providers desconocidos se documentaría exactamente la misma regla.

---

## 5. Riesgos por provider

| Provider | Soporte recomendado | Riesgo principal |
| --------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **Codex** | Primero, estable | Confundir el overlay necesario para ejecutar agentes con lo necesario para leer cuotas. Fallback que lea la cuenta activa equivocada |
| **Claude** | Primero, estable en entorno probado | Pisar `HOME`. Ráfagas de 429. Directorios configurados pero sin credencial correspondiente |
| **Grok** | Segundo, con cautela | Parser protobuf heurístico. Un auth file puede contener varios scopes pero eso no demuestra varias cuentas |
| **OpenCode Go** | Después de parametrizar su adquisición | En el snapshot es passthrough normalizado. Confusión entre suscripción Go, provider de modelos y router/API |
| **Cursor** | Experimental con `stateDb` explícito | No existe todavía un contrato de perfil tan limpio. Copiar una DB no equivale a autenticar otra cuenta |
| **Antigravity** | Multiplicidad definida por upstream | KodexBar no controla qué cuenta usa `agy`. N invocaciones podrían consultar N veces la misma sesión |

Un error adicional transversal es la renovación. El engine actual no pretende renovar automáticamente credenciales de Codex, Grok o Cursor. Multi-cuenta no debe cambiar eso: el mensaje debe indicar qué **perfil** necesita login mediante la CLI nativa, pero KodexBar no inicia el flujo.

---

## 6. Qué no hacer

No duplicaría objetos `{id: "codex"}` dentro del array `providers` para representar cuentas. Ese array representa providers habilitados, no instancias, y el engine actual lo reduce a IDs.

No almacenaría tokens, cookies, API keys ni contenido de `auth.json` dentro de `profiles.json`.

No aceptaría un mapa libre `"env": {...}` en el MVP. Además de dificultar la validación, terminaría convirtiendo el sidecar en almacén de secretos. Solo se admiten localizadores tipados y no sensibles.

No modificaría `os.environ` temporalmente alrededor de un fetch. Con threads, dos perfiles podrían cruzarse. Los paths deben viajar como argumentos. Los subprocesses futuros recibirían su propio `env=`.

No materializaría un shadow home Codex completo para consultar una URL de cuotas.

No derivaría `profileId` de email, token, organización, account ID ni hash de la ruta.

No permitiría que un fallo de un perfil secundario use el fallback de la cuenta convencional.

No escanearía el disco o todo el home para “descubrir” cuentas. El usuario declara perfiles explícitos.

No presentaría OpenCode Go, Cursor o Antigravity como multi-cuenta first-class hasta tener una forma repetible de autenticar y leer cada instancia.

No duplicaría el resumen de costos en cada cuenta ni insinuaría atribución por cuenta cuando los datos locales son provider-level.

No introduciría login automático, cambio de sesión, rotación por agotamiento ni selección de cuenta para agentes. El brief define KodexBar como lector y visualizador local, no como harness, proxy o gestor de secretos.

---

## Criterio de aceptación técnico

Consideraría terminado el MVP cuando pasen, como mínimo, estos casos:

1. Dos perfiles Codex con `authFile` distintos producen dos entradas `provider: "codex"` y `profileId` distintos.
2. Dos perfiles Claude con `configDir` distintos producen dos entradas independientes.
3. Un perfil sano y otro con autenticación expirada generan una lectura y un error, sin tumbar el refresh.
4. Un timeout de `codex.personal` recupera exclusivamente la caché de `codex.personal`.
5. Un error permanente de `codex.personal` oculta exclusivamente la caché de ese perfil.
6. Cambiar el orden de perfiles no cambia cuál permanece seleccionado.
7. Eliminar un perfil del sidecar lo elimina del seed, popup y caché.
8. Dos resultados que no contienen email siguen siendo distinguibles mediante `profileId`.
9. Ningún JSON de salida contiene tokens ni rutas de credenciales.
10. El costo se muestra una vez por provider.
11. Un fallo nativo del perfil secundario nunca termina mostrando la lectura del perfil predeterminado.
12. Sin `profiles.json`, todos los fixtures y usuarios actuales continúan con una sola entrada por provider.

La arquitectura central, por tanto, sería:

```text
config.json de CodexBar
        +
profiles.json de KodexBar Suite
        |
        v
provider driver + perfil tipado
        |
        v
fetch nativo aislado por perfil
        |
        v
profileId estable en success y error
        |
        v
UI existente con cache y seleccion account-aware
```

El primer release debería afirmar únicamente: **multi-cuenta first-class para Codex y Claude. Grok después. Cursor y OpenCode Go experimentales hasta verificar aislamiento. Antigravity y desconocidos según lo que devuelva upstream**. Esa secuencia entrega utilidad real pronto sin fingir simetría entre proveedores.
