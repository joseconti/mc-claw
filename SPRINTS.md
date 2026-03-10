# McClaw - Sprint Tracker

## Proyecto
App nativa macOS (Swift/SwiftUI) que wrappea CLIs de IA (Claude, ChatGPT, Gemini, Ollama) via CLI Bridge. Conecta a Gateway via WebSocket para channels, plugins y automation.

## Estado: Sprint 1-10 COMPLETADO | Sprint 11 COMPLETADO | Sprint 12 COMPLETADO | Sprint 13 COMPLETADO | Sprint 14 COMPLETADO | Sprint 15 COMPLETADO | Sprint 16 COMPLETADO | Sprint 17 COMPLETADO | Sprint 18 COMPLETADO | Sprint 19 COMPLETADO | Sprint 20 COMPLETADO

---

## Sprint 1: Hacerlo Funcional ✅ COMPLETADO

### 1.1 Fix CLI PATH Detection ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/CLIBridge/CLIDetector.swift`
- **Cambio**: `findBinary()` ahora busca en paths hardcoded (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, etc.) antes de fallback a login shell (`/bin/zsh -lc "which ..."`)
- **Problema resuelto**: Apps GUI no heredan PATH del shell, `which` no encontraba binarios

### 1.2 Config Persistence - Load ✅
- **Archivos**: `AppDelegate.swift`, `ConfigStore.swift`
- **Cambio**: Al arrancar, carga `~/.mcclaw/mcclaw.json` y aplica valores a AppState via `applyToState()`
- **Nuevo método**: `ConfigStore.applyToState(_ config:)`

### 1.3 Config Persistence - Save ✅
- **Archivos**: `ConfigStore.swift`, `OnboardingWizard.swift`, `SettingsWindow.swift`
- **Cambio**: `saveFromState()` extrae estado actual y guarda JSON. Se llama al completar onboarding y al cambiar settings (voice, connection, canvas)
- **Nuevo campo**: `hasCompletedOnboarding` en `McClawConfig`

### 1.4 Handle No CLI ✅
- **Archivos**: `ChatViewModel.swift`, `ChatWindow.swift`
- **Cambio**: Si no hay CLI, muestra mensaje sistema en chat + botón "Open Settings" en header con icono warning

### 1.5 Session ID Generation ✅
- **Archivos**: `AppDelegate.swift`, `MenuContentView.swift`
- **Cambio**: UUID generado al arrancar. "New Chat" genera nuevo ID

---

## Sprint 2: Hacerlo Usable ✅ COMPLETADO

### 2.1 Markdown en mensajes ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Chat/MessageBubbleView.swift`
- **Cambio**: `markdownContent` computed property usa `AttributedString(markdown:)` con `inlineOnlyPreservingWhitespace` y fallback a texto plano

### 2.2 Gateway connection graceful ✅
- **Archivos**: `McClaw/Sources/McClaw/App/AppDelegate.swift`, `McClaw/Sources/McClaw/Views/Onboarding/OnboardingWizard.swift`
- **Cambio**: Usa `GatewayDiscovery.discoverLocal()` antes de conectar. Si no hay Gateway, simplemente logea y sigue. Aplicado tanto en AppDelegate como en OnboardingWizard

### 2.3 Persistir estado de onboarding ✅
- **Archivos**: `ConfigStore.swift`, `AppState.swift`, `OnboardingWizard.swift`, `AppDelegate.swift`
- **Verificado**: Flujo end-to-end funciona: `completeOnboarding()` → `saveFromState()` → `mcclaw.json` → `loadConfig()` → `applyToState()` → `hasCompletedOnboarding` restaurado

### 2.4 CLI switching en chat header ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Chat/ChatWindow.swift`
- **Cambio**: Si hay >1 CLI instalado, muestra Picker/Menu en el header. El cambio se persiste automáticamente via `saveFromState()`. Si solo hay 1 CLI, muestra texto estático

---

## Sprint 3: Hacerlo Robusto ✅ COMPLETADO

### 3.1 Tests CLIBridge ✅
- **Archivo nuevo**: `McClaw/Sources/McClawKit/CLIParser.swift` — lógica de parsing/args extraída de CLIBridge para testabilidad
- **Tests**: `McClaw/Tests/McClawKitTests/CLIParserTests.swift` — 18 tests para `parseLine()` con JSON real de Claude CLI y `buildArguments()` por proveedor
- **Refactor**: `CLIBridge.swift` ahora delega a `CLIParser` (público en McClawKit)

### 3.2 Tests protocolo Gateway ✅
- **Archivo nuevo**: `McClaw/Sources/McClawProtocol/WSModels.swift` — tipos WS movidos a McClawProtocol para testabilidad
- **Tests ampliados**: `McClaw/Tests/McClawProtocolTests/McClawProtocolTests.swift` — 19 tests para encoding/decoding de WSRequest, WSResponse, WSEvent, AnyCodableValue (string, int, bool, null, array, dict, nested, raw JSON)
- **Refactor**: `GatewayModels.swift` usa `@_exported import McClawProtocol` para re-exportar tipos WS

### 3.3 Routing eventos Gateway → Chat ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Gateway/GatewayConnectionService.swift`
- **Cambio**: Callback `onChatMessage` + método `setOnChatMessage()`. `handleEvent("chat.message")` extrae text/sessionId y llama al callback
- **Archivo**: `McClaw/Sources/McClaw/Views/Chat/ChatViewModel.swift`
- **Cambio**: `subscribeToGateway()` registra handler, `handleGatewayMessage()` añade mensaje al chat

### 3.4 File picker para attachments ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Chat/ChatInputBar.swift`
- **Cambio**: `openFilePicker()` usa `NSOpenPanel` con selección múltiple, crea `Attachment` con filename, MIME type (via UTType), path y size

### 3.5 CLI installation desde UI ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Settings/SettingsWindow.swift`
- **Cambio**: Botón Install conectado a `CLIInstaller.install()`, muestra ProgressView durante instalación, log de salida en scroll view monoespaciada, rescan automático tras completar

### 3.6 MCP Server Configuration UI ✅
- **Archivos nuevos**:
  - `McClaw/Sources/McClaw/Models/MCP/MCPModels.swift` — MCPServerConfig, MCPTransport, MCPScope, MCPServerFormData, EnvVarEntry, MCPProviderSupport, MCPError
  - `McClaw/Sources/McClawKit/MCPParser.swift` — Lógica pura de parsing/building: Claude CLI args, Claude list parsing, Gemini settings JSON read/write
  - `McClaw/Sources/McClaw/Services/MCP/MCPConfigManager.swift` — Actor @MainActor @Observable con backend híbrido: Claude via `claude mcp` CLI, Gemini via ~/.gemini/settings.json
  - `McClaw/Sources/McClaw/Views/Settings/MCPSettingsTab.swift` — Tab con lista + detalle split view, provider selector, add/edit/remove
  - `McClaw/Sources/McClaw/Views/Settings/MCPServerEditor.swift` — Sheet form: nombre, transport picker, command/args o URL, scope (Claude), env vars dinámicas
- **Tests**: `McClaw/Tests/McClawKitTests/MCPParserTests.swift` — 16 tests (Claude args, Claude list parsing, Gemini JSON CRUD)
- **Soporte por provider**: Claude (stdio/sse/streamable-http, user/project scope), Gemini (stdio only). ChatGPT/Ollama muestran "not supported"

---

## Sprint 4: Cron & Automation (Scheduling Híbrido) ✅ COMPLETADO

> **Arquitectura**: Claude CLI tiene scheduling nativo (`claude task`). Otros providers usan Gateway cron.
> McClaw ofrece una UI unificada que delega al backend correcto según el provider activo.

### 4.1 Modelos Cron ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Models/Cron/CronModels.swift`
- **Cambio**: CronJob, CronSchedule (at/every/cron), CronPayload (systemEvent/agentTurn), CronDelivery, CronJobState, CronRunLogEntry, CronEvent, CronStatusResponse, DurationFormatting helper


### 4.2 CronJobsStore ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Cron/CronJobsStore.swift`
- **Cambio**: @MainActor @Observable singleton con lógica híbrida:
  - Si provider activo es Claude → delega a `claude task` via Process (list/create/delete)
  - Si es otro provider → delega al Gateway via `cron.*` WebSocket RPC
  - Polling cada 30s + event-driven refresh via cron events del Gateway
- **Gateway RPC**: Añadidos métodos `cronList`, `cronStatus`, `cronRuns`, `cronAdd`, `cronUpdate`, `cronRemove`, `cronRun` a GatewayConnectionService
- **Event handling**: Nuevo callback `onCronEvent` + handling del evento "cron" en el switch de eventos

### 4.3 CronJobEditor (UI) ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Views/Settings/CronJobEditor.swift`
- **Cambio**: Form completo para crear/editar jobs: schedule picker (at/every/cron), payload editor (systemEvent/agentTurn), delivery mode (announce/none), session target (main/isolated), validación, auto-switching de payload según session target

### 4.4 CronSettings Tab ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Views/Settings/CronSettings.swift`
- **Archivo**: `McClaw/Sources/McClaw/Views/Settings/SettingsWindow.swift`
- **Cambio**: Tab "Cron" con split-pane layout (job list + detail), scheduler disabled banner, context menus (run/edit/enable/delete), detail card con schedule/payload/delivery summary, run history con status pills, confirmation dialog para delete

### 4.5 Webhooks básicos ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Cron/WebhookReceiver.swift`
- **Cambio**: @MainActor @Observable singleton para register/remove/list webhooks via Gateway `webhook.*` RPC methods

---

## Sprint 5: Exec Approvals & Security Completa ✅ COMPLETADO

### 5.1 ExecApprovals completo ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Security/ExecApprovals.swift`
- **Cambio**: Glob pattern matching (*, **, ?), shell wrapper parsing (bash -c unwrap con fail-closed), allowlist/denylist persistentes en `~/.mcclaw/exec-approvals.json` (permisos 0o600), command resolution via PATH, tilde expansion
- **Archivo nuevo**: `McClaw/Sources/McClawKit/SecurityKit.swift` — Lógica pura extraída para testabilidad: globToRegex, validateAllowlistPattern, parseShellPayload, sanitizeEnvironment, blocklists

### 5.2 Approval UI Dialog ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Views/Security/ExecApprovalDialog.swift`
- **Cambio**: Dialog modal con command display (monospace), details disclosure (executable, resolved path, arguments, host), botones Allow Once / Always Allow / Don't Allow. Integrado como sheet en ChatWindow
- **Flujo**: CLIBridge.send() → ExecApprovals.checkApproval() → si needsApproval → dialog → decisión → continuar/denegar

