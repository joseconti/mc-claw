# 15 - McClaw Mobile Apps: Arquitectura y Plan de Desarrollo

## Status: Approved Architecture

## Objetivo

Desarrollar dos apps moviles (iOS y Android) que actuen como **mando a distancia** de McClaw. Las apps se comunican con McClaw a traves del Gateway via WebSocket, permitiendo: recibir y enviar comunicaciones, interactuar con los CLIs conectados, explorar repositorios, gestionar la biblioteca multimedia, crear acciones programadas y controlar todas las funciones de McClaw de forma remota.

---

## 1. Modelo de Conexion

### 1.1 Arquitectura General

```
Mobile App (iOS / Android)
    |
    | WebSocket (wss://)
    |
    v
Gateway (Node.js) --- ya existente
    |
    +-- CLIs (Claude, ChatGPT, Gemini, Ollama)
    +-- Channels (Telegram, Slack, Discord, etc.)
    +-- Plugins (npm)
    +-- Cron Jobs
    +-- Sessions
    +-- Canvas
    +-- Node Mode
```

La app movil se conecta al Gateway como un cliente mas, usando el protocolo WebSocket v3 ya existente. No se conecta directamente a McClaw macOS sino al Gateway, que es el hub central. Esto significa que la app funciona tanto si McClaw macOS esta abierto como si no (el Gateway corre como LaunchAgent independiente).

### 1.2 Tipo de Cliente

El sistema de presencia del Gateway usa un campo `type` de tipo String para identificar clientes. Los tipos actuales son: `"control-ui"`, `"node"`, `"cli"`, `"acp"`. Se anade el tipo `"mobile"` para las apps moviles. La app se identifica al conectarse con estos headers:

```
Header: X-Protocol-Version: 3
Header: Authorization: Bearer <token>
Header: X-Client-Type: mobile
Header: X-Device-Id: <uuid-dispositivo>
Header: X-Device-Name: "iPhone de Jose" / "Pixel de Jose"
Header: X-Platform: ios / android
```

### 1.3 Modos de Conexion

**Red local (LAN):**
- Descubrimiento automatico via mDNS/Bonjour (`_mcclaw._tcp`)
- Conexion directa: `ws://<ip-local>:3577/ws`
- Sin necesidad de configuracion manual
- Latencia minima

**Red remota (Internet):**
- Via Tailscale/WireGuard: `wss://gateway.tailnet.ts.net/ws`
- Via reverse proxy con HTTPS: `wss://mcclaw.midominio.com/ws`
- Requiere token de autenticacion
- Push notifications para eventos importantes

**Hibrido (recomendado):**
- Detecta automaticamente si esta en la misma red local
- Si hay LAN, usa conexion directa (mas rapida)
- Si no hay LAN, usa conexion remota
- Transicion transparente al cambiar de red

### 1.4 Device Pairing (Emparejamiento)

El protocolo ya tiene los metodos RPC necesarios:

```
device.pair.list     -> Lista dispositivos emparejados
device.pair.approve  -> Aprobar emparejamiento
device.pair.reject   -> Rechazar emparejamiento
```

**Flujo de emparejamiento:**

1. En McClaw macOS, el usuario abre "Dispositivos" en Settings
2. McClaw genera un QR code que contiene: `{ gatewayUrl, pairingCode, token }`
3. La app movil escanea el QR
4. La app envia solicitud de emparejamiento al Gateway
5. McClaw macOS muestra notificacion: "iPhone de Jose quiere conectarse"
6. El usuario aprueba en McClaw
7. La app recibe token permanente y lo almacena en Keychain/KeyStore
8. Conexiones futuras usan el token guardado (sin repetir el QR)

**Datos del QR (JSON codificado en Base64):**

```json
{
  "v": 1,
  "gateway": "ws://192.168.1.100:3577",
  "gateway_remote": "wss://gateway.tailnet.ts.net",
  "code": "ABCD-1234-EFGH",
  "expires": 1710000000
}
```

---

## 2. Canal Nativo "McClaw Mobile"

### 2.1 Concepto

Ademas de ser un cliente de control, la app movil funciona como un **Native Channel** dentro de McClaw. Esto permite:

- Recibir notificaciones/mensajes que McClaw envia a traves de este canal
- Que los cron jobs entreguen resultados via push notification a la app
- Que otros channels (Telegram, Slack) puedan reenviar mensajes a la app
- Que la IA envie respuestas directamente al movil

