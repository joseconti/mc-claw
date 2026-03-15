# Fix: BackgroundCLISession con PTY

## Diagnóstico de los dos problemas

### Problema 1 — `--output-format stream-json` es incompatible con PTY interactivo

En `CLIParser.buildBackgroundSessionArguments()`:

```swift
// Código actual (incorrecto)
var args = ["--output-format", "stream-json", "--verbose"]
```

Cuando el CLI se lanza con PTY activo, entra en **modo interactivo completo**. En ese modo, el CLI gestiona su propio rendering de UI (prompt, colores, animaciones). La flag `--output-format stream-json` intenta forzar output JSON, pero el CLI en modo interactivo **mezcla el JSON con secuencias de control de terminal** (cursor movement, borrado de pantalla, colores ANSI) porque cree que está hablando con un terminal real.

El resultado es que el JSON llega corrupto y el parser falla silenciosamente.

### Problema 2 — `stripANSI` no cubre todas las secuencias PTY

```swift
// Regex actual (incompleta)
text.replacingOccurrences(
    of: "\\x1B\\[[0-9;]*[A-Za-z]|\\x1B\\].*?\\x07|\\x1B\\([A-Z]",
    ...
)
```

El CLI interactivo emite secuencias que este regex no captura:
- `\r` y `\r\n` (carriage return sin newline)
- `\x1B[?25l` / `\x1B[?25h` (ocultar/mostrar cursor)
- `\x1B[2J` / `\x1B[H` (borrar pantalla / mover cursor al origen)
- `\x1B[?2004h` / `\x1B[?2004l` (bracketed paste mode)
- Caracteres de control como `\x07` (bell), `\x08` (backspace)

Incluso si se mejora el regex, la solución es frágil porque el CLI puede cambiar su output de terminal en futuras versiones.

---

## La solución correcta

El error conceptual es intentar parsear `stream-json` de un proceso PTY. Son dos modos incompatibles.

La solución es **separar completamente el canal de envío del canal de recepción**:

- **Canal de envío (PTY)**: lanzar el CLI en modo interactivo puro, sin flags de output format. Solo sirve para escribir `/loop` una vez. No intentamos parsear su output.
- **Canal de recepción**: cuando `/loop` dispara una tarea, el propio Claude CLI ejecuta un subproceso de `claude --print` internamente. Ese output sí es limpio y parseable. McClaw lo recibe a través de un archivo de log que el CLI escribe en `~/.claude/`.

Sin embargo, dado que no tenemos control sobre dónde escribe el CLI su output interno de `/loop`, la solución práctica más robusta es más simple: **lanzar el PTY sin `--output-format`**, dejando que el CLI gestione su UI interactiva, e **ignorar completamente el stdout del PTY**. El objetivo del PTY es solo registrar el `/loop`, no parsear respuestas.

Cuando queramos recoger el output de una tarea que disparó `/loop`, lo hacemos con una llamada separada a `CLIBridge` (el modo `--print` habitual).

---

## Cambios concretos

### 1. `CLIParser.swift` — Cambiar los argumentos de la sesión background

```swift
// ANTES (incorrecto):
public static func buildBackgroundSessionArguments(
    sessionId: String,
    model: String? = nil,
    systemPrompt: String? = nil
) -> [String] {
    var args = ["--output-format", "stream-json", "--verbose"]
    if let model { args += ["--model", model] }
    if let systemPrompt, !systemPrompt.isEmpty {
        args += ["--system-prompt", systemPrompt]
    }
    args += ["--session-id", sessionId]
    return args
}

// DESPUÉS (correcto):
public static func buildBackgroundSessionArguments(
    sessionId: String,
    model: String? = nil
) -> [String] {
    // Sin --output-format ni --verbose.
    // El PTY necesita modo interactivo puro para procesar slash commands.
    // No intentamos parsear el output de esta sesión.
    var args: [String] = []
    if let model { args += ["--model", model] }
    args += ["--session-id", sessionId]
    return args
}
```

**Por qué**: sin `--output-format stream-json`, el CLI entra en modo interactivo limpio. Sus slash commands (`/loop`) funcionan correctamente. No hay JSON corrupto porque no esperamos JSON.

---

### 2. `PTYProcess.swift` — Simplificar `configureTerminal()`

El `configureTerminal()` actual desactiva `ECHO` e `ICANON`. Está bien, pero falta también desactivar el procesamiento de señales del terminal para evitar que secuencias como `\x03` (Ctrl+C) maten el proceso inadvertidamente:

```swift
func configureTerminal() {
    guard masterFD >= 0 else { return }

    var termios = Darwin.termios()
    guard tcgetattr(masterFD, &termios) == 0 else {
        logger.warning("tcgetattr failed: \(Darwin.errno)")
        return
    }

    // Desactivar echo: el input no se refleja en el output
    termios.c_lflag &= ~UInt(ECHO)
    // Desactivar modo canónico: input byte a byte, sin buffering por líneas
    termios.c_lflag &= ~UInt(ICANON)
    // Desactivar procesamiento de señales (SIGINT, SIGQUIT) desde el terminal
    // Esto evita que \x03 mate el proceso accidentalmente
    termios.c_lflag &= ~UInt(ISIG)
    // Desactivar control de flujo por software (XON/XOFF)
    termios.c_iflag &= ~UInt(IXON)

    guard tcsetattr(masterFD, TCSANOW, &termios) == 0 else {
        logger.warning("tcsetattr failed: \(Darwin.errno)")
        return
    }

    logger.info("PTY terminal configured: echo=off, canonical=off, isig=off")
}
```

---

### 3. `BackgroundCLISession.swift` — Simplificar el output reading

