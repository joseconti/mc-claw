# McClaw — Scheduling con Claude CLI: Problema y Solución

## 1. Contexto: ¿Por qué McClaw usa el CLI en vez de la API?

McClaw es una interfaz gráfica sobre los CLIs oficiales de los proveedores de IA. En el caso de Claude, usa el binario `claude` instalado en el sistema, no la API de Anthropic directamente.

Esto es relevante desde el punto de vista legal: Anthropic ha baneado herramientas (OpenCode, Cline, Roo Code) que accedían a la API de Anthropic usando las credenciales OAuth de cuentas Pro/Max, esencialmente consumiendo tokens ilimitados con una suscripción de tarifa plana diseñada para uso humano interactivo.

McClaw evita este problema porque **no hace ninguna llamada a la API de Anthropic**. Cuando el usuario envía un mensaje, McClaw lanza el proceso `claude --print --verbose --output-format stream-json "mensaje"` y lee su stdout. Es exactamente lo mismo que si el usuario escribiera ese comando en el terminal.

---

## 2. Modos de ejecución del CLI de Claude

El CLI de Claude tiene dos modos de operación relevantes:

### Modo no interactivo (`--print`)
```bash
claude --print --verbose --output-format stream-json "dime la hora"
```
- Envía un mensaje, recibe respuesta, **el proceso termina**.
- Es el modo que usa `CLIBridge` para el chat normal de McClaw.
- No soporta slash commands como `/loop`.

### Modo interactivo (persistente)
```bash
claude --output-format stream-json --verbose --input-format stream-json
```
- El proceso queda vivo esperando mensajes por stdin.
- Acepta mensajes JSON por stdin: `{"type":"user_message","message":"..."}`
- **Soporta slash commands como `/loop`** cuando hay un TTY real.
- Es el modo que usa `BackgroundCLISession` para el scheduling.

---

## 3. ¿Qué es `/loop` y por qué lo necesitamos?

`/loop` es un slash command nativo de Claude CLI (requiere v2.1.72+) que permite programar una tarea recurrente dentro de la sesión:

```
/loop 5m dime el tiempo actual
/loop 24h resume los emails de hoy
/loop 1h comprueba si hay nuevos PRs
```

Cuando se ejecuta `/loop`, **el propio Claude CLI gestiona el scheduling internamente**. McClaw no necesita hacer nada más — Claude se encarga de ejecutar la tarea en los intervalos definidos, sin que McClaw intervenga en cada ejecución.

Esto es importante para la cuestión del TOS: McClaw actúa como interfaz para que el usuario configure el loop **una sola vez**, igual que si abriera el terminal y lo escribiera él mismo. La automatización posterior la gestiona el propio Claude CLI de forma nativa.

---

## 4. El problema: `/loop` no funciona sin TTY

Aquí está el problema técnico que impide que funcione actualmente.

### Lo que hace BackgroundCLISession

`BackgroundCLISession` lanza Claude en modo persistente y le envía `/loop` via stdin:

```swift
// En CLIParser.buildBackgroundSessionArguments:
var args = ["--output-format", "stream-json", "--verbose", "--input-format", "stream-json"]

// En BackgroundCLISession.scheduleTask:
let loopCommand = "/loop \(interval) \(message)"
return sendMessage(loopCommand)

// En BackgroundCLISession.sendMessage:
let encoded = CLIParser.encodeStdinMessage(text)
// → {"type":"user_message","message":"/loop 5m dime la hora"}
try handle.write(contentsOf: data)
```

### Por qué falla

En modo `--input-format stream-json`, el CLI recibe los mensajes como input del usuario y los pasa directamente al modelo. **Los slash commands como `/loop` son interceptados por la capa de UI interactiva del CLI, no por el modelo.**

Sin un TTY real, el CLI no activa su modo interactivo completo, y por tanto `/loop` llega al modelo como texto plano. Claude recibe literalmente el texto `/loop 5m dime la hora` y no sabe qué hacer con él porque eso lo debería gestionar el CLI, no el modelo.

### Los logs lo confirman