### 2.2 Implementacion en McClaw (lado macOS/Gateway)

Nuevo servicio: `MobileNativeService` que implementa `NativeChannel`:

```swift
actor MobileNativeService: NativeChannel {
    let channelId = "mobile"
    var state: NativeChannelState
    var stats: NativeChannelStats
    var connectedDevices: [PairedDevice]

    // Envia mensaje a un dispositivo movil conectado
    func sendOutbound(text: String, recipientId: String) async -> Bool {
        // Si el dispositivo esta conectado via WS -> envia directo
        // Si no esta conectado -> encola + push notification
    }

    // Recibe mensaje de la app movil
    func setOnMessage(_ handler: ...) async { }
}
```

### 2.3 Push Notifications

Cuando la app no esta en primer plano o no tiene conexion WebSocket activa:

**iOS:** APNs (Apple Push Notification service)
**Android:** FCM (Firebase Cloud Messaging)

El Gateway necesita un modulo ligero de push:

```
Gateway
  +-- PushService
       +-- APNsAdapter (p8 key de Apple)
       +-- FCMAdapter (service account de Google)
       +-- NotificationQueue (para cuando el dispositivo vuelve a conectarse)
```

**Tipos de push notification:**

| Tipo | Prioridad | Ejemplo |
|------|-----------|---------|
| `chat.message` | Alta | "Claude ha terminado tu tarea" |
| `cron.completed` | Media | "Job 'backup diario' ejecutado OK" |
| `cron.failed` | Alta | "Job 'deploy' fallo con error..." |
| `channel.alert` | Media | "Nuevo mensaje en Slack #general" |
| `exec.approval` | Critica | "Se requiere aprobacion para ejecutar rm -rf..." |
| `system.health` | Baja | "Gateway reiniciado correctamente" |

---

## 3. Funcionalidades de la App

### 3.1 Dashboard (Pantalla Principal)

Vista rapida del estado de McClaw:

- Estado de conexion al Gateway (conectado/desconectado/degradado)
- CLI activo y modelo seleccionado
- Sesiones activas con preview
- Channels conectados con estado
- Proximos cron jobs
- Actividad reciente del agente

**RPCs utilizados:** `status`, `health`, `sessions.list`, `channels.status`, `cron.list`

### 3.2 Chat Remoto

Enviar y recibir mensajes con los CLIs conectados:

- Lista de sesiones existentes
- Crear nueva sesion
- Enviar mensajes de texto
- Ver respuestas en streaming (via eventos `chat.message`)
- Adjuntar fotos del movil (camara/galeria)
- Abortar generacion en curso
- Cambiar modelo/provider en tiempo real

**RPCs:** `chat.send`, `chat.history`, `chat.abort`, `sessions.list`, `sessions.spawn`, `models.list`
**Eventos:** `chat`, `agent`

### 3.3 Explorador de Repositorios

Usar el CLI para explorar repositorios:

- Navegar estructura de archivos (via `chat.send` con prompts de exploracion)
- Ver contenido de archivos (syntax highlighting)
- Pedir resumen de un repo al CLI
- Ver diff de cambios recientes
- Ejecutar comandos Git (con flujo de aprobacion)

**Nota:** Esto se hace a traves del CLI, no accediendo al filesystem directamente. La app envia prompts al CLI que devuelve la informacion.

### 3.4 Gestion de Cron Jobs

CRUD completo de tareas programadas:

- Listar jobs activos/pausados
- Crear nuevo job (con editor de schedule: cron expression, intervalo, fecha puntual)
- Editar job existente
- Ver historial de ejecuciones (runs)
- Ejecutar job manualmente ("Run Now")
- Activar/desactivar jobs
- Ver logs de ultima ejecucion

**RPCs:** `cron.list`, `cron.add`, `cron.remove`, `cron.update`, `cron.status`, `cron.runs`, `cron.run`
**Eventos:** `cron`

### 3.5 Gestion de Channels

Monitorear y controlar los canales de comunicacion:

- Ver estado de todos los channels (nativos + Gateway)
- Conectar/desconectar channels
- Ver estadisticas (mensajes enviados/recibidos)
- Configurar routing de mensajes

**RPCs:** `channels.status`, `channels.logout`
**Eventos:** `channels`, `channels.status`

