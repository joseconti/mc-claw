# BitNet Provider - Diagnostico completo y guia de correccion

## El problema

Cuando el usuario envia un mensaje a BitNet desde McClaw, la respuesta es galimatias (texto sin sentido). Otras personas usando BitNet directamente desde terminal pueden chatear (con limitaciones), pero en McClaw no funciona.

## Contexto: como funciona el flujo actual

Cuando el usuario envia un mensaje con BitNet seleccionado, el flujo es:

```
ChatViewModel.send()
  -> CLIBridge.sendViaBitNet()          (CLIBridge.swift linea 174)
    -> BitNetServerManager.shared.chat() (BitNetServerManager.swift linea 149)
      -> POST http://127.0.0.1:8921/v1/chat/completions
        -> llama-server (proceso nativo)
          -> modelo GGUF cargado en memoria
```

El servidor `llama-server` se arranca en `BitNetServerManager.start()` (linea 54) usando los argumentos que construye `BitNetKit.buildServerStartArgs()` (BitNetKit.swift linea 434).

El metodo `chat()` (linea 149) envia un POST JSON al servidor con este body:

```json
{
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "model": "Falcon3-3B-Instruct-1.58bit"
}
```

El servidor responde con formato OpenAI-compatible y McClaw extrae `choices[0].message.content`.

## Los problemas encontrados (en orden de prioridad)

---

### BUG 1 (CRITICO): `llama-server` no se compila durante la instalacion

**Archivos afectados:**
- `McClaw/Sources/McClaw/Services/CLIBridge/CLIDetector.swift` (lineas 317-373, array `bitnetInstallSteps`)
- `McClaw/Sources/McClawKit/BitNetKit.swift` (linea 67, path `llamaServer`)

**Que pasa:**

Los pasos de instalacion en `bitnetInstallSteps` llaman a `setup_env.py` del repositorio de BitNet. Este script compila `llama-cli` pero NO compila `llama-server`. El `llama-server` requiere pasar el flag `-DLLAMA_BUILD_SERVER=ON` a CMake, y esto no aparece en ningun lugar del codigo de McClaw.

Sin embargo, `BitNetServerManager.start()` en la linea 84 intenta ejecutar el binario en `BitNetKit.Paths.llamaServer` (que es `~/.mcclaw/bitnet/build/bin/llama-server`). Si ese binario no existe, la linea 85 lanza `BitNetServerError.processStartFailed`. Si por alguna razon existe un `llama-server` generico de una instalacion previa de llama.cpp, ese binario NO tiene los kernels optimizados de 1-bit y producira galimatias.

Referencia: https://github.com/microsoft/BitNet/issues/206 - un colaborador confirmo que hay que compilar con `-DLLAMA_BUILD_SERVER=ON`.

El paso de verificacion actual (id `"verify"`, linea 366) comprueba `BitNetKit.Paths.binary` que es `llama-cli`, no `llama-server`.

**Como arreglarlo:**

Hay que anadir un paso de build del servidor despues del paso `download-and-build`. En `CLIDetector.swift`, en el array `bitnetInstallSteps`, anadir un nuevo `InstallStep` entre el paso `"download-and-build"` y el paso `"verify"`:

```swift
// Anadir DESPUES del InstallStep con id "download-and-build" y ANTES de "verify"
InstallStep(
    id: "build-server",
    description: "Build REST API server",
    command: ["/bin/bash", "-c",
              "cd " + BitNetKit.Paths.home + " && " +
              "cmake -S . -B build -DLLAMA_BUILD_SERVER=ON && " +
              "cmake --build build --target llama-server -- -j4"],
    workingDirectory: BitNetKit.Paths.home,
    estimatedDuration: 120
),
```

Y cambiar el paso `"verify"` para que compruebe `llama-server` en lugar de `llama-cli`:

```swift
// CAMBIAR: verificar llama-server en vez de llama-cli
InstallStep(
    id: "verify",
    description: "Verify installation",
    command: ["/bin/test", "-f", BitNetKit.Paths.llamaServer],  // ERA: BitNetKit.Paths.binary
    estimatedDuration: 5,
    canRetry: false
),
```

**IMPORTANTE:** Ademas hay que asegurarse de que el cmake del paso `build-server` pueda encontrar el cmake local si se instalo con el script directo. El cmake podria estar en `~/.mcclaw/tools/cmake/CMake.app/Contents/bin/cmake` (ver `BitNetKit.Paths.cmakeBin`). El comando deberia usar el PATH extendido que ya se configura en `CLIInstaller.processPath`. Si el paso se ejecuta via `runProcessSync` o `runProcessSyncWithWorkDir`, verificar que el environment del Process incluye ese PATH.