```
[01:33:33] Encoded JSON: {"message":"/loop 5m Tell me the current time","type":"user_message"}
[01:33:33] Sent to stdin: /loop 5m Tell me the current time
[01:33:33] Restored task 'Tell me the current time' (5m)
```

El mensaje se envía correctamente. Pero después... **silencio total**. Sin stdout, sin stderr, sin respuesta. El CLI recibe el mensaje pero no lo procesa como slash command.

---

## 5. La solución: PTY (Pseudo-Terminal)

### ¿Qué es un PTY?

Un PTY (Pseudo-Terminal) es un par de file descriptors que simulan un terminal real. Cuando un proceso se lanza con un PTY como stdin/stdout, "cree" que hay un usuario humano al otro lado con una terminal real. Esto activa el modo interactivo completo del CLI, incluyendo el procesamiento de slash commands.

Es la misma técnica que usa SSH, tmux, iTerm2 o cualquier emulador de terminal.

### Por qué funciona

Con PTY:
```
McClaw → forkpty() → proceso claude (cree que hay terminal real)
                          ↓
                   activa modo interactivo completo
                          ↓
                   procesa /loop como slash command nativo
                          ↓
                   gestiona el scheduling internamente
```

Sin PTY (situación actual):
```
McClaw → Pipe() → proceso claude (sabe que no hay terminal)
                       ↓
                  modo no interactivo / stream-json puro
                       ↓
                  /loop llega al modelo como texto plano
                       ↓
                  sin respuesta / comportamiento indefinido
```

---

## 6. Implementación en Swift

### Cambios necesarios en BackgroundCLISession

El cambio central es reemplazar los `Pipe()` de stdin/stdout por un PTY usando `forkpty()` de Darwin:

```swift
import Darwin

// En lugar de:
let stdinPipe = Pipe()
let stdoutPipe = Pipe()
proc.standardInput = stdinPipe
proc.standardOutput = stdoutPipe

// Usar PTY:
var masterFD: Int32 = -1
var pid: pid_t = -1

// forkpty() crea el PTY y hace fork del proceso
pid = forkpty(&masterFD, nil, nil, nil)

if pid == 0 {
    // Proceso hijo: ejecutar el CLI
    execvp(binaryPath, args)
    exit(1)
} else if pid > 0 {
    // Proceso padre: masterFD es el file descriptor del PTY
    // Leer stdout y escribir stdin a través de masterFD
}
```

### Estructura completa de la solución

```swift
actor BackgroundCLISession {

    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1

    private func launchWithPTY(binaryPath: String, args: [String], env: [String: String]) throws {

        var master: Int32 = -1
        var child: pid_t = -1

        // Preparar argv para execvp
        let cBinary = binaryPath.withCString { strdup($0) }
        var cArgs = args.map { $0.withCString { strdup($0) } }
        cArgs.insert(cBinary, at: 0)
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        // Preparar envp
        var cEnv = env.map { "\($0.key)=\($0.value)".withCString { strdup($0) } }
        cEnv.append(nil)
        defer { cEnv.forEach { free($0) } }

        child = forkpty(&master, nil, nil, nil)

        guard child >= 0 else {
            throw PTYError.forkFailed(errno)
        }

        if child == 0 {
            // Proceso hijo
            execve(binaryPath, &cArgs, &cEnv)
            exit(1) // Solo llega aquí si execve falla
        }

        // Proceso padre
        self.masterFD = master
        self.childPID = child

        // Configurar lectura no bloqueante
        var flags = fcntl(master, F_GETFL, 0)
        fcntl(master, F_SETFL, flags | O_NONBLOCK)

        // Iniciar lectura de stdout via GCD
        startReading(fd: master)
    }

    /// Enviar mensaje al proceso via PTY
    func sendMessage(_ text: String) -> Bool {
        guard masterFD >= 0 else { return false }

        // Con PTY podemos enviar el texto directamente (con newline)
        // El CLI lo verá como si el usuario lo hubiera tecleado
        var message = text + "\n"
        let result = message.withCString { ptr in
            write(masterFD, ptr, strlen(ptr))
        }
        return result > 0
    }

    /// Leer stdout del proceso via GCD
    private func startReading(fd: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                let data = Data(buffer.prefix(n))
                if let text = String(data: data, encoding: .utf8) {
                    self.handleOutput(text)
                }
            }
        }
        source.resume()
    }
}
```