### 3.6 Gestion de Plugins

Administrar el ecosistema de plugins:

- Listar plugins instalados con estado
- Instalar nuevos plugins (busqueda en npm)
- Desinstalar plugins
- Activar/desactivar plugins
- Ver configuracion de cada plugin

**RPCs:** `plugins.list`, `plugins.install`, `plugins.uninstall`, `plugins.toggle`
**Eventos:** `plugins`, `plugins.changed`

### 3.7 Biblioteca Multimedia (Canvas)

Interactuar con el sistema Canvas de McClaw:

- Ver snapshots del canvas actual
- Navegar archivos multimedia generados
- Compartir desde el movil hacia el canvas
- Ver historial de canvas por sesion

**RPCs via node.invoke:** `canvas.snapshot`, `canvas.navigate`, `canvas.present`

### 3.8 Aprobaciones de Ejecucion

Resolver solicitudes de aprobacion de comandos desde el movil:

- Recibir push notification cuando se requiere aprobacion
- Ver el comando que se quiere ejecutar
- Aprobar o rechazar con un toque
- Ver historial de aprobaciones

**RPC:** `exec.approval.resolve`
**Eventos:** `exec.approval.requested` (push notification critica)

### 3.9 Control de Nodos

Si hay multiples nodos McClaw conectados (futuro McClaw Win):

- Listar nodos conectados
- Ver capacidades de cada nodo
- Invocar comandos en nodos remotos
- Gestionar emparejamiento de nodos

**RPCs:** `node.list`, `node.describe`, `node.invoke`, `node.pair.approve`, `node.pair.reject`

### 3.10 Configuracion Remota

Ajustar la configuracion de McClaw desde el movil:

- Cambiar CLI activo
- Ajustar configuracion del Gateway
- Gestionar dispositivos emparejados
- Ver logs del sistema

**RPCs:** `config.get`, `config.set`, `config.patch`, `device.pair.list`

---

## 4. Tecnologia

### 4.1 Decision: Kotlin Multiplatform (KMP)

**Por que KMP y no otras opciones:**

| Opcion | Ventaja | Desventaja |
|--------|---------|------------|
| Swift + Kotlin nativos | Maximo rendimiento | Doble desarrollo, doble mantenimiento |
| Flutter | Un solo codebase | Dart no comparte nada con Swift/McClaw |
| React Native | Gran ecosistema | Bridge overhead, no nativo |
| **KMP** | **Logica compartida en Kotlin, UI nativa** | **Curva de aprendizaje iOS** |

**KMP es la eleccion correcta porque:**

1. **Logica compartida:** El protocolo WebSocket, modelos de datos, RPC client, y logica de negocio se escriben una sola vez en Kotlin
2. **UI nativa:** SwiftUI en iOS, Jetpack Compose en Android -- cada plataforma con su look & feel nativo
3. **Cercania al ecosistema McClaw:** Kotlin es familiar para desarrollo Android nativo y la logica compartida reduce bugs de inconsistencia
4. **Rendimiento:** Sin bridge ni overhead de VM en la UI
5. **Futuro McClaw Win:** La capa compartida KMP tambien compila a JVM/Windows

### 4.2 Arquitectura del Proyecto

