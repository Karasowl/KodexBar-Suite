# Contrato de adaptadores locales

Los adaptadores Python ejecutables se incluyen únicamente en este paquete. No se cargan módulos Python desde la configuración de un usuario.

Un descriptor JSON puede vivir en `/usr/lib/kodexbar/local-ai-drivers` si el directorio no es escribible por usuarios normales, o indicarse mediante `adapterDescriptors` en la configuración. Solo se acepta este esquema:

```json
{"id":"mi-runtime","kind":"openai-model-catalog","modelsPath":"/v1/models"}
```

El `id` debe coincidir con una entrada de `runtimes`. `modelsPath` es una ruta HTTP relativa. No admite comandos, rutas Python ni acciones.

Todo adaptador devuelve una lista de modelos y un estado de runtime. Cada modelo declara `state`, `kind`, `classificationConfidence`, `metric` solo si la fuente reporta una unidad real, `memory` solo si la fuente la atribuye y capacidades explícitas. Un error de conexión se representa como runtime `disconnected`. Un adaptador no puede inventar actividad, rendimiento ni habilitar acciones no soportadas.