### 5.3 Host Environment Sanitization ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Security/HostEnvSanitizer.swift`
- **Cambio**: Delega a SecurityKit. Blocklists: NODE_OPTIONS, PYTHONPATH, DYLD_*, LD_*, BASH_FUNC_*, etc. Override-blocked: HOME, EDITOR, GIT_SSH_COMMAND, etc. Shell wrapper mode ultra-restrictivo (solo TERM, LANG, LC_*). PATH nunca overrideable
- **Integración**: CLIBridge.send() aplica HostEnvSanitizer.sanitize() antes de cada Process

### 5.4 Permissions Manager (TCC) ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Security/PermissionManager.swift`
- **Cambio**: @MainActor @Observable singleton. Check/request: microphone (AVCaptureDevice), camera (AVCaptureDevice), accessibility (AXIsProcessTrusted), screen recording (CGWindowListCopyWindowInfo proxy), notifications (UNUserNotificationCenter). Open System Settings para permisos no requestables programáticamente
- **UI**: SecuritySettingsTab muestra todas las permissions con status badge (granted/denied/notDetermined) y botón Request/Open Settings

### 5.5 Integración completa ✅
- **CLIBridge**: Approval check antes de process.run(), env sanitization via HostEnvSanitizer
- **AppState**: showingApprovalDialog state
- **ConfigStore**: Persiste execMode, carga allowlist/denylist via ExecApprovals.loadFromFile()
- **SettingsWindow**: SecuritySettingsTab completo con mode picker (segmented), allowlist management (add/remove), denylist display, TCC permissions grid
- **GatewayConnectionService**: exec.approval.requested event handler, execApprovalResolve RPC
- **Tests**: 21 tests nuevos en SecurityKitTests (glob matching, pattern validation, shell wrapper parsing, env sanitization)

---

## Sprint 6: Channels & Plugins Completos ✅ COMPLETADO

### 6.1 Channel Management UI ✅
- **Archivos nuevos**:
  - `McClaw/Sources/McClaw/Models/Channel/ChannelModels.swift` — ChannelsStatusSnapshot con per-channel status types (WhatsApp, Telegram, Discord, GoogleChat, Signal, iMessage), ChannelAccountSnapshot, login/logout result types
  - `McClaw/Sources/McClaw/Models/Channel/ConfigSchemaSupport.swift` — ConfigSchemaNode, ConfigUiHint, ConfigPath para generación dinámica de forms desde JSON Schema
  - `McClaw/Sources/McClaw/Services/Channels/ChannelsStore.swift` — @MainActor @Observable singleton con lifecycle polling, config schema loading, WhatsApp login flow (QR), channel logout, config CRUD
  - `McClaw/Sources/McClaw/Views/Settings/ChannelConfigForm.swift` — ConfigSchemaForm dinámico: objects, arrays, strings, numbers, booleans, enums, sensitive fields
- **Cambio**: `SettingsWindow.swift` — ChannelsSettingsTab completo con split-pane sidebar/detail, per-channel status badges, WhatsApp QR section, generic channel config editor, save/reload

### 6.2 Channel Routing ✅
- **Archivo**: `GatewayConnectionService.swift` — Nuevos RPC: `channelsStatus()`, `channelLogout()`, `whatsAppLoginStart()`, `whatsAppLoginWait()`
- **Eventos**: `channels`, `channels.status` events trigger refresh via callback
- **Config**: Full config.schema + config.get + config.set flow para routing/allowlist config por canal

### 6.3 Plugin Runtime completo ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Plugins/PluginRuntime.swift` — Refactored a @Observable, con refreshPlugins (parse real), install, uninstall, toggle, busy tracking per-plugin
- **RPC nuevos**: `pluginsList()`, `pluginInstall()`, `pluginUninstall()`, `pluginToggle()`, `pluginUpdateConfig()`
- **Eventos**: `plugins`, `plugins.changed` events trigger refresh

### 6.4 Plugin Config UI ✅
- **Archivo**: `SettingsWindow.swift` — PluginsSettingsTab completo: plugin list con toggle, kind badge, version, uninstall con confirmación, install sheet (npm package name), refresh, status messages
- **Archivo**: `ChannelConfigForm.swift` — ConfigSchemaForm reutilizable para plugins y channels

### 6.5 Skills Management ✅
- **Archivos nuevos**:
  - `McClaw/Sources/McClaw/Models/Skills/SkillModels.swift` — SkillsStatusReport, SkillStatus, SkillRequirements, SkillMissing, SkillStatusConfigCheck, SkillInstallOption, SkillInstallResult, SkillUpdateResult
  - `McClaw/Sources/McClaw/Services/Skills/SkillsStore.swift` — @MainActor @Observable singleton con refresh, install, setEnabled, updateEnv, busy tracking
  - `McClaw/Sources/McClaw/Views/Settings/SkillsSettings.swift` — SkillsSettingsTab con filter (all/ready/needsSetup/disabled), SkillRow con emoji, source tag, requirements summary, config checks, env editor modal, install buttons
  - `McClaw/Sources/McClawKit/ChannelsPluginsKit.swift` — Lógica pura extraída: parseChannelStatus, parsePluginsList, parseSkillsStatus, skillSourceLabel, isConfigPathSensitive
- **RPC nuevos**: `skillsStatus()`, `skillsInstall()`, `skillsUpdate()`
- **Tests**: 16 tests nuevos en ChannelsPluginsKitTests (channel status parsing, plugin list parsing, skills status parsing, source labels, config sensitivity)
- **Tab**: Skills tab añadido a SettingsWindow con icono sparkles

---

## Sprint 7: Voice Mode — Experiencia JARVIS ✅ COMPLETADO

> **Filosofía**: APIs nativas de macOS (SFSpeechRecognizer + NSSpeechSynthesizer) para Voice Mode
> tipo JARVIS: hablar → texto en chat; IA responde → lectura en voz alta. Local, offline-capable.

### 7.1 VoiceModeService (Core) ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Voice/VoiceModeService.swift`
- **Cambio**: @MainActor @Observable singleton coordinador. Estados: off/listening/speaking/processing. Toggle on/off, activate/deactivate. Pausa reconocimiento durante TTS (anti-feedback). Reanuda escucha tras terminar de hablar. Callback `onFinalTranscript` para auto-send. `speakResponse()` y `speakResponseChunk()` para TTS streaming. `interruptSpeaking()` para cortar TTS

### 7.2 SpeechRecognizer (Input: Voz → Texto) ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Voice/SpeechRecognitionService.swift`
- **Cambio**: `SFSpeechRecognizer` + `AVAudioEngine` para reconocimiento continuo en tiempo real. `AsyncStream<SpeechEvent>` con `.partialTranscript`, `.finalTranscript`, `.audioLevel`, `.error`. Detección de pausa (silence threshold configurable 0.5-3s) → auto-envío. Multi-idioma configurable. Auto-restart tras recognition task expiry. Audio level calculation (RMS → normalized). Integración con PermissionManager para mic permission

### 7.3 SpeechSynthesizer (Output: Texto → Voz) ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Voice/SpeechSynthesisService.swift`
- **Cambio**: `NSSpeechSynthesizer` TTS con cola de utterances. Streaming-aware: empieza a leer al primer chunk. Voice selection (`availableVoices()`, `previewVoice()`). Rate/volume control. Markdown cleaning para speech (code blocks, links, formatting). Sentence splitting para pacing natural. `onFinishedSpeaking` callback. NSSpeechSynthesizerDelegate para queue processing

### 7.4 Voice Mode Toggle en ChatInputBar ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Chat/ChatInputBar.swift`
- **Cambio**: Botón mic toggle entre attach y text field. Estados visuales: OFF (gris), listening (verde pulsante con symbolEffect), speaking (azul), processing (naranja). Transcript parcial en tiempo real (texto gris/itálico). Keyboard shortcut `Cmd+Shift+V`. Placeholder dinámico ("Voice Mode active..." vs "Message...")

### 7.5 Push-to-Talk (Hotkey) ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Voice/PushToTalkService.swift`
- **Cambio**: Global hotkey monitor via `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`. Right Option por defecto (configurable). Hold = graba, release = envía transcript. Interrumpe TTS al presionar. Soporta Right/Left Option, Right/Left Shift, Right Control. Requiere Accessibility permission

### 7.6 Voice Wake Word ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Voice/VoiceWakeRuntime.swift`
- **Cambio**: Implementación completa con `SFSpeechRecognizer` en modo continuo. On-device recognition cuando disponible (lower latency). Trigger word configurable ("hey claw" por defecto). Auto-restart tras detection o error. NSSound.beep() al detectar. `onWakeWordDetected` callback activa Voice Mode

### 7.7 Voice Overlay View ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Voice/VoiceOverlayView.swift`
- **Cambio**: Overlay compacto integrado en ChatWindow (entre mensajes e input). Waveform indicator con pulse animation reactivo al audio level. State label (Listening/Speaking/Processing). Skip speech button cuando speaking. Close button para desactivar. ultraThinMaterial background

### 7.8 Voice Settings ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Views/Settings/VoiceSettings.swift`
- **Cambio**: VoiceSettingsTab con 6 secciones: Microphone permission status/request, Speech Recognition (language picker con todos los locales de SFSpeechRecognizer, silence threshold slider 0.5-3s), Text-to-Speech (voice picker con preview, speed slider 100-300 wpm, volume slider), Push-to-Talk (toggle + accessibility warning), Wake Word (toggle + custom phrase), Test (mic test con live transcript display)
- **Archivo**: `McClaw/Sources/McClaw/Views/Settings/SettingsWindow.swift` — Voice tab añadido con icono waveform, voice toggles removidos de General tab

### 7.9 Tests Voice ✅
- **Archivo nuevo**: `McClaw/Tests/McClawKitTests/VoiceKitTests.swift` — 23 tests
- **Archivo nuevo**: `McClaw/Sources/McClawKit/VoiceKit.swift` — Lógica pura extraída: cleanForSpeech (markdown stripping), splitIntoSentences, matchWakeWord, normalizeAudioLevel, shouldAutoSend, VoiceConfig Codable
- **Tests**: cleanForSpeech (code blocks, inline code, links, formatting, headers, bullets, whitespace, empty), splitIntoSentences (multiple, single, empty), matchWakeWord (match, case insensitive, no match, multiple triggers), normalizeAudioLevel (range, clamp, custom gain), shouldAutoSend (yes, no, exact threshold), VoiceConfig (defaults, encode/decode roundtrip)

### 7.10 Integración completa ✅
- **ChatViewModel**: Auto-speak AI responses cuando voice mode activo. Streaming TTS: accumula chunks y habla en sentence boundaries. Stop TTS on abort
- **ChatWindow**: VoiceOverlayView integrado (visible cuando voice mode activo). setupVoiceMode() wires onFinalTranscript → send, push-to-talk → send, wake word → activate
- **AppState**: Nuevos campos: selectedVoice, speechRate, speechVolume, silenceThreshold, recognitionLocale
- **ConfigStore**: McClawConfig ampliado con voice settings (pushToTalkEnabled, selectedVoice, speechRate, speechVolume, silenceThreshold, recognitionLocale, triggerWords). applyToState() configura servicios de voz. saveFromState() persiste voice config