```
mcclaw-mobile/
|
+-- shared/                          # Kotlin Multiplatform (commonMain)
|   +-- protocol/
|   |   +-- WSClient.kt             # WebSocket client (Ktor)
|   |   +-- WSModels.kt             # WSRequest, WSResponse, WSEvent
|   |   +-- RPCClient.kt            # Request/response con seq matching
|   |   +-- AnyCodableValue.kt      # JSON interop type-erased
|   |
|   +-- domain/
|   |   +-- models/                  # Modelos de dominio
|   |   |   +-- Session.kt
|   |   |   +-- CronJob.kt
|   |   |   +-- Channel.kt
|   |   |   +-- Plugin.kt
|   |   |   +-- Device.kt
|   |   |   +-- ChatMessage.kt
|   |   |   +-- AgentEvent.kt
|   |   |   +-- HealthStatus.kt
|   |   |
|   |   +-- repositories/           # Interfaces de repositorio
|   |       +-- ChatRepository.kt
|   |       +-- CronRepository.kt
|   |       +-- ChannelsRepository.kt
|   |       +-- PluginsRepository.kt
|   |
|   +-- services/
|   |   +-- ConnectionManager.kt    # Gestion de conexion (LAN/remota/hibrida)
|   |   +-- EventBus.kt             # Distribucion de eventos push
|   |   +-- PairingService.kt       # Flujo de emparejamiento
|   |   +-- AuthStore.kt            # Token management (expect/actual)
|   |
|   +-- viewmodels/                  # ViewModels compartidos
|       +-- DashboardViewModel.kt
|       +-- ChatViewModel.kt
|       +-- CronViewModel.kt
|       +-- ChannelsViewModel.kt
|       +-- PluginsViewModel.kt
|       +-- SettingsViewModel.kt
|
+-- iosApp/                          # Swift/SwiftUI
|   +-- App/
|   |   +-- McClawMobileApp.swift
|   |   +-- AppDelegate.swift        # Push notifications setup
|   |
|   +-- Views/
|   |   +-- DashboardView.swift
|   |   +-- ChatView.swift
|   |   +-- CronJobsView.swift
|   |   +-- ChannelsView.swift
|   |   +-- PluginsView.swift
|   |   +-- PairingView.swift        # QR scanner
|   |   +-- SettingsView.swift
|   |
|   +-- Platform/
|       +-- KeychainAuthStore.swift  # actual para AuthStore
|       +-- APNsHandler.swift
|       +-- BonjourDiscovery.swift   # mDNS discovery
|
+-- androidApp/                      # Kotlin/Jetpack Compose
    +-- app/
    |   +-- McClawMobileApp.kt
    |
    +-- ui/
    |   +-- screens/
    |   |   +-- DashboardScreen.kt
    |   |   +-- ChatScreen.kt
    |   |   +-- CronJobsScreen.kt
    |   |   +-- ChannelsScreen.kt
    |   |   +-- PluginsScreen.kt
    |   |   +-- PairingScreen.kt     # QR scanner
    |   |   +-- SettingsScreen.kt
    |   |
    |   +-- theme/
    |       +-- Theme.kt
    |       +-- Colors.kt
    |
    +-- platform/
        +-- KeyStoreAuthStore.kt     # actual para AuthStore
        +-- FCMHandler.kt
        +-- NsdDiscovery.kt          # mDNS discovery
```

### 4.3 Dependencias Clave (shared)

| Libreria | Uso |
|----------|-----|
| **Ktor Client** | WebSocket + HTTP (multiplataforma) |
| **kotlinx.serialization** | JSON parsing (equivalente a Codable) |
| **kotlinx.coroutines** | Async/await, Flow (equivalente a AsyncStream) |
| **Koin** | Inyeccion de dependencias |
| **kotlinx.datetime** | Fechas multiplataforma |
| **Napier** | Logging multiplataforma |

### 4.4 Dependencias por Plataforma

**iOS:**
- AVFoundation (camara para QR)
- Network.framework (mDNS)
- UserNotifications (push)
- Security.framework (Keychain)

**Android:**
- CameraX (camara para QR)
- NsdManager (mDNS)
- Firebase Messaging (push)
- AndroidX Security (EncryptedSharedPreferences)

---

## 5. Protocolo de Comunicacion (Detalle)

### 5.1 WebSocket Client (Shared)

El cliente WebSocket compartido replica la logica de `GatewayConnectionService.swift`:

```kotlin
// shared/protocol/WSClient.kt
class WSClient {
    private var socket: WebSocketSession? = null
    private var sequence = AtomicInteger(0)
    private val pending = ConcurrentHashMap<Int, CompletableDeferred<WSResponse>>()
    private val _events = MutableSharedFlow<WSEvent>()
    val events: SharedFlow<WSEvent> = _events

    suspend fun connect(config: ConnectionConfig) { ... }
    suspend fun disconnect() { ... }

    suspend fun <T> call(method: String, params: Map<String, Any>? = null): T {
        val seq = sequence.incrementAndGet()
        val deferred = CompletableDeferred<WSResponse>()
        pending[seq] = deferred
        socket?.send(WSRequest(seq, method, params).toJson())
        val response = deferred.await()
        if (!response.ok) throw RPCException(response.error)
        return response.result.decode<T>()
    }
}
```

### 5.2 Eventos en Tiempo Real