Ya que no parseamos el output del PTY, el `startReading` se simplifica enormemente. Solo lo usamos para detectar que el proceso está vivo y para loggear en debug:

```swift
// ANTES: intentaba parsear JSON del PTY (incorrecto)
pty.startReading(
    onData: { data in
        guard let rawText = String(data: data, encoding: .utf8) else { return }
        let text = CLIParser.stripANSI(rawText)  // ← frágil e incompleto
        let lines = lineBuffer.feed(text)
        for line in lines {
            let event = CLIParser.parseLine(line, provider: "claude")  // ← falla con PTY output
            // ...
        }
    },
    onEOF: { ... }
)

// DESPUÉS: solo logging, sin parsing
pty.startReading(
    onData: { data in
        // Solo loggeamos en debug para diagnóstico.
        // No intentamos parsear — el output del PTY interactivo no es JSON limpio.
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sessionLogger.debug("PTY output: \(String(trimmed.prefix(200)))")
            }
        }
    },
    onEOF: {
        sessionLogger.info("PTY process closed stdout (EOF)")
    }
)
```

---

### 4. `BackgroundCLISession.swift` — Eliminar `TaskOutputState` y `LineBuffer`

Con el cambio anterior ya no son necesarios. Eliminar ambas clases privadas del archivo:

```swift
// ELIMINAR estas dos clases del final de BackgroundCLISession.swift:

// private final class TaskOutputState: Sendable { ... }
// private final class LineBuffer: Sendable { ... }
```

---

### 5. `BackgroundCLISession.swift` — Eliminar el evento `.taskFired`

Sin parsing del output del PTY, el evento `.taskFired` no se puede emitir desde aquí. Hay dos opciones:

**Opción A (recomendada)**: Eliminar `.taskFired` del enum `SessionEvent` y de `CronJobsStore.handleSessionEvent`. El output de las tareas `/loop` se recoge por otro mecanismo (ver punto 6).

**Opción B**: Mantener `.taskFired` pero emitirlo desde `CronJobsStore` cuando detecta que ha pasado el intervalo de una tarea. Menos preciso pero más simple de implementar.

```swift
// Enum simplificado:
enum SessionEvent: Sendable {
    case text(String)          // output de mensajes normales (no /loop)
    case error(String)
    case processExited(status: Int32)
    case stateChanged(SessionState)
    // .taskFired eliminado — el output de /loop se gestiona por separado
}
```

---

### 6. Recoger el output de las tareas `/loop`

Cuando Claude CLI ejecuta una tarea programada por `/loop`, lo hace internamente. El output no llega por el mismo PTY de forma parseable. 

La solución es que `CronJobsStore` use `CLIBridge` (modo `--print` normal) para ejecutar periódicamente una consulta de estado, o bien confiar en que el propio `/loop` entregue el resultado a través de los canales configurados (notificaciones, Slack, etc.) en el payload de la tarea.

Para la entrega de resultados, el mensaje que se pasa a `/loop` debe incluir instrucciones de entrega:

```swift
// En BackgroundCLISession.scheduleTask():
func scheduleTask(interval: String, message: String, deliveryChannel: String? = nil) -> Bool {
    var fullMessage = message
    
    // Si hay canal de entrega configurado, añadirlo al mensaje
    // para que Claude lo incluya en su respuesta de forma que
    // CronJobsStore pueda procesarlo
    if let channel = deliveryChannel {
        fullMessage += " [Deliver result to: \(channel)]"
    }
    
    let loopCommand = "/loop \(interval) \(fullMessage)"
    return sendMessage(loopCommand)
}
```

---

## Resumen de cambios por archivo

| Archivo | Qué cambiar |
|---|---|
| `CLIParser.swift` | `buildBackgroundSessionArguments()`: eliminar `--output-format stream-json` y `--verbose`. Eliminar `systemPrompt` del parámetro (no aplica en modo PTY). Puede también eliminarse `stripANSI()` si ya no se usa. |
| `PTYProcess.swift` | `configureTerminal()`: añadir `ISIG` e `IXON` al conjunto de flags desactivados. |
| `BackgroundCLISession.swift` | `launchProcess()`: simplificar el bloque `startReading` a solo logging. Eliminar `TaskOutputState` y `LineBuffer`. Actualizar `SessionEvent` eliminando `.taskFired`. |
| `CronJobsStore.swift` | `handleSessionEvent()`: eliminar el case `.taskFired`. Ajustar la lógica de run logs si es necesario. |

---

## Flujo correcto tras el fix

```
McClaw arranca
    ↓
BackgroundCLISession.launchProcess()
    ↓
forkpty() → claude --session-id <UUID>
  (modo interactivo puro, sin --output-format)
    ↓
PTY activo, CLI espera input como si fuera terminal
    ↓
restoreScheduledTasks()
    ↓
write(masterFD, "/loop 5m dime la hora\n")
    ↓
Claude CLI interpreta /loop como slash command ✓
    ↓
Claude registra la tarea internamente
    ↓
Cada 5 minutos: Claude ejecuta "dime la hora" autónomamente
    ↓
McClaw no interviene en cada ejecución
```

---

## Verificación

Para confirmar que `/loop` se registra correctamente tras el fix, los logs deberían mostrar algo así después del `write()`:

```
[info] Sent to PTY: /loop 5m dime la hora
[debug] PTY output: ✓ Scheduled: "dime la hora" every 5m (job ID: a1b2c3d4)
```

Si aparece el mensaje de confirmación del CLI, el loop está registrado. Si el PTY output sigue siendo silencio total, el problema es que el CLI no está arrancando en modo interactivo — revisar que `--print` no esté presente en los args y que el PTY esté correctamente configurado con `forkpty()`.