---

## Sprint 8: Canvas & Node Mode ✅ COMPLETADO

> **Filosofía**: Canvas como panel flotante con WKWebView + custom URL scheme. Node mode expone
> capacidades macOS (canvas, camera, screen, location, system) al Gateway via bridge invoke protocol.

### 8.1 Canvas Window Controller ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Canvas/CanvasWindowController.swift`
- **Cambio**: NSPanel flotante (non-activating, utility window) con WKWebView. Placement configurable (x, y, width, height). Snapshot (PNG/JPEG con resize). Navigation via custom scheme `mcclaw-canvas://`. A2UI bridge JS inyectado via WKUserScript. Panel sizing: 520x680 default, min 360x360

### 8.2 Canvas JS Bridge ✅
- **Archivos**:
  - `McClaw/Sources/McClaw/Services/Canvas/CanvasManager.swift` — @MainActor @Observable singleton coordinador: show/hide/navigate/eval/snapshot, A2UI push/pushJSONL/reset, bridge invoke handler para todos los canvas.* commands
  - `McClaw/Sources/McClaw/Services/Canvas/CanvasA2UIActionMessageHandler.swift` — WKScriptMessageHandler para DOM events a2uiaction → Gateway agent.send
  - `McClaw/Sources/McClaw/Views/Canvas/CanvasView.swift` — Inline canvas view con header + open/close panel button, CanvasSchemeHandler completo (sirve archivos desde ~/.mcclaw/canvas/{sessionKey}/, MIME types, 404 handling)
- **A2UI protocol**: JS bridge bidireccional: a2uiaction DOM events → Swift → Gateway, a2ui:push/pushJSONL/reset events → JS
- **Custom scheme**: `mcclaw-canvas://sessionKey/path` → `~/.mcclaw/canvas/sessionKey/path` con MIME type detection

### 8.3 Canvas File Watcher ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Canvas/CanvasFileWatcher.swift`
- **Cambio**: DispatchSource.makeFileSystemObjectSource para hot-reload. Monitorea write/rename/delete/extend en directorio de sesión canvas. Auto-reload del WebView al detectar cambios

### 8.4 Node Mode completo ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Node/NodeMode.swift` — @MainActor @Observable singleton con dispatch completo:
  - `canvas.*`: delegado a CanvasManager (present, hide, navigate, eval, snapshot, a2ui.push/pushJSONL/reset)
  - `camera.*`: list (AVCaptureDevice.DiscoverySession), snap (AVCapturePhotoOutput), clip (AVCaptureMovieFileOutput)
  - `screen.record`: ScreenCaptureKit (SCStream + AVAssetWriter)
  - `system.run`: delegado a exec approvals flow
  - `system.which`: Process(/usr/bin/which)
  - `system.notify`: UNUserNotificationCenter
  - `location.get`: CLLocationManager