```kotlin
// shared/services/EventBus.kt
class EventBus(private val wsClient: WSClient) {
    val chatMessages: Flow<ChatEvent>
    val agentActivity: Flow<AgentEvent>
    val cronEvents: Flow<CronEvent>
    val channelEvents: Flow<ChannelEvent>
    val healthUpdates: Flow<HealthEvent>
    val presenceChanges: Flow<PresenceEvent>
    val execApprovals: Flow<ExecApprovalEvent>

    init {
        // Filtra wsClient.events por tipo y deserializa
        chatMessages = wsClient.events
            .filter { it.event == "chat" }
            .map { decode<ChatEvent>(it.data) }
        // ... etc
    }
}
```

### 5.3 Descubrimiento en Red Local

```kotlin
// expect en shared
expect class NetworkDiscovery {
    fun discoverGateways(): Flow<DiscoveredGateway>
}

data class DiscoveredGateway(
    val host: String,
    val port: Int,
    val name: String,       // "McClaw de Jose"
    val version: String     // protocolo
)

// actual iOS -> NWBrowser con Bonjour _mcclaw._tcp
// actual Android -> NsdManager con _mcclaw._tcp
```

---

## 6. Cambios Necesarios en McClaw/Gateway

### 6.1 En el Gateway (Node.js)

| Cambio | Descripcion | Prioridad |
|--------|-------------|-----------|
| **mDNS Advertising** | Publicar servicio `_mcclaw._tcp` con puerto y metadata | Alta |
| **Device Pairing Flow** | Implementar generacion de QR, validacion de codigo, emision de tokens | Alta |
| **Push Service** | Modulo para enviar APNs + FCM cuando el dispositivo no esta conectado | Media |
| **Mobile Presence** | Registrar tipo `mobile` en presencia, trackear dispositivos conectados | Alta |
| **Notification Queue** | Cola de mensajes pendientes para cuando el movil reconecta | Media |
| **Rate Limiting** | Limitar requests desde moviles (proteccion contra uso excesivo) | Baja |
| **Chat RPCs** | Implementar `chat.send`, `chat.history`, `chat.abort` si no existen en el Gateway | Alta |
| **Sessions RPCs** | Implementar `sessions.spawn`, `models.list` si no existen | Alta |

### 6.2 En McClaw macOS (Swift)

| Cambio | Descripcion | Prioridad |
|--------|-------------|-----------|
| **Settings > Devices** | Nueva tab para gestionar dispositivos emparejados | Alta |
| **QR Generator** | Generar QR con datos de conexion + pairing code | Alta |
| **MobileNativeService** | Implementar NativeChannel para el canal "mobile" | Alta |
| **Device Notifications** | Mostrar alertas cuando un dispositivo se conecta/desconecta | Media |
| **Remote Exec Approval** | Reenviar solicitudes de aprobacion al movil via push | Media |
| **Device Pairing RPCs** | Implementar `device.pair.list/approve/reject` en GatewayConnectionService (documentados en protocolo pero no implementados aun) | Alta |
| **Chat/Session RPCs** | Implementar wrappers en GatewayConnectionService para `chat.send`, `chat.history`, `chat.abort`, `sessions.spawn`, `models.list` (documentados en protocolo pero no implementados aun) | Alta |

**Nota importante sobre RPCs pendientes:** Los metodos `device.pair.*`, `chat.send/history/abort`, `sessions.spawn` y `models.list` estan documentados en el protocolo Gateway (doc 04) pero **no estan implementados aun** en `GatewayConnectionService.swift`. Estos deben implementarse tanto en el Gateway (Node.js) como en el wrapper Swift antes de que las apps moviles puedan usarlos. Los RPCs de cron, channels, plugins y exec approvals **si estan implementados** y listos.

### 6.3 Registro mDNS (Gateway)

El Gateway debe anunciar su presencia en la red local:

```javascript
// Gateway - mDNS advertising
const mdns = require('mdns');

const ad = mdns.createAdvertisement(
    mdns.tcp('mcclaw'),
    config.port,
    {
        name: config.instanceName || 'McClaw Gateway',
        txtRecord: {
            version: '3',
            platform: process.platform,
            features: 'chat,cron,channels,plugins,canvas'
        }
    }
);
ad.start();
```

---

## 7. Seguridad

### 7.1 Autenticacion

- **Emparejamiento:** Unico, via QR code con codigo temporal (expira en 5 minutos)
- **Token permanente:** JWT con claim `deviceId`, almacenado en Keychain/KeyStore
- **Renovacion:** Token se renueva automaticamente antes de expirar
- **Revocacion:** Desde McClaw macOS se puede revocar acceso a cualquier dispositivo

