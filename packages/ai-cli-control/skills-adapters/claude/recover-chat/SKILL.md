---
name: recover-chat
description: Transporta al contexto actual una conversación previa de Codex, Grok, Antigravity o Claude para este proyecto. Úsalo cuando el usuario pida recuperar, listar o elegir conversaciones anteriores.
---

# Recuperar conversaciones

Usa siempre el comando universal `ai recover`. Si `ai` no está en `PATH`, usa `~/.local/bin/ai recover`.

## Recuperación directa

Cuando el usuario indique un proveedor, recupera su última conversación pasada:

```bash
ai recover dump --provider PROVEEDOR --id last
```

Acepta `codex`, `grok`, `agy`, `antigravity` y `claude`. Para Claude, `--id last` omite la sesión activa y selecciona la conversación pasada más reciente. Integra el contenido recuperado y menciona proveedor, id y fecha. Si aparece `[TRUNCADO: ...]`, advierte que el dump fue recortado.

## Lista y elección

Si el usuario pide `--lista`, `-l` o elegir una conversación, lista primero:

```bash
ai recover list --provider PROVEEDOR
```

Presenta las sesiones mediante `AskUserQuestion`. Cada opción combina fecha u hora y el fragmento del primer prompt. Muestra hasta cuatro opciones por pregunta y permite que el usuario escriba un id de la lista. Después recupera la elegida con `dump --provider PROVEEDOR --id ID`.

## Varios proveedores

Para varios proveedores con lista, ejecuta un `list` por proveedor y formula una pregunta `AskUserQuestion` por proveedor, con un máximo de cuatro preguntas por llamada. Recupera cada id elegido con `dump`. Si Antigravity avisa que no puede asociar conversaciones de forma fiable al proyecto, comunícalo antes de pedir la selección.

El límite normal de `dump` es 100000 caracteres. Usa `--max-chars` solo cuando haga falta reducir contexto.