---

### BUG 2 (CRITICO): No se pasan `temperature` ni `max_tokens` en el POST al servidor

**Archivo afectado:**
- `McClaw/Sources/McClaw/Services/CLIBridge/BitNetServerManager.swift` (lineas 168-171, metodo `chat()`)

**Que pasa:**

El body del POST solo contiene `messages` y `model`:

```swift
// CODIGO ACTUAL (lineas 168-171):
let body: [String: Any] = [
    "messages": messages,
    "model": currentModel ?? "bitnet",
]
```

No envia `temperature`, `max_tokens` (`n_predict`), ni ningun otro parametro. Esto tiene dos consecuencias:

1. El valor por defecto de `n_predict` en llama-server es **128 tokens**. Esto produce respuestas truncadas (confirmado en https://github.com/microsoft/BitNet/issues/264).
2. Sin temperatura controlada, el modelo puede generar tokens semi-aleatorios.

Los valores estan disponibles en `self.config` (que es un `BitNetKit.ServerConfig` que se pasa en `start()`), pero no se usan en `chat()`.

**Como arreglarlo:**

Cambiar el body del POST en el metodo `chat()` para incluir los parametros del config. En `BitNetServerManager.swift`, reemplazar las lineas 168-171 con:

```swift
let body: [String: Any] = [
    "messages": messages,
    "model": currentModel ?? "bitnet",
    "max_tokens": config.maxTokens,
    "temperature": config.temperature,
]
```

Los valores de `config.maxTokens` y `config.temperature` ya estan configurados correctamente cuando se crea el `ServerConfig` en `CLIBridge.sendViaBitNet()` (lineas 190-196) a partir de `AppState.shared`.

---

### BUG 3 (IMPORTANTE): El parche TL1 tiene una inconsistencia con `usePretuned`

**Archivos afectados:**
- `McClaw/Sources/McClaw/Services/CLIBridge/CLIDetector.swift` (lineas 326-334 y 355-365)
- `McClaw/Sources/McClawKit/BitNetKit.swift` (lineas 481-496, `buildSetupFromRepoArgs`)

**Que pasa:**

Hay dos pasos de instalacion que interactuan:

1. Paso `"patch-setup"` (linea 326): cambia `BITNET_ARM_TL1=OFF` a `BITNET_ARM_TL1=ON` en `setup_env.py`. El comentario en el codigo dice que sin esto hay "garbage output" en Apple Silicon.

2. Paso `"download-and-build"` (linea 355): llama a `BitNetKit.buildSetupFromRepoArgs()` con `usePretuned: false`.

`buildSetupFromRepoArgs` con `usePretuned: false` no pasa el flag `-p` a `setup_env.py`. Los kernels TL1 pueden necesitar parametros pretuned para funcionar correctamente. Si TL1 esta activado pero sin pretuned, la inferencia puede producir resultados incorrectos (basura).

Ademas, el parche sed se aplica globalmente (`s/-DBITNET_ARM_TL1=OFF/-DBITNET_ARM_TL1=ON/g`) pero sed en macOS no devuelve error si no encuentra coincidencias. Si el repositorio upstream ha cambiado la sintaxis de `setup_env.py` (por ejemplo, si ya no contiene exactamente `BITNET_ARM_TL1=OFF`), el parche no se aplica y no hay forma de saberlo.

**Como arreglarlo:**

Paso 1: Cambiar `usePretuned` a `true` en el paso `"download-and-build"`:

```swift
// EN CLIDetector.swift, paso "download-and-build":
InstallStep(
    id: "download-and-build",
    description: "Download Falcon3 3B Instruct and build kernels",
    command: BitNetKit.buildSetupFromRepoArgs(
        repo: "tiiuae/Falcon3-3B-Instruct-1.58bit",
        usePretuned: true  // <-- CAMBIAR de false a true
    ),
    workingDirectory: BitNetKit.Paths.home,
    condaEnvironment: BitNetKit.condaEnvironment,
    estimatedDuration: 480
),
```

Paso 2: Anadir un paso de verificacion del parche despues de `"patch-setup"` y antes de `"conda-create"`:

```swift
InstallStep(
    id: "verify-patch",
    description: "Verify TL1 kernel patch applied",
    command: ["/bin/bash", "-c",
              "grep -q 'BITNET_ARM_TL1=ON' " + BitNetKit.Paths.home + "/setup_env.py"],
    estimatedDuration: 2,
    canRetry: false
),
```

Si este paso falla, significa que el parche no se aplico (el upstream cambio). En ese caso habria que revisar el `setup_env.py` actual para entender la nueva sintaxis.

---

### BUG 4 (IMPORTANTE): Modelos base producen galimatias al usarse para chat

**Archivo afectado:**
- `McClaw/Sources/McClawKit/BitNetKit.swift` (lineas 190-273, `modelRegistry`)

**Que pasa:**

El registro de modelos incluye 8 modelos, pero solo 4 son modelos Instruct (los Falcon3). Los otros 4 son modelos BASE que **no tienen chat template**:

- `BitNet-b1.58-2B-4T` - base. El propio registro dice: "Known GGUF tokenizer issue."
- `bitnet_b1_58-large` - base. Dice: "Base model (no chat). Research only."
- `bitnet_b1_58-3B` - base. Dice: "Base model (no chat). Research only."
- `Llama3-8B-1.58-100B-tokens` - base. Dice: "Base model (no chat)."

Cuando `llama-server` recibe un POST a `/v1/chat/completions` con `messages`, necesita formatear esos mensajes usando un **chat template** (por ejemplo, Falcon3 usa `<|system|>...<|user|>...<|assistant|>`). Los modelos base no tienen chat template embebido en el GGUF, asi que el servidor no sabe como formatear los mensajes y produce basura.

El modelo por defecto que descarga la instalacion es `Falcon3-3B-Instruct-1.58bit`, que SI es instruct. Pero si el usuario cambia de modelo a cualquiera de los modelos base desde la UI de BitNet Settings, obtendra galimatias.

**Como arreglarlo:**

Paso 1: Anadir un campo `isInstruct` a `BitNetKit.ModelInfo`:

```swift
// EN BitNetKit.swift, struct ModelInfo:
public struct ModelInfo: Sendable, Codable, Equatable, Identifiable {
    // ... campos existentes ...
    public let isInstruct: Bool  // NUEVO
    // ... init existente, anadir parametro isInstruct ...
}
```

Paso 2: Marcar cada modelo en `modelRegistry`:

```swift
// Los 4 modelos Falcon3: isInstruct: true
// Los 4 modelos base: isInstruct: false
```

Paso 3: En `BitNetServerManager.chat()` o en `CLIBridge.sendViaBitNet()`, antes de enviar el POST, verificar que el modelo seleccionado es instruct. Si no lo es, devolver un error descriptivo:

```swift
// En CLIBridge.sendViaBitNet() o en BitNetServerManager.chat():
if let modelInfo = BitNetKit.registryModel(for: selectedModel),
   !modelInfo.isInstruct {
    // No usar chat/completions para modelos base
    continuation.yield(.error("El modelo \(modelInfo.displayName) no soporta chat. Selecciona un modelo Instruct (Falcon3)."))
    continuation.yield(.done)
    continuation.finish()
    return
}
```

Paso 4: En la UI de `BitNetSettingsTab.swift`, mostrar una advertencia junto a los modelos base o deshabilitar la opcion de usarlos como modelo de chat.

---

### BUG 5 (MENOR): `buildServerStartArgs` no pasa `--chat-template`

**Archivo afectado:**
- `McClaw/Sources/McClawKit/BitNetKit.swift` (lineas 434-449, `buildServerStartArgs`)

**Que pasa:**

Cuando se arranca `llama-server`, los argumentos son:

```swift
[
    Paths.llamaServer,
    "-m", modelPath,
    "-c", String(config.contextSize),
    "-t", String(config.threads),
    "-n", String(config.maxTokens),
    "-ngl", "0",
    "--temp", String(config.temperature),
    "--host", config.host,
    "--port", String(config.port),
]
```

No se pasa `--chat-template`. Algunos modelos GGUF tienen el template embebido en sus metadatos, y `llama-server` lo detecta automaticamente. Los modelos Falcon3 Instruct normalmente incluyen su template. Pero si el modelo no lo incluye, el servidor no sabe como formatear los mensajes y el resultado es basura.

**Como arreglarlo (baja prioridad si se arregla BUG 4):**

Si se implementa la validacion del BUG 4 (solo permitir modelos instruct para chat), este bug se mitiga porque los modelos Falcon3 Instruct si incluyen su template. Sin embargo, como precaucion extra, se podria anadir el template explicito:

```swift
// EN BitNetKit.swift, buildServerStartArgs():
public static func buildServerStartArgs(
    modelPath: String,
    config: ServerConfig = ServerConfig(),
    chatTemplate: String? = nil  // NUEVO parametro opcional
) -> [String] {
    var args = [
        Paths.llamaServer,
        "-m", modelPath,
        "-c", String(config.contextSize),
        "-t", String(config.threads),
        "-n", String(config.maxTokens),
        "-ngl", "0",
        "--temp", String(config.temperature),
        "--host", config.host,
        "--port", String(config.port),
    ]
    if let chatTemplate {
        args += ["--chat-template", chatTemplate]
    }
    return args
}
```

---

## Resumen de archivos a modificar

| Archivo | Que cambiar |
|---------|-------------|
| `CLIDetector.swift` | Anadir paso `build-server` con cmake `-DLLAMA_BUILD_SERVER=ON`. Anadir paso `verify-patch`. Cambiar paso `verify` para comprobar `llamaServer`. Cambiar `usePretuned` a `true`. |
| `BitNetServerManager.swift` | En `chat()`, anadir `max_tokens` y `temperature` al body del POST. |
| `BitNetKit.swift` | Anadir campo `isInstruct` a `ModelInfo`. Marcar cada modelo. Opcionalmente anadir parametro `chatTemplate` a `buildServerStartArgs`. |
| `CLIBridge.swift` | En `sendViaBitNet()`, validar que el modelo es instruct antes de enviar. |
| `BitNetSettingsTab.swift` | Mostrar advertencia en modelos base o deshabilitar su uso para chat. |

## Orden de ejecucion recomendado

1. **Primero** arreglar BUG 2 (anadir `max_tokens` y `temperature` al POST). Es el cambio mas simple (2 lineas en `BitNetServerManager.swift`) y puede resolver parte del problema inmediatamente si `llama-server` ya existe.

2. **Segundo** arreglar BUG 1 (compilar `llama-server`). Anadir el paso de build del servidor a `bitnetInstallSteps` y cambiar la verificacion. El usuario tendra que reinstalar BitNet despues de este cambio.

3. **Tercero** arreglar BUG 3 (cambiar `usePretuned` a true y verificar el parche).

4. **Cuarto** arreglar BUG 4 (campo `isInstruct` y validacion).

5. **Quinto** (opcional) arreglar BUG 5 (chat template explicito).

## Verificacion tras los cambios

Para verificar que los cambios funcionan:

```bash
# 1. Verificar que llama-server existe tras reinstalar
ls -la ~/.mcclaw/bitnet/build/bin/llama-server

# 2. Verificar que el parche TL1 se aplico
grep "BITNET_ARM_TL1=ON" ~/.mcclaw/bitnet/setup_env.py

# 3. Verificar que el modelo Falcon3 esta descargado
ls ~/.mcclaw/bitnet/models/Falcon3-3B-Instruct-1.58bit/

# 4. Probar el servidor manualmente
~/.mcclaw/bitnet/build/bin/llama-server \
  -m ~/.mcclaw/bitnet/models/Falcon3-3B-Instruct-1.58bit/ggml-model-i2_s.gguf \
  -c 2048 -t 4 -n 512 --temp 0.7 --host 127.0.0.1 --port 8921

# 5. En otra terminal, probar el endpoint
curl -s http://127.0.0.1:8921/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "falcon3",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is 2+2?"}
    ],
    "max_tokens": 256,
    "temperature": 0.7
  }'
```

Si el paso 5 devuelve una respuesta coherente con `choices[0].message.content` conteniendo algo como "4" o "2+2=4", entonces el servidor funciona y los bugs del lado McClaw (BUG 2, 4, 5) son los que hay que arreglar en el codigo Swift.

Si el paso 4 falla (servidor no arranca o no existe), el BUG 1 es el problema principal.

Si el paso 5 devuelve galimatias, el problema esta en la compilacion (BUG 3 - parche TL1 / pretuned) o en el modelo (BUG 4 - modelo base sin chat template).

## Tests

Tras los cambios, ejecutar los tests existentes:

```bash
cd McClaw && swift test
```

Los tests en `BitNetKitTests.swift` cubren paths, model registry, version parsing, command building y response parsing. Si se anade `isInstruct` a `ModelInfo`, habra que actualizar las inicializaciones en los tests.

## Referencias

- BitNet repo: https://github.com/microsoft/BitNet
- Issue #264 (truncated output, n_predict=128): https://github.com/microsoft/BitNet/issues/264
- Issue #243 (only getting "G"): https://github.com/microsoft/BitNet/issues/243
- Issue #206 (server build flag -DLLAMA_BUILD_SERVER=ON): https://github.com/microsoft/BitNet/issues/206
- Documentacion de arquitectura: `docs/McClaw/15-BITNET-PROVIDER.md`