### 7.2 Transporte

- **LAN:** `ws://` aceptable solo en red local (mismo comportamiento que McClaw macOS)
- **Internet:** `wss://` obligatorio. Sin excepciones
- **Certificate pinning:** Opcional pero recomendado para conexiones directas

### 7.3 Permisos Granulares

Cada dispositivo emparejado puede tener permisos limitados:

```json
{
  "deviceId": "uuid",
  "permissions": {
    "chat": true,
    "cron.read": true,
    "cron.write": true,
    "channels.read": true,
    "channels.write": false,
    "plugins.read": true,
    "plugins.write": false,
    "exec.approve": true,
    "config.read": true,
    "config.write": false,
    "node.invoke": false
  }
}
```

Esto permite, por ejemplo, dar acceso de lectura a un segundo dispositivo sin que pueda instalar plugins o modificar cron jobs.

---

## 8. Plan de Sprints

### Sprint M1: Fundamentos (2 semanas)

**Shared:**
- Configurar proyecto KMP (shared + iosApp + androidApp)
- Implementar WSClient con Ktor WebSocket
- Implementar WSModels (WSRequest, WSResponse, WSEvent, AnyCodableValue)
- Implementar RPCClient con seq matching y timeout
- Tests unitarios del protocolo

**McClaw/Gateway:**
- Implementar mDNS advertising en Gateway
- Crear endpoint de device pairing (generacion de codigo, validacion)

**Tests:** 30+ tests del protocolo compartido

---

### Sprint M2: Pairing y Conexion (2 semanas)

**Shared:**
- ConnectionManager (LAN discovery + remote + hibrido)
- PairingService (flujo completo)
- AuthStore (expect/actual)

**iOS:**
- PairingView con QR scanner (AVFoundation)
- KeychainAuthStore
- BonjourDiscovery (Network.framework)

**Android:**
- PairingScreen con QR scanner (CameraX)
- KeyStoreAuthStore
- NsdDiscovery

**McClaw macOS:**
- Settings > Devices tab con QR generator
- device.pair.approve/reject en GatewayConnectionService

**Tests:** 20+ tests de pairing y discovery

---

### Sprint M3: Dashboard y Estado (2 semanas)

**Shared:**
- DashboardViewModel
- HealthRepository
- EventBus (primera version: health, presence)

**iOS:**
- DashboardView (estado, sesiones, channels, CLIs)

**Android:**
- DashboardScreen (equivalente)

**Tests:** 15+ tests de viewmodels

---

### Sprint M4: Chat Remoto (2 semanas)

**Shared:**
- ChatViewModel
- ChatRepository (history, send, abort, streaming)
- EventBus: chat events, agent events

**iOS:**
- ChatView con lista de sesiones
- MessageBubbleView con markdown rendering
- Adjuntos (fotos)

**Android:**
- ChatScreen equivalente
- Markdown rendering
- Adjuntos

**Tests:** 25+ tests de chat

---

### Sprint M5: Cron Jobs (2 semanas)

**Shared:**
- CronViewModel
- CronRepository (CRUD + runs + manual run)
- Schedule editor logic (cron expression parser)

**iOS:**
- CronJobsView (lista + detalle)
- CronEditorView (schedule picker)
- RunHistoryView

**Android:**
- Equivalentes Compose

**Tests:** 20+ tests de cron

---

### Sprint M6: Channels y Plugins (2 semanas)

**Shared:**
- ChannelsViewModel + ChannelsRepository
- PluginsViewModel + PluginsRepository

**iOS:**
- ChannelsView (estado, connect/disconnect)
- PluginsView (lista, install/uninstall, toggle)

**Android:**
- Equivalentes Compose

**Tests:** 20+ tests

---

### Sprint M7: Push Notifications (2 semanas)

**Gateway:**
- PushService con APNs + FCM adapters
- NotificationQueue para mensajes pendientes
- Registro de device tokens

**iOS:**
- APNsHandler + UNUserNotificationCenter
- Background refresh

**Android:**
- FCMHandler + FirebaseMessagingService
- Notification channels por tipo

**McClaw macOS:**
- MobileNativeService (NativeChannel para mobile)
- Reenvio de exec.approval a dispositivos

**Tests:** 15+ tests