### Envío de mensajes con PTY

Con PTY, el envío cambia: en vez de JSON por stdin, se escribe texto directamente como si fuera un teclado:

```swift
// Sin PTY (actual) — JSON por pipe:
let json = "{\"type\":\"user_message\",\"message\":\"/loop 5m test\"}\n"
stdinHandle.write(json.data(using: .utf8)!)

// Con PTY — texto directo como si lo tecleara el usuario:
let text = "/loop 5m test\n"
write(masterFD, text, text.count)
```

Esto es exactamente lo que ve el CLI cuando un usuario escribe en el terminal.

---

## 7. Limitaciones de `/loop` a tener en cuenta

Antes de implementar, hay que conocer las limitaciones documentadas de `/loop`:

| Limitación | Detalle |
|---|---|
| **Session-scoped** | Las tareas solo viven mientras el proceso de Claude está activo. Si McClaw se cierra, se pierden. |
| **Sin persistencia** | Si el proceso muere y se reinicia, hay que re-enviar los `/loop`. BackgroundCLISession ya maneja esto con `restoreScheduledTasks()`. |
| **Expiración** | Las tareas recurrentes expiran automáticamente a los 3 días. Hay que renovarlas. |
| **Máximo 50 tareas** | Por sesión. Poco probable que sea un problema en uso real. |
| **No soporta cron expressions** | `/loop` solo acepta intervalos simples (`5m`, `1h`, `24h`). Para cron expressions hay que aproximar el intervalo, como ya hace `cronToApproxInterval()`. |
| **Sin catch-up** | Si el proceso estaba ocupado cuando tocaba ejecutar, solo se ejecuta una vez al quedar libre, no una por cada intervalo perdido. |

---

## 8. Flujo completo con la solución PTY

```
Usuario crea tarea en McClaw (p.ej. "Resume emails cada mañana a las 7am")
    ↓
CronJobsStore.upsertJob() guarda en ~/.mcclaw/schedules.json
    ↓
BackgroundCLISession.scheduleTask(interval: "24h", message: "resume emails de hoy")
    ↓
write(masterFD, "/loop 24h resume emails de hoy\n")
    ↓
Claude CLI (con PTY activo) interpreta /loop como slash command nativo
    ↓
Claude gestiona el timer internamente
    ↓
Cada 24h: Claude ejecuta "resume emails de hoy" de forma autónoma
    ↓
BackgroundCLISession recibe el output por stdout y lo procesa
    ↓
McClaw muestra el resultado y/o lo entrega via canales configurados

--- Si McClaw se reinicia ---
    ↓
BackgroundCLISession.restoreScheduledTasks() lee schedules.json
    ↓
Re-envía /loop para cada tarea activa
    ↓
Claude retoma el scheduling
```

---

## 9. Archivos a modificar

| Archivo | Cambio |
|---|---|
| `BackgroundCLISession.swift` | Reemplazar `Pipe()` por `forkpty()`. Cambiar `sendMessage()` para escribir texto plano al PTY en vez de JSON. Añadir lectura via GCD del masterFD. |
| `CLIParser.swift` | `buildBackgroundSessionArguments()` puede simplificarse: con PTY no hace falta `--input-format stream-json`. |
| `CronJobsStore.swift` | Añadir renovación automática de tareas antes de que expiren (3 días). |

---

## 10. Resumen

El problema es simple: **`/loop` es un slash command del CLI interactivo y no funciona sin un TTY real**. La solución es lanzar el proceso de Claude con `forkpty()` en vez de `Pipe()`, lo que simula un terminal real y activa el modo interactivo completo del CLI.

Con esto, McClaw actúa como un frontend gráfico que escribe `/loop` en nombre del usuario una sola vez para configurar la tarea. A partir de ahí, **es el propio Claude CLI quien gestiona el scheduling de forma nativa**, sin que McClaw intervenga en cada ejecución. La automatización es de Claude, no de McClaw.