- **Bridge protocol**: BridgeInvokeRequest/Response, BridgeHello, BridgeEventFrame (types en McClawKit)
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Node/NodeLocationService.swift` — CLLocationManager con async/await wrapper, requestWhenInUseAuthorization

### 8.5 Screen & Camera Services ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Node/ScreenRecordService.swift`
  - ScreenCaptureKit: SCShareableContent, SCStream, SCStreamConfiguration
  - AVAssetWriter con H.264 video + optional AAC audio
  - Configurable: screen index, duration (max 60s), fps (max 30), audio
  - Output: MP4 a /tmp/mcclaw-screen-record-*.mp4
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Node/CameraCaptureService.swift`
  - Actor-based con AVCaptureSession
  - snap(): AVCapturePhotoOutput + warm-up delay + resize + JPEG encoding
  - clip(): AVCaptureMovieFileOutput + max 30s + optional audio
  - listDevices(): DiscoverySession enumeration (front/back/external)
  - Permission checking + authorization request

### 8.6 Models & Kit ✅
- **Archivo nuevo**: `McClaw/Sources/McClawKit/CanvasNodeKit.swift` — Pure logic extraída para testabilidad:
  - Canvas: CanvasCommand, CanvasA2UICommand, CanvasPresentParams, CanvasNavigateParams, CanvasEvalParams, CanvasSnapshotParams/Format, CanvasPlacementParams
  - Camera: CameraCommand, CameraFacing, CameraSnapParams, CameraClipParams, CameraDeviceInfo
  - Screen: ScreenCommand, ScreenRecordParams
  - System: SystemCommand, LocationCommand
  - Bridge: BridgeInvokeRequest (con decodeParams<T>), BridgeInvokeResponse (success/failure factories), BridgeEventFrame, BridgeHello
  - Node: NodeCommandCategory, NodeErrorCode, NodeError
  - Helpers: sanitizeSessionKey, canvasSessionDirectory, mimeTypeForExtension, parseNodeCommand, buildNodeCommandList, buildNodeCapabilities

### 8.7 Gateway Integration ✅
- **Archivo**: `GatewayConnectionService.swift` — Nuevos RPCs: sendCanvasA2UIAction (agent.send), sendNodeInvokeResponse, sendNodeEvent, sendNodeHello
- **Eventos**: `node.invoke` event → callback → NodeMode.handleInvoke → response enviada de vuelta
- **ChatWindow**: setupNodeMode() wires Gateway node.invoke events → NodeMode dispatch → response

### 8.8 State & Config Integration ✅
- **AppState**: Nuevos campos: cameraEnabled, screenEnabled
- **ConfigStore**: McClawConfig ampliado con cameraEnabled, screenEnabled. applyToState() configura NodeMode. saveFromState() persiste
- **SettingsWindow**: AdvancedSettingsTab ampliado con Canvas & Node section (canvas toggle, camera toggle, screen toggle, node capabilities disclosure, node ID display)

### 8.9 Tests ✅
- **Archivo nuevo**: `McClaw/Tests/McClawKitTests/CanvasNodeKitTests.swift` — 26 tests:
  - sanitizeSessionKey (special chars, preserves valid)
  - canvasSessionDirectory (correct path, sanitized key)
  - mimeTypeForExtension (HTML, CSS, JS, images, video, audio, PDF, case insensitive, unknown)
  - parseNodeCommand (valid canvas/camera/screen/system/location, invalid)
  - buildNodeCommandList (base, camera, screen, all)
  - buildNodeCapabilities (none, camera, screen, all)
  - BridgeInvokeRequest decodeParams (valid, invalid JSON, nil)
  - BridgeInvokeResponse (success, failure, success with payload)
  - BridgeHello (encode/decode roundtrip)
  - CameraSnapParams, ScreenRecordParams, CameraDeviceInfo, NodeError, CanvasSnapshotFormat (Codable)

---

## Sprint 9: Remote & IPC ✅ COMPLETADO

> **Filosofía**: IPC via Unix domain socket con HMAC auth. Remote mode via SSH tunnel
> o conexión directa wss://. ConnectionModeCoordinator orquesta el switching.

### 9.1 Unix Socket IPC ✅
- **Archivo**: `McClaw/Sources/McClawIPC/McClawIPC.swift` — Reescritura completa:
  - Actor IPCConnection con Unix domain socket (AF_UNIX, SOCK_STREAM)
  - UID verification via LOCAL_PEERCRED (getpeereid)
  - HMAC-SHA256 handshake con nonce challenge/response (CommonCrypto)
  - Length-prefixed frames (4-byte big-endian header)
  - IPCRequest enum Codable: status, notify, runShell, agent, canvasPresent/Hide/Eval, nodeInvoke
  - IPCResponse, IPCMessage, IPCFrame models
  - Receive loop via detached Task con raw fd reads
  - Socket path: `~/.mcclaw/control.sock` (configurable)
  - Socket permission verification (warn if world-readable)

### 9.2 SSH Tunnel Manager ✅
- **Archivos nuevos**:
  - `McClaw/Sources/McClaw/Services/Remote/RemotePortTunnel.swift` — SSH port forwarding tunnel:
    - `ssh -N -L localPort:127.0.0.1:remotePort` via Process
    - SSH options: BatchMode, ExitOnForwardFailure, StrictHostKeyChecking, ServerAlive keepalive
    - Port detection via NWListener (free port finder)
    - IPv4 + IPv6 dual binding check (canBindIPv4/canBindIPv6)
    - Stderr drain para prevenir ssh blocking
    - Immediate exit detection (150ms) con error surfacing
    - SSHTarget parser: user@host:port format
  - `McClaw/Sources/McClaw/Services/Remote/RemoteTunnelManager.swift` — Tunnel lifecycle manager:
    - Actor singleton con tunnel reuse (reuses existing if healthy)
    - Restart backoff (2s minimum between restarts)
    - ensureControlTunnel() con auto-create si no existe
    - stopAll() para cleanup graceful

### 9.3 Remote Connection UI ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Views/Settings/RemoteSettingsTab.swift`
- **Cambio**: Tab "Remote" con icono network en SettingsWindow:
  - Connection Mode picker (segmented: Unconfigured/Local/Remote)
  - Gateway port config
  - Status indicator (colored dot + text)
  - Remote Configuration section (visible solo en modo remote):
    - Transport picker (SSH Tunnel / Direct)
    - SSH: target (user@host:port), identity file con Browse (NSOpenPanel .ssh)
    - Direct: URL field con validación (wss:// required para non-loopback)
  - Test Connection button con SSH test real (ssh echo mcclaw-test-ok)
  - Apply button que invoca ConnectionModeCoordinator
- **Archivo**: `SettingsWindow.swift` — Remote tab añadido, Gateway section en General simplificado a read-only

### 9.4 Connection Mode Coordinator ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Remote/ConnectionModeCoordinator.swift`
- **Cambio**: @MainActor singleton que orquesta mode switching:
  - `apply(mode:)` → unconfigured/local/remote dispatch
  - unconfigured: stopAll tunnels + disconnect Gateway
  - local: stop tunnels, set ws://127.0.0.1:port/ws, connect
  - remote SSH: parse SSHTarget, ensureControlTunnel, set ws://127.0.0.1:localPort/ws, connect
  - remote direct: validate + normalize URL (wss only for non-loopback), connect
- **GatewayRemoteConfig**: URL normalization, loopback check, default ports (ws:3577, wss:443)
- **GatewayConnectionService**: nuevo `setGatewayURL(_ url:)` para URL dinámica (ya no hardcoded)

### 9.5 RemoteKit (Lógica pura) ✅
- **Archivo nuevo**: `McClaw/Sources/McClawKit/RemoteKit.swift` — Pure logic extraída para testabilidad:
  - RemoteSSHTarget: parse, format, Codable, Equatable
  - RemoteURLValidator: normalize, localURL, isLoopback, defaultPort, dashboardURL
  - ConnectionModeResolver: priority cascade (explicit → remoteUrl → remoteTarget → default)
  - SSHArgumentsBuilder: buildTunnelArgs (full SSH options), buildTestArgs (connectivity check)
  - IPCFrameHeaderKit: 4-byte big-endian length prefix encode/decode
- **Tests**: `McClaw/Tests/McClawKitTests/RemoteKitTests.swift` — 36 tests:
  - RemoteSSHTarget: parse full/user+host/host+port/host only/empty/trimmed/invalid port/out of range/format roundtrip/codable
  - RemoteURLValidator: valid wss/valid ws loopback/ws non-loopback rejected/http rejected/empty host/empty string/default port wss/ws/existing port preserved/isLoopback/localURL/dashboardURL
  - ConnectionModeResolver: explicit mode wins/remote URL triggers/remote target triggers/empty values/no onboarding/onboarding done
  - SSHArgumentsBuilder: tunnel args basic/with identity+port/empty identity/test args
  - IPCFrameHeaderKit: roundtrip/zero/max/known bytes

### 9.6 Config & State Integration ✅
- **AppState**: Nuevo campo `gatewayPort: Int = 3577`
- **ConfigStore**: McClawConfig ampliado con `remoteTransport`, `remoteTarget`, `remoteUrl`, `remoteIdentity`. applyToState() configura gateway port + remote fields. saveFromState() persiste todo

---

## Sprint 10: Polish & Production ✅ COMPLETADO

### 10.1 HealthSnapshot completo ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Health/HealthStore.swift`
- **Cambio**: Parseo AnyCodableValue → HealthSnapshot via JSON encode/decode roundtrip. Polling cada 60s. Sync `channelStatuses` a AppState. `lastError` tracking + `refresh()` manual

### 10.2 Sparkle Auto-updates ✅
- **Archivos**: `Services/Updater/UpdaterService.swift` (nuevo), `Info.plist` (raíz), `scripts/build-app.sh` (nuevo), `api.joseconti.com/v1/mcclaw/appcast.xml` (nuevo)
- **Cambio**: `UpdaterService` wrappea `SPUStandardUpdaterController` como `@MainActor @Observable` singleton. Appcast en api.joseconti.com. Build script crea .app bundle con Sparkle.framework, Info.plist, code signing con Developer ID Application. Se arranca en AppDelegate paso 6

### 10.3 Diagnostics & Logging ✅
- **Archivos**: `Infrastructure/Logging/DiagnosticsFileLog.swift` (nuevo), `Infrastructure/Logging/McClawLogger.swift` (actualizado), `Views/Settings/SettingsWindow.swift` (actualizado)
- **Cambio**: `DiagnosticsFileLogHandler` escribe a `~/.mcclaw/logs/mcclaw.log` con rotación a 5MB. Serial dispatch queue + `nonisolated(unsafe)` para statics. `MultiplexLogHandler([stdout, file])`. Settings tab "Logs" con viewer, export, clear, open folder

### 10.4 Deep Links ✅
- **Archivos**: `App/DeepLinks.swift` (nuevo), `App/McClawApp.swift` (actualizado)
- **Cambio**: `DeepLinkRouter` con rutas: `mcclaw://chat`, `mcclaw://chat?session=NAME`, `mcclaw://settings`, `mcclaw://canvas`, `mcclaw://new`. `DeepLinkAwareChat` wrapper con `onOpenURL` + `openWindow` environment

### 10.5 Menu Bar completo ✅
- **Archivo**: `Views/Menu/MenuContentView.swift`
- **Cambio**: Versión display, "Open Chat"/"Open Canvas" buttons, "Recent Sessions" (últimas 5 con título y count), usage summary per provider, session store + usage tracker state integrados

### 10.6 Full Onboarding ✅
- **Archivo**: `Views/Onboarding/OnboardingWizard.swift`
- **Cambio**: Ampliado de 5 a 6 páginas: welcome, cliDetection, cliSelection, permissions, gateway, done. Permissions page con TCC requests reales via `PermissionManager` (mic, camera, notifications). Gateway page verifica reachability. `OnboardingPermissionRow` con estados Allow/Denied/Granted

### 10.7 Chat Commands ✅
- **Archivo**: `Views/Chat/ChatViewModel.swift`
- **Cambio**: Slash command routing intercepta `/` antes de enviar a CLI. 9 comandos: `/status` (provider+model+session info), `/new` (nueva sesión), `/reset` (limpiar mensajes), `/compact` (resumen), `/think` (modo razonamiento), `/model NAME` (cambiar modelo), `/provider NAME` (cambiar provider), `/session` (info sesión), `/help` (lista comandos)

### 10.8 Session Persistence ✅
- **Archivos**: `Services/Sessions/SessionStore.swift` (nuevo), `Views/Chat/ChatViewModel.swift` (actualizado), `Views/Chat/ChatWindow.swift` (actualizado)
- **Cambio**: `SessionStore` @MainActor @Observable singleton. Persiste a `~/.mcclaw/sessions/{id}.json`. `SessionRecord` Codable con sessionId, messages, cliProvider, savedAt. Auto-save tras cada streaming. `loadCurrentSession()` en ChatWindow `.onAppear`

### 10.9 Model Failover ✅
- **Archivo**: `Views/Chat/ChatViewModel.swift`
- **Cambio**: `findFallbackProvider(excluding:)` busca CLIs detectados alternativos cuando el provider activo falla. Si el asistente responde con error, auto-switch al fallback y reintenta el mensaje. Notifica al usuario del cambio via mensaje sistema

### 10.10 Usage Tracking ✅
- **Archivo**: `Services/Usage/UsageTracker.swift` (nuevo)
- **Cambio**: `UsageTracker` @MainActor @Observable singleton. Persiste a `~/.mcclaw/usage.json`. `record(provider:inputTokens:outputTokens:pricing:)` acumula stats. `totalSummary` y `summary(for:)` para display. Integrado en ChatViewModel en eventos `.usage`

---

## Decisiones Arquitectónicas

### Scheduling Híbrido (Sprint 4)
```
McClaw UI (CronJobEditor)
        │
        ├── Provider = Claude CLI
        │   └── claude task create/list/delete (nativo)
        │
        └── Provider = ChatGPT/Gemini/Ollama
            └── Gateway cron.create/list/delete (WebSocket RPC)
```
- Claude CLI tiene `claude task` nativo → McClaw delega directamente
- Otros providers no tienen scheduling → usan Gateway cron
- La UI es idéntica para el usuario, la implementación varía por provider

### CLI Bridge vs Gateway
- **Chat directo**: siempre via CLI Bridge (Process → streaming)
- **Channels/plugins**: siempre via Gateway (WebSocket)
- **Cron**: híbrido (ver arriba)
- **Tools**: depende — exec local via CLIBridge, tools remotos via Gateway

---

## Cobertura de Features

| Feature | Sprint McClaw | Estado |
|---|---|---|
| Chat con streaming | Sprint 1-2 | ✅ |
| Config persistence | Sprint 1 | ✅ |
| CLI detection + install | Sprint 1, 3 | ✅ |
| Gateway WebSocket | Sprint 2-3 | ✅ |
| Markdown rendering | Sprint 2 | ✅ |
| Cron/Scheduling | Sprint 4 | ✅ |
| Webhooks | Sprint 4 | ✅ |
| MCP Server config UI | Sprint 3 | ✅ |
| Exec Approvals completo | Sprint 5 | ✅ |
| TCC Permissions | Sprint 5 | ✅ |
| Channels management | Sprint 6 | ✅ |
| Channel routing | Sprint 6 | ✅ |
| Plugins runtime | Sprint 6 | ✅ |
| Skills management | Sprint 6 | ✅ |
| Voice Mode STT (SFSpeechRecognizer) | Sprint 7 | ✅ |
| Voice Mode TTS (NSSpeechSynthesizer) | Sprint 7 | ✅ |
| Voice toggle en ChatInputBar | Sprint 7 | ✅ |
| Push-to-talk (hotkey) | Sprint 7 | ✅ |
| Voice wake word | Sprint 7 | ✅ |
| Voice overlay + settings | Sprint 7 | ✅ |
| Canvas JS bridge | Sprint 8 | ✅ |
| Canvas window controller | Sprint 8 | ✅ |
| Node mode (camera/screen) | Sprint 8 | ✅ |
| IPC Unix socket | Sprint 9 | ✅ |
| SSH tunnel remote | Sprint 9 | ✅ |
| Remote connection UI | Sprint 9 | ✅ |
| Connection mode coordinator | Sprint 9 | ✅ |
| Health monitoring | Sprint 10 | ✅ |
| Auto-updates (Sparkle) | Sprint 10 | ✅ |
| Deep links | Sprint 10 | ✅ |
| Chat commands (9) | Sprint 10 | ✅ |
| Session persistence | Sprint 10 | ✅ |
| Usage tracking | Sprint 10 | ✅ |
| Model failover | Sprint 10 | ✅ |
| Full onboarding (6 pages) | Sprint 10 | ✅ |
| Menu bar completo | Sprint 10 | ✅ |
| Diagnostics/Logging | Sprint 10 | ✅ |

---

## Verificación por Sprint

### Sprint 1 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 5/5 passing
```

### Sprint 2 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 5/5 passing
# Manual: mensajes markdown, app sin Gateway, cambiar CLI desde chat
```

### Sprint 3 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 55/55 passing
# Manual: file picker, install CLI, eventos Gateway, MCP settings tab
```

### Sprint 4 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 39/39 passing
# Manual: crear cron job, verificar ejecución, toggle enable/disable
# Con Claude: verificar que usa `claude task`
# Sin Claude: verificar que usa Gateway cron
```

### Sprint 5 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 76/76 passing
# Manual: exec command → approval dialog aparece, approve/deny funciona
# Manual: verificar permisos TCC (mic, accessibility)
# Manual: allowlist patterns en Security settings
```

### Sprint 6 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 92/92 passing
# Manual: configurar canal (ej. Telegram), enviar/recibir mensaje
# Manual: instalar plugin, verificar config UI generada
# Manual: skills tab muestra skills con requirements, install, toggle
```

### Sprint 7 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 115/115 passing
# Manual: activar Voice Mode toggle en chat → hablar → transcript aparece en input → auto-send
# Manual: la IA responde → respuesta se lee en voz alta (TTS nativo macOS)
# Manual: push-to-talk con Right Option (mantener pulsado → soltar → envía)
# Manual: wake word "Hey McClaw" activa escucha
# Manual: Voice Settings: cambiar voz, idioma, velocidad, umbral de pausa
```

### Sprint 8 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 141/141 passing
# Manual: canvas panel flotante se abre con contenido HTML
# Manual: JS bridge A2UI bidireccional funciona
# Manual: file watcher auto-reload al cambiar archivos en ~/.mcclaw/canvas/
# Manual: camera.list devuelve dispositivos, camera.snap captura foto
# Manual: screen.record graba pantalla con ScreenCaptureKit
# Manual: system.which, system.notify funcionan
# Manual: location.get devuelve coordenadas
# Manual: Canvas & Node settings en Advanced tab
```

### Sprint 9 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 177/177 passing
# Manual: Remote tab en Settings, SSH target + identity config
# Manual: Test Connection verifica SSH connectivity
# Manual: Apply connection mode → Gateway se conecta via tunnel
# Manual: Direct wss:// URL → Gateway se conecta directo
# Manual: Cambiar mode unconfigured/local/remote → cleanup correcto
```

### Sprint 10 ✅
```bash
cd McClaw && swift build  # ✅ OK
swift test                 # ✅ 177/177 passing
# Manual: deep links (mcclaw://chat, mcclaw://settings, mcclaw://canvas)
# Manual: auto-update check en Settings > General > Updates
# Manual: /status, /new, /reset, /help commands en chat
# Manual: session history persiste entre reinicios (~/.mcclaw/sessions/)
# Manual: usage display en menu bar (tokens/coste por provider)
# Manual: model failover: si CLI falla, auto-switch a otro provider
# Manual: onboarding 6 páginas con permisos TCC reales
# Manual: logs viewer en Settings > Logs, export, clear
# Manual: health polling cada 60s desde Gateway
```

---

## Archivos Clave del Proyecto

| Área | Archivo |
|------|---------|
| Entry point | `McClaw/Sources/McClaw/App/McClawApp.swift` |
| Lifecycle | `McClaw/Sources/McClaw/App/AppDelegate.swift` |
| State | `McClaw/Sources/McClaw/State/AppState.swift` |
| CLI Bridge | `McClaw/Sources/McClaw/Services/CLIBridge/CLIBridge.swift` |
| CLI Detector | `McClaw/Sources/McClaw/Services/CLIBridge/CLIDetector.swift` |
| CLI Installer | `McClaw/Sources/McClaw/Services/CLIBridge/CLIInstaller.swift` |
| Gateway WS | `McClaw/Sources/McClaw/Services/Gateway/GatewayConnectionService.swift` |
| Config | `McClaw/Sources/McClaw/Infrastructure/Config/ConfigStore.swift` |
| Chat UI | `McClaw/Sources/McClaw/Views/Chat/ChatWindow.swift` |
| Chat Logic | `McClaw/Sources/McClaw/Views/Chat/ChatViewModel.swift` |
| Message UI | `McClaw/Sources/McClaw/Views/Chat/MessageBubbleView.swift` |
| Input | `McClaw/Sources/McClaw/Views/Chat/ChatInputBar.swift` |
| Menu | `McClaw/Sources/McClaw/Views/Menu/MenuContentView.swift` |
| Settings | `McClaw/Sources/McClaw/Views/Settings/SettingsWindow.swift` |
| Onboarding | `McClaw/Sources/McClaw/Views/Onboarding/OnboardingWizard.swift` |
| Cron Models | `McClaw/Sources/McClaw/Models/Cron/CronModels.swift` |
| Cron Store | `McClaw/Sources/McClaw/Services/Cron/CronJobsStore.swift` |
| Cron Editor | `McClaw/Sources/McClaw/Views/Settings/CronJobEditor.swift` |
| Cron Settings | `McClaw/Sources/McClaw/Views/Settings/CronSettings.swift` |
| Webhooks | `McClaw/Sources/McClaw/Services/Cron/WebhookReceiver.swift` |
| MCP Models | `McClaw/Sources/McClaw/Models/MCP/MCPModels.swift` |
| MCP Parser | `McClaw/Sources/McClawKit/MCPParser.swift` |
| MCP Manager | `McClaw/Sources/McClaw/Services/MCP/MCPConfigManager.swift` |
| MCP Settings | `McClaw/Sources/McClaw/Views/Settings/MCPSettingsTab.swift` |
| MCP Editor | `McClaw/Sources/McClaw/Views/Settings/MCPServerEditor.swift` |
| Channel Models | `McClaw/Sources/McClaw/Models/Channel/ChannelModels.swift` |
| Config Schema | `McClaw/Sources/McClaw/Models/Channel/ConfigSchemaSupport.swift` |
| Channels Store | `McClaw/Sources/McClaw/Services/Channels/ChannelsStore.swift` |
| Channel Config UI | `McClaw/Sources/McClaw/Views/Settings/ChannelConfigForm.swift` |
| Skill Models | `McClaw/Sources/McClaw/Models/Skills/SkillModels.swift` |
| Skills Store | `McClaw/Sources/McClaw/Services/Skills/SkillsStore.swift` |
| Skills Settings | `McClaw/Sources/McClaw/Views/Settings/SkillsSettings.swift` |
| Channels/Plugins Kit | `McClaw/Sources/McClawKit/ChannelsPluginsKit.swift` |
| Voice Mode Service | `McClaw/Sources/McClaw/Services/Voice/VoiceModeService.swift` |
| Speech Recognition | `McClaw/Sources/McClaw/Services/Voice/SpeechRecognitionService.swift` |
| Speech Synthesis | `McClaw/Sources/McClaw/Services/Voice/SpeechSynthesisService.swift` |
| Push-to-Talk | `McClaw/Sources/McClaw/Services/Voice/PushToTalkService.swift` |
| Voice Wake | `McClaw/Sources/McClaw/Services/Voice/VoiceWakeRuntime.swift` |
| Voice Overlay | `McClaw/Sources/McClaw/Views/Voice/VoiceOverlayView.swift` |
| Voice Settings | `McClaw/Sources/McClaw/Views/Settings/VoiceSettings.swift` |
| VoiceKit | `McClaw/Sources/McClawKit/VoiceKit.swift` |
| Canvas Manager | `McClaw/Sources/McClaw/Services/Canvas/CanvasManager.swift` |
| Canvas Window | `McClaw/Sources/McClaw/Services/Canvas/CanvasWindowController.swift` |
| Canvas A2UI | `McClaw/Sources/McClaw/Services/Canvas/CanvasA2UIActionMessageHandler.swift` |
| Canvas File Watcher | `McClaw/Sources/McClaw/Services/Canvas/CanvasFileWatcher.swift` |
| Canvas View | `McClaw/Sources/McClaw/Views/Canvas/CanvasView.swift` |
| Node Mode | `McClaw/Sources/McClaw/Services/Node/NodeMode.swift` |
| Screen Record | `McClaw/Sources/McClaw/Services/Node/ScreenRecordService.swift` |
| Camera Capture | `McClaw/Sources/McClaw/Services/Node/CameraCaptureService.swift` |
| Node Location | `McClaw/Sources/McClaw/Services/Node/NodeLocationService.swift` |
| CanvasNodeKit | `McClaw/Sources/McClawKit/CanvasNodeKit.swift` |
| IPC Connection | `McClaw/Sources/McClawIPC/McClawIPC.swift` |
| Remote Port Tunnel | `McClaw/Sources/McClaw/Services/Remote/RemotePortTunnel.swift` |
| Remote Tunnel Manager | `McClaw/Sources/McClaw/Services/Remote/RemoteTunnelManager.swift` |
| Connection Coordinator | `McClaw/Sources/McClaw/Services/Remote/ConnectionModeCoordinator.swift` |
| Remote Settings | `McClaw/Sources/McClaw/Views/Settings/RemoteSettingsTab.swift` |
| RemoteKit | `McClaw/Sources/McClawKit/RemoteKit.swift` |
| Updater | `McClaw/Sources/McClaw/Services/Updater/UpdaterService.swift` |
| Deep Links | `McClaw/Sources/McClaw/App/DeepLinks.swift` |
| Session Store | `McClaw/Sources/McClaw/Services/Sessions/SessionStore.swift` |
| Usage Tracker | `McClaw/Sources/McClaw/Services/Usage/UsageTracker.swift` |
| Health Store | `McClaw/Sources/McClaw/Services/Health/HealthStore.swift` |
| File Log | `McClaw/Sources/McClaw/Infrastructure/Logging/DiagnosticsFileLog.swift` |
| Logger Config | `McClaw/Sources/McClaw/Infrastructure/Logging/McClawLogger.swift` |
| Build Script | `scripts/build-app.sh` |
| Info.plist | `Info.plist` |
| Package | `McClaw/Package.swift` |
| Docs | `docs/McClaw/00-INDICE.md` (índice de 8 docs) |

---

## Sprint 11: Arquitectura Core de Conectores ✅ COMPLETADO

> **Objetivo**: Modelos, store, keychain, registry, protocolo, settings tab. Sin llamadas API reales.

### 11.1 ConnectorModels.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Models/Connectors/ConnectorModels.swift`
- **Cambio**: ConnectorCategory, ConnectorAuthType, OAuthConfig, ConnectorDefinition, ConnectorInstance, ConnectorCredentials, ConnectorActionResult, ConnectorActionDef, ConnectorActionParam, ConnectorBinding, ConnectorStatus

### 11.2 KeychainService.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/Auth/KeychainService.swift`
- **Cambio**: Actor para CRUD de credenciales via Security framework. Access control `.whenUnlockedThisDeviceOnly`

### 11.3 ConnectorProtocol.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorProtocol.swift`
- **Cambio**: Protocolo ConnectorProvider + ConnectorProviderError enum

### 11.4 ConnectorRegistry.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorRegistry.swift`
- **Cambio**: Registro estático de las 23 definiciones con sus acciones por categoría

### 11.5 ConnectorStore.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorStore.swift`
- **Cambio**: @MainActor @Observable singleton. CRUD instancias, persistencia en ~/.mcclaw/connectors.json

### 11.6 ConnectorsSettingsTab.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Settings/ConnectorsSettingsTab.swift`
- **Cambio**: Lista agrupada por categoría, badges de estado, add/connect/disconnect buttons

### 11.7 SettingsWindow.swift ✅
- **Cambio**: Añadido case .connectors con icono "link" y ConnectorsSettingsTab()

### 11.8 ConfigStore.swift ✅
- **Cambio**: Directorio "connectors" en ensureDirectories()

### 11.9 ConnectorsKit.swift ✅
- **Archivo**: `McClaw/Sources/McClawKit/ConnectorsKit.swift`
- **Cambio**: Parsing @fetch, header building, result formatting, token validation, OAuth URL building, PKCE, sanitización

### 11.10 Tests ✅
- 26 tests en ConnectorsKitTests: fetch parsing, extract, header, format, token, OAuth URL, sanitize

---

## Sprint 12: Conectores Google (OAuth 2.0) ✅ COMPLETADO

> **Objetivo**: Flujo OAuth 2.0 completo + 5 conectores Google operativos.

### 12.1 OAuthService.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/Auth/OAuthService.swift`
- **Cambio**: ASWebAuthenticationSession + PKCE. startOAuthFlow, exchangeCodeForTokens, refreshAccessToken, state validation CSRF

### 12.2 GoogleProviders.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/Providers/GoogleProviders.swift`
- **Cambio**: GoogleAPIClient helper + GmailProvider, GoogleCalendarProvider, GoogleDriveProvider, GoogleSheetsProvider, GoogleContactsProvider

### 12.3 ConnectorExecutor.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorExecutor.swift`
- **Cambio**: Actor dispatch: credential loading, token refresh, provider dispatch. Google + Dev providers registrados

### 12.4 ConnectorDetailView.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Settings/ConnectorDetailView.swift`
- **Cambio**: OAuth sign-in, API Key, Bot Token, Domain+Key (Jira), dual auth (GitHub/GitLab), test connection, disconnect

### 12.5 Tests ✅
- PKCE (9 tests) + Google API response parsing (15 tests) en ConnectorsKitTests

---

## Sprint 13: Conectores de Desarrollo ✅ COMPLETADO

> **Objetivo**: GitHub, GitLab, Linear, Jira, Notion. Mix de OAuth y PAT.

### 13.1 DevProviders.swift ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/Connectors/Providers/DevProviders.swift`
- **Cambio**: RESTAPIClient helper + GitHubProvider, GitLabProvider, LinearProvider (GraphQL), JiraProvider, NotionProvider

### 13.2 ConnectorDetailView.swift (ampliado) ✅
- **Cambio**: Dual auth tabs (OAuth + PAT) para GitHub/GitLab, domain field para Jira, token format hints

### 13.3 Tests ✅
- GitHub (6), GitLab (3), Linear (4), Jira (3), Notion (4), PAT validation (7) = 27 tests nuevos

---

## Sprint 14: Conectores de Comunicación ✅ COMPLETADO

> **Objetivo**: Slack, Discord, Telegram via Bot Tokens. 281 tests totales.

### 14.1 CommunicationProviders.swift ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Connectors/Providers/CommunicationProviders.swift`
- **Cambio**: Implementar 3 providers
  - **SlackProvider** (Bot Token xoxb-): list_channels (conversations.list), read_channel (conversations.history), search_messages (search.messages). Base URL `https://slack.com`. Auth `Bearer xoxb-{token}`. testConnection via auth.test
  - **DiscordProvider** (Bot Token): list_guilds (users/@me/guilds), list_channels (guilds/{id}/channels), read_channel (channels/{id}/messages). Base URL `https://discord.com`. Auth `Bot {token}`. API v10. testConnection via users/@me
  - **TelegramProvider** (Bot Token de BotFather): get_updates (/bot{token}/getUpdates), get_me (/bot{token}/getMe). Base URL `https://api.telegram.org`. Sin auth header (token en URL). testConnection via getMe

### 14.2 ConnectorExecutor.swift (registrar providers) ✅
- **Cambio**: Registrar SlackProvider, DiscordProvider, TelegramProvider en init()

### 14.3 ConnectorsKit.swift (formatters + validators) ✅
- **Cambio**: Añadir formatters para Slack (channels, messages, search results), Discord (guilds, channels, messages), Telegram (updates, bot info)
- **Token validators**: isValidSlackBotToken (xoxb- prefix, 30+ chars), isValidDiscordBotToken (3 dot-separated segments, 50+ chars), isValidTelegramBotToken (digits:hash, hash 30+ chars)

### 14.4 ConnectorsSettingsTab.swift (nota Connectors vs Channels) ✅
- **Cambio**: GroupBox informativo explicando la diferencia: "Connectors READ data, Channels SEND messages. They are complementary"

### 14.5 ConnectorDetailView.swift (bot token hints) ✅
- **Cambio**: Hints por provider: Slack "xoxb-...", Discord "Bot token from Developer Portal", Telegram "123456789:ABC... from @BotFather"

### 14.6 Tests ✅
- Slack parsing (7 tests): channels, private channels, messages, subtype messages, search results, empty states
- Discord parsing (5 tests): guilds, channels (text+voice types), messages, empty states
- Telegram parsing (4 tests): text updates, callback queries, bot info, empty states
- Bot token validation (7 tests): Slack valid/invalid prefix/short, Discord valid/no dots/short, Telegram valid/no colon/non-numeric ID/short hash

### Verificación Sprint 14 ✅
```bash
cd McClaw && swift build   # ✅ OK
swift test                  # ✅ 281/281 passing
```

---

## Sprint 15: Conectores Microsoft (Graph API) ✅ COMPLETADO

**Objetivo**: Outlook Mail, Outlook Calendar, OneDrive, Microsoft To Do via Microsoft Graph API v1.0.

### 15.1 MicrosoftProviders.swift ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Connectors/Providers/MicrosoftProviders.swift`
- **Cambio**: 4 providers + helper compartido `MicrosoftGraphClient`
  - **MicrosoftGraphClient**: HTTP client común con Bearer auth, manejo de errores Graph (401, 403, 429), base URL `https://graph.microsoft.com/v1.0/`
  - **OutlookMailProvider** (`microsoft.outlook`):
    - `list_messages(folder:, top:)` → GET /me/messages con $orderby, $select
    - `read_message(messageId:)` → GET /me/messages/{id} con body, recipients
    - `search(query:)` → GET /me/messages?$search="{query}"
    - `list_folders()` → GET /me/mailFolders con displayName, counts
  - **OutlookCalendarProvider** (`microsoft.calendar`):
    - `list_events(startDateTime:, endDateTime:)` → GET /me/calendarview con $orderby, $select
    - `get_event(eventId:)` → GET /me/events/{id} con body, attendees
    - `list_calendars()` → GET /me/calendars
  - **OneDriveProvider** (`microsoft.onedrive`):
    - `list_recent()` → GET /me/drive/recent
    - `search(query:)` → GET /me/drive/root/search(q='{query}')
    - `get_item(itemId:)` → GET /me/drive/items/{id}
  - **MicrosoftToDoProvider** (`microsoft.todo`):
    - `list_tasks(listId:)` → GET /me/todo/lists/{id}/tasks
    - `list_lists()` → GET /me/todo/lists
    - `get_task(listId:, taskId:)` → GET /me/todo/lists/{listId}/tasks/{taskId}
  - Todos con `refreshTokenIfNeeded` usando Azure AD OAuth 2.0 endpoints

### 15.2 microsoftOAuthConfig() helper ✅
- **Archivo**: `MicrosoftProviders.swift`
- **Cambio**: Helper `microsoftOAuthConfig(scopes:)` construye OAuthConfig con:
  - Auth URL: `https://login.microsoftonline.com/common/oauth2/v2.0/authorize`
  - Token URL: `https://login.microsoftonline.com/common/oauth2/v2.0/token`
  - Scopes: dinámicos + `offline_access` (para refresh_token)
  - PKCE habilitado

### 15.3 ConnectorsKit.swift — Microsoft Graph formatters ✅
- **Archivo modificado**: `McClaw/Sources/McClawKit/ConnectorsKit.swift`
- **Funciones añadidas**:
  - `parseMicrosoftGraphError(statusCode:body:)` — parseo de errores Graph API
  - `formatOutlookMessages(_:)` — mensajes con from/subject/preview/isRead
  - `formatOutlookFolders(_:)` — carpetas con displayName/totalItems/unread
  - `formatOutlookEvents(_:)` — eventos con subject/start/end/location/organizer/isAllDay
  - `formatOutlookCalendars(_:)` — calendarios con name/color/isDefault
  - `formatOneDriveItems(_:)` — archivos/carpetas con name/size/mimeType/lastModified
  - `formatOneDriveItemDetail(_:)` — detalle completo con webUrl/createdBy
  - `formatFileSize(_:)` — helper para tamaños legibles (B/KB/MB/GB)
  - `formatToDoLists(_:)` — listas con displayName/isOwner/wellknownListName
  - `formatToDoTasks(_:)` — tareas con title/status/importance/dueDate
  - `formatToDoTaskDetail(_:)` — detalle con body/completedDateTime

### 15.4 ConnectorExecutor.swift — registro de providers ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorExecutor.swift`
- **Cambio**: Registrados 4 providers Microsoft en init(): OutlookMailProvider, OutlookCalendarProvider, OneDriveProvider, MicrosoftToDoProvider

### 15.5 Tests ✅
- **Archivo modificado**: `McClaw/Tests/McClawKitTests/ConnectorsKitTests.swift`
- **21 tests nuevos**:
  - `MicrosoftGraphErrorTests` (2): parsing errores Graph, fallback
  - `OutlookMailParsingTests` (4): mensajes, read/unread, empty, folders
  - `OutlookCalendarParsingTests` (4): eventos, all-day, empty, calendars
  - `OneDriveParsingTests` (4): files, folders, empty, item detail
  - `ToDosParsingTests` (5): lists default/shared, tasks pending/completed, empty, detail
  - Total tests proyecto: **302/302 passing**

### Verificación Sprint 15 ✅
```bash
cd McClaw && swift build   # ✅ OK
swift test                  # ✅ 302/302 passing
```

---

## Sprint 16: Conectores Productividad + Utilidades ✅ COMPLETADO

**Objetivo**: Todoist, Trello, Airtable, Dropbox, Weather, RSS, Webhook. 346 tests totales.

### 16.1 ProductivityProviders.swift ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Connectors/Providers/ProductivityProviders.swift`
- **Cambio**: 4 providers de productividad
  - **TodoistProvider** (API Token): list_tasks (con projectId/filter opcionales), list_projects, get_task. Base URL `https://api.todoist.com`. Auth `Bearer {token}`
  - **TrelloProvider** (API Key + Token): list_boards, list_cards (por listId), list_lists (por boardId). Base URL `https://api.trello.com`. Auth via query params key + token
  - **AirtableProvider** (PAT): list_records (baseId + tableId), list_bases, get_record. Base URL `https://api.airtable.com`. Auth `Bearer {pat}`
  - **DropboxProvider** (OAuth): list_files (POST /2/files/list_folder), search (POST /2/files/search_v2), get_metadata (POST /2/files/get_metadata). Base URL `https://api.dropboxapi.com`. Auth `Bearer {token}`. Con refreshTokenIfNeeded via dropboxOAuthConfig()

### 16.2 UtilityProviders.swift ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Connectors/Providers/UtilityProviders.swift`
- **Cambio**: 3 providers de utilidades
  - **WeatherProvider** (API Key OpenWeatherMap): current (/data/2.5/weather), forecast (/data/2.5/forecast), alerts (/data/3.0/onecall). Auth via query param appid
  - **RSSProvider** (sin auth): fetch_feed con XMLParser de Foundation. RSSXMLParser soporta RSS 2.0 y Atom (detecta `<feed>` vs `<item>`). Extrae title, link, description, pubDate, author. maxEntries configurable. HTML stripping en descriptions
  - **WebhookProvider** (sin auth): call con URL, method (GET/POST only), body y headers custom opcionales. Retorna HTTP status + response body

### 16.3 ConnectorsKit.swift — Formatters ✅
- **Archivo modificado**: `McClaw/Sources/McClawKit/ConnectorsKit.swift`
- **Funciones añadidas** (20 nuevas):
  - Todoist: `formatTodoistTasks`, `formatTodoistProjects`, `formatTodoistTaskDetail`
  - Trello: `formatTrelloBoards`, `formatTrelloCards`, `formatTrelloLists`
  - Airtable: `formatAirtableRecords`, `formatAirtableBases`, `formatAirtableRecordDetail`
  - Dropbox: `formatDropboxEntries`, `formatDropboxSearchResults`, `formatDropboxEntryDetail`
  - Weather: `formatCurrentWeather`, `formatWeatherForecast`, `formatWeatherAlerts`, `formatUnixTimestamp`
  - RSS: `formatRSSEntries`
  - Webhook: `formatWebhookResponse`

### 16.4 ConnectorExecutor.swift — registro de providers ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorExecutor.swift`
- **Cambio**: Registrados 7 providers nuevos en init(): TodoistProvider, TrelloProvider, AirtableProvider, DropboxProvider, WeatherProvider, RSSProvider, WebhookProvider

### 16.5 Tests ✅
- **Archivo modificado**: `McClaw/Tests/McClawKitTests/ConnectorsKitTests.swift`
- **44 tests nuevos**:
  - `TodoistParsingTests` (4): tasks con prioridades/labels/due, empty, projects con favoritos, task detail
  - `TrelloParsingTests` (4): boards open/closed, cards con labels/due, lists con archived, empty
  - `AirtableParsingTests` (4): records con fields, bases, record detail con createdTime, empty
  - `DropboxParsingTests` (4): entries files/folders con sizes, entry detail, empty, search results
  - `WeatherParsingTests` (5): current weather completo, forecast con city, alerts con timestamps, alerts empty, alerts missing key
  - `RSSParsingTests` (3): entries con author/link/date, empty, HTML stripping en descriptions
  - `WebhookParsingTests` (3): success 200, error 500, empty body 204
  - Total tests proyecto: **346/346 passing**

### Verificación Sprint 16 ✅
```bash
cd McClaw && swift build   # ✅ OK
swift test                  # ✅ 346/346 passing
```

---

## Sprint 17: Motor de Prompt Enrichment ✅ COMPLETADO

> **Objetivo**: Sprint clave — conecta los conectores con el chat y el cron. @fetch end-to-end.

### 17.1 PromptEnrichmentService.swift ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Services/Connectors/PromptEnrichmentService.swift`
- **Cambio**: Servicio coordinador @MainActor @Observable singleton
  - `buildConnectorsHeader()` — delega a ConnectorStore para inyectar cabecera en prompts
  - `parseAndExecuteFetch(response:round:)` — detecta @fetch en respuestas IA, ejecuta via ConnectorExecutor, retorna resultado formateado
  - `executeSlashFetch(_:)` — ejecuta /fetch manual del usuario, retorna mensaje formateado para chat
  - `enrichForCronJob(message:bindings:)` — enriquece prompts de cron con datos reales de bindings
  - Resolución de instancias por nombre, definitionId o sufijo (gmail → google.gmail)
  - Errores incluidos como texto (no falla el job completo)
  - Estados observables: `isFetching`, `fetchStatusMessage`

### 17.2 ChatViewModel.swift (modificar) ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Views/Chat/ChatViewModel.swift`
- **Cambio**: Integración completa de enrichment en flujo de chat
  - Cabecera de conectores prepended al primer mensaje de cada turno
  - Nuevo método `streamAndEnrich()` — loop recursivo de @fetch (max 3 rounds)
  - Tras streaming: detecta @fetch en respuesta IA → ejecuta → re-envía resultado → espera respuesta final
  - Counter anti-loop con ConnectorsKit.maxFetchRoundsPerTurn
  - Flag `headerInjectedThisTurn` para evitar duplicados

### 17.3 ChatViewModel.swift — /fetch manual ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Views/Chat/ChatViewModel.swift`
- **Cambio**: Nuevo slash command `/fetch connector.action param=value`
  - Ejecuta via PromptEnrichmentService.executeSlashFetch()
  - Resultado mostrado como mensaje de sistema en chat
  - Añadido a /help

### 17.4 CronJobsStore.swift (modificar) ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Services/Cron/CronJobsStore.swift`
- **Cambio**: Enrichment antes de ejecutar cron jobs con bindings
  - `runJob()` detecta connectorBindings en payload agentTurn
  - Si tiene bindings: enriquece via PromptEnrichmentService.enrichForCronJob()
  - Envía mensaje enriquecido como messageOverride a Gateway

### 17.5 CronModels.swift (modificar) ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Models/Cron/CronModels.swift`
- **Cambio**: Añadido campo `connectorBindings: [ConnectorBinding]?` a CronPayload.agentTurn
  - Encoder/decoder actualizados
  - Todos los pattern matches actualizados (CronJobEditor, CronSettings, CronJobsStore)

### 17.6 CronJobEditor.swift (modificar) ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Views/Settings/CronJobEditor.swift`
- **Cambio**: Nuevo GroupBox "Data Sources" en editor de cron jobs
  - Visible solo si hay conectores activos y payload es agentTurn
  - Lista dinámica de ConnectorBindingRow (add/remove)
  - Bindings guardados en CronPayload al save
  - Hidratación desde job existente

### 17.7 ConnectorActionPicker.swift ✅
- **Archivo nuevo**: `McClaw/Sources/McClaw/Views/Settings/ConnectorActionPicker.swift`
- **Cambio**: Componente reutilizable de selección de connector + action + params
  - Picker de instancia conectada → picker de acción → campos de parámetros
  - Soporte para enum values (dropdowns) y campos de texto
  - Max result length configurable
  - Preview de la sintaxis @fetch generada
  - ConnectorBindingRow wrapper para uso en CronJobEditor

### 17.8 ConnectorsKit.swift (ampliar) ✅
- **Archivo modificado**: `McClaw/Sources/McClawKit/ConnectorsKit.swift`
- **Nuevas funciones**:
  - `detectFetchInResponse(_:)` — alias semántico para extractFetchCommands
  - `parseSlashFetch(_:)` — parser de /fetch command (formato con espacios)
  - `buildFetchResultMessage(connector:action:data:truncated:)` — formatea resultado para chat
  - `maxFetchRoundsPerTurn` (3) — constante anti-loop
  - `defaultMaxResultLength` (4000) — constante de truncación

### 17.9 Tests ✅
- **Archivo modificado**: `McClaw/Tests/McClawKitTests/ConnectorsKitTests.swift`
- **13 tests nuevos**:
  - `DetectFetchTests` (2): detecta commands en respuesta, texto limpio
  - `SlashFetchTests` (5): simple, con params, empty, sin dot, otro comando
  - `FetchResultTests` (2): build result message, con truncación
  - `ConstantsTests` (2): maxFetchRoundsPerTurn, defaultMaxResultLength
  - `EnrichedPromptMultipleTests` (2): múltiples resultados, errores graceful
  - Total tests proyecto: **359/359 passing**

### 17.10 GatewayConnectionService.swift (modificar) ✅
- **Archivo modificado**: `McClaw/Sources/McClaw/Services/Gateway/GatewayConnectionService.swift`
- **Cambio**: `cronRun()` ahora acepta `messageOverride: String?` opcional para enviar prompts enriquecidos

### Verificación Sprint 17 ✅
```bash
cd McClaw && swift build   # ✅ OK
swift test                  # ✅ 359/359 passing
```

---

## Sprint 18: Conector MCP Content Manager (WordPress/WooCommerce) ✅ COMPLETADO

> **Objetivo**: Bridge completo WordPress ↔ McClaw via MCP Content Manager. 13 sub-conectores, ~278 abilities, zero-latency discovery.

### Tareas

- ✅ **18.1** MCMAbilitiesCatalog (McClawKit) — catálogo completo de ~278 abilities con 13 sub-conectores
- ✅ **18.2** ConnectorRegistry mapping — 13 ConnectorDefinition wp.* generados desde el catálogo
- ✅ **18.3** MCMAbilitiesCatalogTests — 17 tests de validación del catálogo
- ✅ **18.4** WordPressProvider.swift — bridge MCP Content Manager via stdio/HTTP JSON-RPC
- ✅ **18.4b** Registro en ConnectorExecutor para los 13 sub-conectores wp.*
- ✅ **18.5** UI WordPress: detección automática de MCP installations, botón Connect via MCP, estado en ConnectorsSettingsTab
- ✅ **18.6** Tests adicionales: 6 tests WordPressProvider (catálogo, sub-connector resolution, param validation)
- ✅ **18.7** Helper `MCMAbilitiesCatalog.subConnector(forAbility:)` para resolución ability→sub-connector

### Arquitectura

```
MCMAbilitiesCatalog (McClawKit, pure logic)
  ├── 13 MCMSubConnector (wp.content, wp.media, wp.woocommerce, etc.)
  ├── ~278 MCMAbility (id, name, description, params, requiresConfirmation)
  └── Zero-latency: validación local sin red

WordPressProvider (ConnectorProvider)
  ├── handles() → todos los 13 wp.* sub-connectors
  ├── execute() → validación local + JSON-RPC via MCP server
  │   ├── stdio: Process + stdin/stdout (initialize + tools/call)
  │   └── HTTP: URLSession POST (tools/call)
  ├── testConnection() → mcm/site-health
  └── detectInstallations() → escanea MCPConfigManager

ConnectorExecutor
  └── Un solo WordPressProvider registrado para las 13 definitionIds
```

### Archivos creados/modificados
- `Sources/McClawKit/MCMAbilitiesCatalog.swift` — +`subConnector(forAbility:)` helper
- `Sources/McClaw/Services/Connectors/Providers/WordPressProvider.swift` — MCP bridge provider + MCPWordPressSite model
- `Sources/McClaw/Services/Connectors/ConnectorExecutor.swift` — registro wp.* providers
- `Sources/McClaw/Views/Settings/ConnectorsSettingsTab.swift` — detección MCP y botón mejorado
- `Sources/McClaw/Views/Settings/ConnectorDetailView.swift` — mcpBridgeView con detección de sites
- `Tests/McClawKitTests/MCMAbilitiesCatalogTests.swift` — 6 tests WordPressProvider

### Verificación Sprint 18 ✅
```bash
cd McClaw && swift build   # ✅ OK
swift test                  # ✅ 365/365 passing
```

---

## Sprint 19: Telegram Native Channel ✅ COMPLETADO

### Objetivo
Implementar un canal nativo de Telegram que corre directamente desde McClaw sin Gateway. Bot que escucha mensajes via long polling y responde usando el CLI de IA activo.

### 19.1 TelegramKit (McClawKit, pure logic) ✅
- Modelos: `User`, `Chat`, `Message`, `Update`, `BotInfo`, `APIResponse<T>`
- URL building: `getUpdatesURL`, `sendMessageURL`, `getMeURL`, `apiURL`
- Parsing: `parseUpdates`, `parseBotInfo`, `parseSentMessage`
- Helpers: `nextOffset`, `filterTextMessages`, `truncateForTelegram`, `escapeMarkdownV2`, `isValidBotToken`
- Request body building: `sendMessageBody` (JSON con chat_id, text, parse_mode, reply_to_message_id)

### 19.2 NativeChannel Protocol + TelegramNativeService ✅
- **NativeChannelProtocol**: `start(config:)`, `stop()`, `setOnMessage()`, state/stats/botDisplayName
- **NativeChannelModels**: `NativeChannelState`, `NativeChannelConfig`, `NativeChannelMessage`, `NativeChannelStats`, `NativeChannelDefinition`
- **TelegramNativeService** actor:
  - Long-polling loop con `getUpdates` (timeout 30s)
  - Offset tracking para deduplicación de mensajes
  - Rate limiting handling (429 + retry_after)
  - Conflict detection (409 — otra instancia polling)
  - Reconnection con backoff (max 10 errores consecutivos)
  - Markdown fallback (si falla envío con Markdown, reintenta plain text)
  - Carga credenciales del ConnectorProvider existente (`comm.telegram`) via KeychainService

### 19.3 NativeChannelsManager (coordinator) ✅
- Singleton `@MainActor @Observable`
- Gestiona lifecycle de todos los native channels
- Estado observable: `telegramState`, `telegramStats`, `telegramBotName`
- Persistencia de configs en `~/.mcclaw/native-channels.json`
- Se inicia desde `AppDelegate` al arrancar la app

### 19.4 Message Routing (chat integration) ✅
- Mensajes entrantes → CLIBridge con el provider de IA activo
- System prompt con contexto del canal y sender
- Soporte de `allowedChatIds` para restringir acceso
- Respuesta enviada via `sendMessage` con reply_to_message_id
- Configurable: `respondWithAI`, `aiProviderId`, `systemPrompt`

### 19.5 UI: NativeChannelsSettingsTab ✅
- Integrado dentro de ChannelsSettingsTab (sección "Native Channels" arriba, "Gateway Channels" abajo)
- Card por canal con: estado (badge coloreado), nombre del bot, stats en tiempo real
- Botones Start/Stop + gear para configuración
- Sheet de configuración: enabled, auto-reconnect, AI provider, system prompt, allowed chat IDs
- Stats: messages received/sent, uptime, last message time

### 19.6 Tests ✅
- 48 tests nuevos en `TelegramKitTests.swift`
- Suites: URLBuilding, Parsing, Offset, Filtering, Formatting, TokenValidation, RequestBody, Models

### Arquitectura

```
TelegramKit (McClawKit, pure logic, testable)
  ├── Models: User, Chat, Message, Update, BotInfo, APIResponse<T>
  ├── URL Building: getUpdatesURL, sendMessageURL, getMeURL
  ├── Parsing: parseUpdates, parseBotInfo, parseSentMessage
  └── Helpers: nextOffset, filterTextMessages, truncateForTelegram, isValidBotToken

NativeChannelProtocol (actor protocol)
  └── start/stop/setOnMessage/state/stats

TelegramNativeService (actor, NativeChannel)
  ├── Long-polling loop (getUpdates + offset tracking)
  ├── Rate limiting + conflict detection + reconnection
  ├── sendMessage with Markdown fallback
  └── Credential loading via KeychainService (reuses comm.telegram)

NativeChannelsManager (@MainActor @Observable singleton)
  ├── Lifecycle: start/stop channels
  ├── Message routing: incoming → CLIBridge → sendMessage
  ├── Config persistence: ~/.mcclaw/native-channels.json
  └── Observable state for UI

NativeChannelsSettingsTab (SwiftUI)
  ├── Channel cards with status badge + stats
  ├── Start/Stop controls
  └── Config sheet (AI provider, system prompt, allowed chats)
```

### Archivos creados/modificados
- `Sources/McClawKit/TelegramKit.swift` — Pure logic: models, URL building, parsing, helpers
- `Sources/McClaw/Models/NativeChannel/NativeChannelModels.swift` — State, config, message, stats models
- `Sources/McClaw/Services/NativeChannels/NativeChannelProtocol.swift` — Actor protocol
- `Sources/McClaw/Services/NativeChannels/TelegramNativeService.swift` — Telegram long-polling service
- `Sources/McClaw/Services/NativeChannels/NativeChannelsManager.swift` — Coordinator singleton
- `Sources/McClaw/Views/Settings/NativeChannelsSettingsTab.swift` — Settings UI + config sheet
- `Sources/McClaw/Views/Settings/SettingsWindow.swift` — Integrated native channels into ChannelsSettingsTab
- `Sources/McClaw/App/AppDelegate.swift` — Added NativeChannelsManager.shared.start()
- `Tests/McClawKitTests/TelegramKitTests.swift` — 48 tests

### Verificación Sprint 19 ✅
```bash
cd McClaw && swift build   # ✅ OK
swift test                  # ✅ 413/413 passing (48 new)
```

---

## Sprint 20: Slack Native Channel ✅ COMPLETADO

### Objetivo
Phase 2 de Native Channels: Slack via Socket Mode (WebSocket directo, sin servidor webhook).

### 20.1 SlackKit (Pure Logic) ✅
- **Archivo**: `McClaw/Sources/McClawKit/SlackKit.swift`
- **Modelos**: `SocketEnvelope`, `Payload`, `SlackEvent`, `BotIdentity`
- **Envelope types**: `typeHello`, `typeEventsApi`, `typeSlashCommands`, `typeInteractive`, `typeDisconnect`
- **Parsing**: `parseEnvelope()`, `parseBotIdentity()`, `parseWebSocketURL()`
- **URL Building**: `webAPIURL(method:)`, `connectURL()`
- **Request Bodies**: `postMessageBody(channel:text:threadTs:)`, `acknowledgeBody(envelopeId:)`
- **Event Logic**: `shouldProcess(event:)`, `extractText(from:botUserId:)` (strips `<@UBOTID>` mentions)
- **Formatting**: `truncateForSlack(_:maxLength:)`, `escapeSlackMrkdwn(_:)`
- **Validation**: `isValidBotToken(_:)` (xoxb- prefix, >20 chars), `isValidAppToken(_:)` (xapp- prefix, >20 chars)
- **SlackEvent computed**: `isUserMessage`, `isDirectMessage`, `isAppMention`

### 20.2 SlackNativeService (Socket Mode WebSocket) ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/NativeChannels/SlackNativeService.swift`
- **Actor** implementando `NativeChannel` protocol
- **Dual tokens**: Bot Token (xoxb- del ConnectorProvider existente via Keychain) + App-Level Token (xapp- del config)
- **Flujo de conexión**:
  1. `auth.test` con bot token → obtiene `BotIdentity`
  2. `apps.connections.open` POST con app-level token → obtiene WebSocket URL
  3. Conecta WebSocket → receive loop
  4. Envelope handling: hello (log), disconnect (reconnect), events_api (process)
  5. Ack dentro de 3 segundos (requisito Slack)
- **Respuestas**: `chat.postMessage` Web API con bot token, threaded replies via `thread_ts`
- **Reconnection**: Max 10 errores consecutivos, 5s delay entre reconexiones
- **Filtering**: DM-only mode, allowed channel IDs, bot message filtering

### 20.3 NativeChannelModels Actualizados ✅
- **Archivo**: `McClaw/Sources/McClaw/Models/NativeChannel/NativeChannelModels.swift`
- **NativeChannelConfig**: Añadidos `appLevelToken: String?`, `allowedChannelIds: [String]?`, `dmOnly: Bool?`
- **NativeChannelMessage**: Añadidos `platformChannelId: String?`, `platformUserId: String?`, `threadId: String?`

### 20.4 NativeChannelsManager Integración ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/NativeChannels/NativeChannelsManager.swift`
- Añadido `slackState`, `slackStats`, `slackBotName` properties
- Slack channel definition (icon: `number.square`, color: purple)
- `startChannel`/`stopChannel`/`refreshChannelState` manejan `"slack"` case
- `SlackNativeService.shared.stop()` en `stop()`

### 20.5 NativeChannelsSettingsTab UI ✅
- **Archivo**: `McClaw/Sources/McClaw/Views/Settings/NativeChannelsSettingsTab.swift`
- Channel card con status badge para Slack
- Config sheet: App-Level Token (SecureField), DM-only toggle, Allowed Channel IDs
- Stats view: messages received/sent, uptime, last message
- State/error/botName helpers para Slack

### 20.6 SlackKitTests ✅
- **Archivo**: `McClaw/Tests/McClawKitTests/SlackKitTests.swift`
- **39 tests** en 11 suites:
  - `EnvelopeParsing` (5): hello, disconnect, events_api message, app_mention, invalid JSON
  - `BotIdentity` (3): parse auth.test, failed auth, displayName fallback
  - `Acknowledge` (1): build ack body
  - `URLBuilding` (2): web API URL, connect URL
  - `WebSocketURL` (2): parse WSS URL, failed parse
  - `RequestBody` (2): postMessage, postMessage with thread
  - `EventFiltering` (7): user message, app_mention, bot skip, subtype skip, no-user skip, isDM, isNotDM
  - `TextExtraction` (4): strip mention, no mention, empty after strip, nil text
  - `Formatting` (3): truncate, no truncate, escape mrkdwn
  - `TokenValidation` (7): valid/invalid bot tokens, valid/invalid app tokens, empty tokens
  - `Models` (3): isUserMessage, subtype not user, botId not user

### 20.7 Error: SlackNativeError ✅
- **Archivo**: `McClaw/Sources/McClaw/Services/NativeChannels/SlackNativeService.swift`
- `invalidURL`, `invalidResponse`, `noWebSocketURL`, `unauthorized`, `forbidden`, `httpError(Int)`
- Mensajes descriptivos con sugerencias de solución

### Verificación Sprint 20 ✅
```bash
cd McClaw && swift build   # ✅ OK
swift test                  # ✅ 452/452 passing (39 new)
```