---

### Sprint M8: Canvas, Nodos y Config Remota (2 semanas)

**Shared:**
- CanvasViewModel (snapshots, navegacion)
- NodesViewModel (list, describe, invoke)
- SettingsViewModel (config remota, device management)

**iOS + Android:**
- Pantallas de canvas, nodos y settings

**Tests:** 15+ tests

---

### Sprint M9: Exec Approvals y Permisos (1 semana)

**Shared:**
- ExecApprovalViewModel
- Permisos granulares por dispositivo

**iOS + Android:**
- Notificacion push critica para aprobaciones
- Pantalla de aprobar/rechazar con detalle del comando

**McClaw macOS:**
- UI para configurar permisos por dispositivo

**Tests:** 10+ tests

---

### Sprint M10: Polish y Release (2 semanas)

- Onboarding flow (primera vez, emparejamiento guiado)
- Themes (light/dark, siguiendo sistema)
- Offline mode (cache local, cola de acciones pendientes)
- Haptic feedback
- Accessibility (VoiceOver, TalkBack)
- App icons y splash screens
- Screenshots para App Store y Play Store
- TestFlight / Internal Testing track
- Performance profiling
- Documentacion de usuario

---

## 9. Esquema de Datos Compartidos

### 9.1 Modelos (shared/domain/models/)

Estos modelos son el equivalente Kotlin de los modelos Swift existentes en McClaw:

```kotlin
@Serializable
data class GatewayStatus(
    val ok: Boolean,
    val version: String,
    val uptime: Long,
    val sessions: Int,
    val channels: Map<String, ChannelStatus>
)

@Serializable
data class ChatMessage(
    val id: String,
    val sessionKey: String,
    val role: MessageRole,      // user, assistant, system
    val content: String,
    val timestamp: Instant,
    val isPartial: Boolean = false
)

@Serializable
data class CronJob(
    val id: String,
    val name: String,
    val enabled: Boolean,
    val schedule: CronSchedule,
    val payload: CronPayload,
    val state: CronJobState
)

@Serializable
data class PairedDevice(
    val deviceId: String,
    val name: String,
    val platform: DevicePlatform,  // ios, android
    val lastSeen: Instant,
    val permissions: DevicePermissions,
    val pushToken: String?
)
```

---

## 10. Preparacion para McClaw Win

La arquitectura KMP esta pensada para que la capa `shared/` se reutilice:

- `shared/protocol/` -> compila a JVM para Windows (Desktop Compose o similar)
- `shared/domain/` -> modelos y logica identicos
- `shared/viewmodels/` -> reutilizables con Compose Desktop
- Solo la capa `platform/` (auth store, discovery) necesita implementacion Windows

Cuando McClaw Win exista, la app Windows puede reutilizar el 70-80% de la capa compartida.

---

## 11. Metricas de Exito

| Metrica | Objetivo |
|---------|----------|
| Tiempo de emparejamiento | < 30 segundos (QR scan to connected) |
| Latencia de chat (LAN) | < 100ms round-trip |
| Latencia de chat (remoto) | < 500ms round-trip |
| Push notification delivery | < 3 segundos |
| Cobertura de tests (shared) | > 80% |
| Crash rate | < 0.1% |
| Consumo de bateria | < 2% en background (push only) |

---

## 12. Resumen de RPCs por Funcionalidad

| Funcionalidad | RPCs | Eventos |
|---------------|------|---------|
| Dashboard | `status`, `health`, `sessions.list` | `health`, `presence` |
| Chat | `chat.send`, `chat.history`, `chat.abort`, `sessions.spawn` | `chat`, `agent` |
| Cron | `cron.list/add/remove/update/run/runs/status` | `cron` |
| Channels | `channels.status`, `channels.logout` | `channels` |
| Plugins | `plugins.list/install/uninstall/toggle` | `plugins` |
| Models | `models.list` | - |
| Nodes | `node.list/describe/invoke`, `node.pair.*` | `node.invoke` |
| Devices | `device.pair.list/approve/reject` | `presence` |
| Config | `config.get/set/patch` | - |
| Security | `exec.approval.resolve` | `exec.approval.requested` |
| Canvas | via `node.invoke` | - |
| Voice | `voicewake.get/set`, `talk.config/mode` | `voicewake` |
| Gateway | `gateway.restart`, `gateway.update` | `instance` |
