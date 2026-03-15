# 15a - McClaw Mobile iOS: Plan de Implementacion

## Referencia: [15-MOBILE-APPS-ARCHITECTURE.md](15-MOBILE-APPS-ARCHITECTURE.md)

---

## 1. Resumen del Proyecto

App nativa iOS (SwiftUI) que actua como mando a distancia de McClaw. La logica de protocolo, modelos y viewmodels vive en la capa compartida KMP (Kotlin). La app iOS consume esa capa y proporciona la UI nativa y las integraciones de plataforma (Keychain, APNs, Bonjour, camara).

**Requisitos minimos:** iOS 17+, iPhone y iPad.

**Repositorio:** `mcclaw-ios` (independiente de mcclaw-mobile shared, que se integra como dependencia SPM via KMP-to-Swift bridge).

---

## 2. Estructura del Proyecto iOS

```
mcclaw-ios/
|
+-- McClaw Mobile.xcodeproj
|
+-- McClaw Mobile/
|   +-- App/
|   |   +-- McClawMobileApp.swift           # @main, WindowGroup
|   |   +-- AppDelegate.swift               # UIApplicationDelegate para APNs
|   |   +-- AppState.swift                  # @Observable estado global iOS
|   |
|   +-- Navigation/
|   |   +-- RootTabView.swift               # TabView principal (Dashboard, Chat, Cron, More)
|   |   +-- Router.swift                    # NavigationPath programatico
|   |   +-- DeepLinkHandler.swift           # mcclaw:// URL scheme
|   |
|   +-- Views/
|   |   +-- Pairing/
|   |   |   +-- WelcomeView.swift           # Primera ejecucion, onboarding
|   |   |   +-- QRScannerView.swift         # AVCaptureSession para QR
|   |   |   +-- PairingProgressView.swift   # Estado del emparejamiento
|   |   |   +-- PairingSuccessView.swift    # Confirmacion
|   |   |
|   |   +-- Dashboard/
|   |   |   +-- DashboardView.swift         # Vista principal con estado
|   |   |   +-- ConnectionStatusCard.swift  # Estado Gateway
|   |   |   +-- ActiveSessionsCard.swift    # Sesiones activas
|   |   |   +-- ChannelsStatusCard.swift    # Channels con indicadores
|   |   |   +-- NextCronJobsCard.swift      # Proximos jobs
|   |   |   +-- AgentActivityCard.swift     # Actividad reciente
|   |   |
|   |   +-- Chat/
|   |   |   +-- SessionListView.swift       # Lista de sesiones
|   |   |   +-- ChatView.swift              # Conversacion con streaming
|   |   |   +-- MessageBubbleView.swift     # Burbuja individual
|   |   |   +-- MarkdownRenderer.swift      # Render de markdown en chat
|   |   |   +-- CodeBlockView.swift         # Bloques de codigo con syntax
|   |   |   +-- ChatInputBar.swift          # Input con adjuntos
|   |   |   +-- ModelPickerView.swift       # Selector de modelo/provider
|   |   |   +-- AttachmentPicker.swift      # Camara + galeria
|   |   |
|   |   +-- CronJobs/
|   |   |   +-- CronJobsListView.swift      # Lista con estado
|   |   |   +-- CronJobDetailView.swift     # Detalle + historial
|   |   |   +-- CronJobEditorView.swift     # Crear/editar job
|   |   |   +-- SchedulePickerView.swift    # Selector visual de schedule
|   |   |   +-- RunHistoryView.swift        # Historial de ejecuciones
|   |   |
|   |   +-- Channels/
|   |   |   +-- ChannelsListView.swift      # Lista con estado
|   |   |   +-- ChannelDetailView.swift     # Detalle + stats
|   |   |
|   |   +-- Plugins/
|   |   |   +-- PluginsListView.swift       # Lista con toggle
|   |   |   +-- PluginDetailView.swift      # Detalle + config
|   |   |   +-- PluginInstallView.swift     # Buscar e instalar
|   |   |
|   |   +-- Canvas/
|   |   |   +-- CanvasGalleryView.swift     # Galeria de snapshots
|   |   |   +-- CanvasDetailView.swift      # Vista de snapshot
|   |   |
|   |   +-- Approvals/
|   |   |   +-- ApprovalBannerView.swift    # Banner in-app urgente
|   |   |   +-- ApprovalDetailView.swift    # Detalle del comando
|   |   |
|   |   +-- Nodes/
|   |   |   +-- NodesListView.swift         # Nodos conectados
|   |   |   +-- NodeDetailView.swift        # Capacidades del nodo
|   |   |
|   |   +-- Settings/
|   |       +-- SettingsView.swift          # Settings principal
|   |       +-- DevicesView.swift           # Dispositivos emparejados
|   |       +-- ConnectionSettingsView.swift # LAN/remoto
|   |       +-- NotificationSettingsView.swift # Tipos de push
|   |       +-- AboutView.swift             # Version, licencias
|   |
|   +-- Platform/
|   |   +-- Auth/
|   |   |   +-- KeychainAuthStore.swift     # actual para AuthStore (KMP)
|   |   |   +-- KeychainHelper.swift        # Wrapper de Security.framework
|   |   |
|   |   +-- Push/
|   |   |   +-- APNsHandler.swift           # Registro y manejo de tokens
|   |   |   +-- PushNotificationParser.swift # Parseo de payloads
|   |   |   +-- NotificationActions.swift   # Approve/Reject actions
|   |   |
|   |   +-- Discovery/
|   |   |   +-- BonjourDiscovery.swift      # NWBrowser para _mcclaw._tcp
|   |   |   +-- NetworkMonitor.swift        # NWPathMonitor (wifi/cellular)
|   |   |
|   |   +-- Camera/
|   |       +-- QRCodeScanner.swift         # AVCaptureSession + AVMetadata
|   |
|   +-- Components/
|   |   +-- StatusBadge.swift               # Indicador de estado (pill)
|   |   +-- LoadingOverlay.swift            # Overlay de carga
|   |   +-- ErrorBanner.swift               # Banner de error
|   |   +-- EmptyStateView.swift            # Estado vacio
|   |   +-- RefreshableList.swift           # Pull-to-refresh
|   |   +-- SearchBar.swift                 # Barra de busqueda
|   |   +-- ConfirmationDialog.swift        # Dialogo de confirmacion
|   |
|   +-- Theme/
|   |   +-- Colors.swift                    # Paleta McClaw
|   |   +-- Typography.swift                # Tipografia
|   |   +-- Spacing.swift                   # Constantes de espaciado
|   |
|   +-- Extensions/
|   |   +-- Date+Formatting.swift
|   |   +-- String+Markdown.swift
|   |   +-- View+Shimmer.swift              # Skeleton loading
|   |
|   +-- Resources/
|       +-- Assets.xcassets/                # App icon, colores, imagenes
|       +-- en.lproj/Localizable.strings    # Ingles
|       +-- es.lproj/Localizable.strings    # Espanol
|       +-- Info.plist
|
+-- McClaw MobileTests/
|   +-- Platform/
|   |   +-- KeychainAuthStoreTests.swift
|   |   +-- BonjourDiscoveryTests.swift
|   |   +-- PushNotificationParserTests.swift
|   |
|   +-- Views/
|       +-- DashboardViewModelTests.swift   # Tests de integracion con KMP VMs
|       +-- ChatViewTests.swift
|
+-- McClaw MobileUITests/
    +-- PairingFlowUITests.swift
    +-- ChatFlowUITests.swift
    +-- CronJobsUITests.swift
```

---

## 3. Integracion con KMP (Shared)

### 3.1 Como se integra la capa compartida

El modulo KMP `shared` se compila como XCFramework y se distribuye via SPM (Swift Package Manager):

```swift
// Package.swift (generado por KMP)
// McClaw Mobile importa el framework:
import Shared  // Modulo KMP compilado
```

**Acceso a ViewModels compartidos desde SwiftUI:**

```swift
// DashboardView.swift
struct DashboardView: View {
    // El ViewModel viene de KMP (Kotlin), envuelto para SwiftUI
    @StateObject private var viewModel = DashboardViewModelWrapper()

    var body: some View {
        ScrollView {
            ConnectionStatusCard(status: viewModel.connectionStatus)
            ActiveSessionsCard(sessions: viewModel.sessions)
            ChannelsStatusCard(channels: viewModel.channels)
            NextCronJobsCard(jobs: viewModel.nextCronJobs)
        }
        .refreshable { await viewModel.refresh() }
    }
}

// Wrapper que adapta el ViewModel KMP a @ObservableObject
@MainActor
class DashboardViewModelWrapper: ObservableObject {
    private let vm = DashboardViewModel()  // Kotlin class

    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var sessions: [Session] = []
    @Published var channels: [ChannelInfo] = []
    @Published var nextCronJobs: [CronJob] = []

    init() {
        // Observa los StateFlow de Kotlin como Combine publishers
        FlowCollector.collect(vm.connectionStatusFlow) { [weak self] status in
            self?.connectionStatus = status
        }
        // ... etc para cada Flow
    }

    func refresh() async {
        try? await vm.refresh()
    }
}
```

### 3.2 Adaptacion de Kotlin Flow a Swift

```swift
// FlowCollector.swift - Puente entre Kotlin Flow y Swift @Published
class FlowCollector {
    static func collect<T>(
        _ flow: Kotlinx_coroutines_coreFlow,
        onEach: @escaping (T) -> Void
    ) {
        Task {
            for await value in flow.asAsyncSequence() {
                await MainActor.run {
                    onEach(value as! T)
                }
            }
        }
    }
}
```

### 3.3 Platform Implementations (actual)

```swift
// KeychainAuthStore.swift
// Implementacion iOS del expect class AuthStore de KMP
class KeychainAuthStore: AuthStoreProtocol {
    private let service = "com.mcclaw.mobile"

    func saveToken(_ token: String, forDevice deviceId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId,
            kSecValueData as String: token.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func getToken(forDevice deviceId: String) -> String? {
        // SecItemCopyMatching...
    }

    func deleteToken(forDevice deviceId: String) {
        // SecItemDelete...
    }
}
```

---

## 4. Implementaciones de Plataforma (Detalle)

### 4.1 QR Scanner

```swift
// QRCodeScanner.swift
struct QRCodeScanner: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    // QRScannerViewController usa:
    // - AVCaptureSession con AVCaptureDevice.default(.builtInWideAngleCamera)
    // - AVCaptureMetadataOutput con .qr type
    // - Preview layer en la vista
}
```

### 4.2 Bonjour Discovery (mDNS)

```swift
// BonjourDiscovery.swift
@Observable
class BonjourDiscovery {
    private var browser: NWBrowser?
    var discoveredGateways: [DiscoveredGateway] = []

    func startDiscovery() {
        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: "_mcclaw._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { results, changes in
            // Resuelve cada resultado a host:port
            // Extrae TXT record (version, features)
            // Actualiza discoveredGateways
        }
        browser?.start(queue: .main)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }
}
```

### 4.3 Push Notifications (APNs)

```swift
// APNsHandler.swift
class APNsHandler: NSObject, UNUserNotificationCenterDelegate {

    func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .criticalAlert]  // criticalAlert para exec.approval
        ) { granted, error in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // Token recibido -> enviarlo al Gateway
    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            await GatewayClient.shared.registerPushToken(token, platform: "apns")
        }
    }

    // Configurar categorias de notificacion
    func setupNotificationCategories() {
        let approveAction = UNNotificationAction(
            identifier: "APPROVE_EXEC",
            title: String(localized: "Approve"),
            options: [.authenticationRequired]
        )
        let rejectAction = UNNotificationAction(
            identifier: "REJECT_EXEC",
            title: String(localized: "Reject"),
            options: [.destructive]
        )
        let execCategory = UNNotificationCategory(
            identifier: "EXEC_APPROVAL",
            actions: [approveAction, rejectAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([execCategory])
    }

    // Manejar accion del usuario sobre la notificacion
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let requestId = userInfo["requestId"] as? String else { return }

        switch response.actionIdentifier {
        case "APPROVE_EXEC":
            await GatewayClient.shared.resolveExecApproval(requestId: requestId, approved: true)
        case "REJECT_EXEC":
            await GatewayClient.shared.resolveExecApproval(requestId: requestId, approved: false)
        default:
            // Abrir la app en la pantalla de approval
            Router.shared.navigate(to: .execApproval(requestId))
        }
    }
}
```

**Payload APNs esperado del Gateway:**

```json
{
  "aps": {
    "alert": {
      "title": "Exec Approval Required",
      "body": "rm -rf /tmp/cache/* requested by Claude CLI",
      "loc-key": "exec_approval_body",
      "loc-args": ["rm -rf /tmp/cache/*", "Claude CLI"]
    },
    "sound": "default",
    "category": "EXEC_APPROVAL",
    "interruption-level": "critical"
  },
  "type": "exec.approval",
  "requestId": "req-abc-123",
  "command": "rm -rf /tmp/cache/*",
  "source": "claude"
}
```

### 4.4 Network Monitor

```swift
// NetworkMonitor.swift
@Observable
class NetworkMonitor {
    private let monitor = NWPathMonitor()
    var isConnected: Bool = false
    var isOnWifi: Bool = false
    var isOnCellular: Bool = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isOnWifi = path.usesInterfaceType(.wifi)
                self?.isOnCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: .global(qos: .background))
    }
}
```

---

## 5. Navegacion y Flujo de Pantallas

### 5.1 Flujo Principal

```
[Primera vez]
    WelcomeView -> QRScannerView -> PairingProgressView -> PairingSuccessView
        |
        v
[App normal]
    RootTabView
        +-- Tab 1: DashboardView
        +-- Tab 2: ChatView (SessionListView -> ChatView)
        +-- Tab 3: CronJobsListView (-> CronJobDetailView, CronJobEditorView)
        +-- Tab 4: MoreView
                +-- ChannelsListView
                +-- PluginsListView
                +-- CanvasGalleryView
                +-- NodesListView
                +-- SettingsView
                        +-- DevicesView
                        +-- ConnectionSettingsView
                        +-- NotificationSettingsView
                        +-- AboutView
```

### 5.2 Deep Links

```
mcclaw://chat/{sessionKey}          -> Abre sesion de chat
mcclaw://approval/{requestId}       -> Pantalla de aprobacion
mcclaw://cron/{jobId}               -> Detalle de cron job
mcclaw://pair?code={pairingCode}    -> Inicia emparejamiento
```

---

## 6. Sprints iOS (Detalle)

### Sprint iOS-1: Scaffolding y Pairing (2 semanas)

**Tareas:**

1. Crear proyecto Xcode con estructura de carpetas completa
2. Integrar KMP shared como XCFramework via SPM
3. Configurar signing, capabilities (Push Notifications, Camera, Network)
4. Implementar WelcomeView (onboarding de primera vez)
5. Implementar QRCodeScanner (AVCaptureSession + metadata QR)
6. Implementar QRScannerView (SwiftUI wrapper del scanner)
7. Implementar PairingProgressView (animacion de conexion)
8. Implementar PairingSuccessView (confirmacion con device name)
9. Implementar KeychainAuthStore (guardar/leer/borrar tokens)
10. Implementar KeychainHelper (wrapper low-level de Security.framework)
11. Conectar PairingService (KMP) con QRScannerView
12. Test: KeychainAuthStoreTests (save, get, delete, overwrite)
13. Test: QR payload parsing tests
14. Test: PairingFlowUITests (happy path simulado)

**Entregable:** App que escanea QR y se empareja con McClaw.

**Dependencias McClaw:** Sprint MC-1 (device pairing en Gateway) debe estar listo.

---

### Sprint iOS-2: Conexion y Dashboard (2 semanas)

**Tareas:**

1. Implementar BonjourDiscovery (NWBrowser para _mcclaw._tcp)
2. Implementar NetworkMonitor (NWPathMonitor wifi/cellular)
3. Implementar AppState (@Observable con estado global)
4. Implementar RootTabView (TabView con 4 tabs)
5. Implementar Router (NavigationPath programatico)
6. Implementar DashboardView con scroll vertical
7. Implementar ConnectionStatusCard (estado, latencia, modo)
8. Implementar ActiveSessionsCard (lista horizontal con preview)
9. Implementar ChannelsStatusCard (grid de iconos con badge)
10. Implementar NextCronJobsCard (proximos 3 jobs)
11. Implementar AgentActivityCard (actividad reciente)
12. Implementar StatusBadge (componente reutilizable)
13. Implementar pull-to-refresh en DashboardView
14. Conectar DashboardViewModel (KMP) con vistas
15. Test: BonjourDiscoveryTests (mock NWBrowser)
16. Test: DashboardViewModelTests (estados de conexion)

**Entregable:** App con dashboard funcional mostrando estado real de McClaw.

---

### Sprint iOS-3: Chat Remoto (2 semanas)

**Tareas:**

1. Implementar SessionListView (lista de sesiones con preview)
2. Implementar ChatView (lista de mensajes con scroll automatico)
3. Implementar MessageBubbleView (user vs assistant, timestamps)
4. Implementar MarkdownRenderer (texto con formato en burbujas)
5. Implementar CodeBlockView (syntax highlighting basico, copy button)
6. Implementar ChatInputBar (TextField + boton send + adjuntos)
7. Implementar streaming de respuestas (actualizacion incremental)
8. Implementar ModelPickerView (selector de modelo/provider)
9. Implementar AttachmentPicker (PHPickerViewController + UIImagePickerController)
10. Implementar indicador de "typing" cuando el agente trabaja
11. Implementar abort de generacion (boton stop)
12. Implementar haptic feedback al enviar/recibir
13. Conectar ChatViewModel (KMP) con vistas
14. Test: MarkdownRenderer tests
15. Test: ChatView snapshot tests
16. Test: ChatFlowUITests (enviar mensaje, recibir respuesta)

**Entregable:** Chat funcional con streaming, markdown y adjuntos.

---

### Sprint iOS-4: Cron Jobs (2 semanas)

**Tareas:**

1. Implementar CronJobsListView (lista filtrable: activos/pausados/todos)
2. Implementar CronJobDetailView (info, estado, next run, historial)
3. Implementar CronJobEditorView (formulario crear/editar)
4. Implementar SchedulePickerView (visual: rapido vs cron expression)
5. Implementar RunHistoryView (lista de ejecuciones con status pills)
6. Implementar accion "Run Now" con confirmacion
7. Implementar toggle enable/disable con optimistic update
8. Implementar swipe actions (delete, run now)
9. Conectar CronViewModel (KMP)
10. Test: SchedulePickerView tests (parsing cron expressions)
11. Test: CronJobsUITests (crear, editar, eliminar)

**Entregable:** Gestion completa de cron jobs desde iOS.

---

### Sprint iOS-5: Channels, Plugins y Canvas (2 semanas)

**Tareas:**

1. Implementar ChannelsListView (grid con estado y badge)
2. Implementar ChannelDetailView (stats, config, connect/disconnect)
3. Implementar PluginsListView (lista con toggle enable/disable)
4. Implementar PluginDetailView (info, version, config)
5. Implementar PluginInstallView (busqueda + instalacion)
6. Implementar CanvasGalleryView (grid de snapshots)
7. Implementar CanvasDetailView (zoom, compartir, info)
8. Conectar ChannelsViewModel, PluginsViewModel, CanvasViewModel (KMP)
9. Test: ChannelsListView tests
10. Test: PluginsListView tests

**Entregable:** Gestion de channels, plugins y galeria de canvas.

---

### Sprint iOS-6: Push Notifications y Approvals (2 semanas)

**Tareas:**

1. Implementar APNsHandler (registro, token, categorias)
2. Implementar PushNotificationParser (parseo de payloads por tipo)
3. Implementar NotificationActions (approve/reject desde notificacion)
4. Configurar UNNotificationCategory para EXEC_APPROVAL
5. Solicitar permiso de Critical Alerts (requiere entitlement de Apple)
6. Implementar ApprovalBannerView (banner in-app urgente)
7. Implementar ApprovalDetailView (comando, origen, approve/reject)
8. Implementar NotificationSettingsView (seleccionar tipos de push)
9. Implementar background refresh para mantener badge actualizado
10. Conectar con PushService del Gateway (registro de device token)
11. Test: PushNotificationParserTests (todos los tipos de payload)
12. Test: NotificationActions tests

**Entregable:** Push notifications funcionales con approve/reject desde lock screen.

**Dependencias McClaw:** Sprint MC-4 (PushService en Gateway) debe estar listo.

---

### Sprint iOS-7: Nodos, Settings y Config Remota (1.5 semanas)

**Tareas:**

1. Implementar NodesListView (nodos conectados con capacidades)
2. Implementar NodeDetailView (info, invoke commands)
3. Implementar SettingsView (hub de settings)
4. Implementar DevicesView (dispositivos emparejados, revocar)
5. Implementar ConnectionSettingsView (LAN auto / remote URL)
6. Implementar DeepLinkHandler (mcclaw:// URL scheme)
7. Conectar NodesViewModel, SettingsViewModel (KMP)
8. Test: DeepLinkHandler tests

**Entregable:** Control completo de nodos y configuracion remota.

---

### Sprint iOS-8: Polish y Release (2 semanas)

**Tareas:**

1. Implementar tema light/dark siguiendo sistema
2. Definir paleta de colores McClaw (Colors.swift)
3. App icon (1024x1024 + todas las variantes)
4. Launch screen (splash con logo McClaw)
5. Animaciones de transicion entre pantallas
6. Shimmer/skeleton loading en todas las listas
7. Empty state views para listas vacias
8. Accessibility audit (VoiceOver labels, Dynamic Type, contraste)
9. Localizacion completa (es, en)
10. Offline mode: cache local de ultima lectura, cola de acciones
11. Performance profiling (Instruments: leaks, CPU, energy)
12. Reducir consumo de bateria en background (solo push, sin polling)
13. Screenshots para App Store (6.7", 6.1", 12.9" iPad)
14. App Store metadata (descripcion, keywords, categorias)
15. Subir a TestFlight para beta testing
16. Resolver feedback de beta testers

**Entregable:** App lista para envio a App Store.

---

## 7. Dependencias Externas iOS

| Dependencia | Version | Uso |
|-------------|---------|-----|
| KMP Shared XCFramework | (interna) | Protocolo, modelos, viewmodels |
| **Nativa (sin pods)** | - | Se priorizan frameworks de sistema |

**Frameworks de sistema usados:**
- SwiftUI (UI)
- AVFoundation (camara QR)
- Network.framework (Bonjour, NWPathMonitor)
- Security.framework (Keychain)
- UserNotifications (push)
- PhotosUI (picker de fotos)
- OSLog (logging)

**Nota:** Se evita intencionalmente el uso de dependencias externas para la app iOS. Todo se resuelve con frameworks nativos de Apple y la capa KMP. Esto minimiza el tamano del binario y los riesgos de compatibilidad.

---

## 8. Configuracion de Xcode

### 8.1 Capabilities Requeridas

- Push Notifications
- Background Modes: Remote notifications, Background fetch
- Camera (para QR scanner)
- Network Extensions (para mDNS)
- Critical Alerts (requiere solicitud a Apple)

### 8.2 Info.plist

```xml
<key>NSCameraUsageDescription</key>
<string>McClaw Mobile needs the camera to scan QR codes for device pairing</string>

<key>NSLocalNetworkUsageDescription</key>
<string>McClaw Mobile searches the local network to find your McClaw Gateway</string>

<key>NSBonjourServices</key>
<array>
    <string>_mcclaw._tcp</string>
</array>

<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>mcclaw</string>
        </array>
    </dict>
</array>
```

### 8.3 Targets

| Target | Tipo | Proposito |
|--------|------|-----------|
| McClaw Mobile | App | App principal |
| McClaw MobileTests | Unit Tests | Tests unitarios |
| McClaw MobileUITests | UI Tests | Tests de flujo |
| McClaw Mobile Notification Extension | Notification Service Extension | Rich notifications (imagenes, modificacion de contenido) |

---

## 9. Checklist de Calidad Pre-Release

- [ ] Todos los textos usan String(localized:) -- ningun string hardcoded
- [ ] VoiceOver funcional en todas las pantallas
- [ ] Dynamic Type respeta todas las escalas
- [ ] Tema dark y light correctos
- [ ] No hay memory leaks (verificado con Instruments)
- [ ] Energy Impact bajo en background (verificado con Instruments)
- [ ] Crash rate 0% en TestFlight con 10+ testers durante 1 semana
- [ ] Todas las pantallas funcionan en iPhone SE (pantalla pequena)
- [ ] Todas las pantallas funcionan en iPad (multitasking)
- [ ] Deep links funcionan correctamente
- [ ] Push notifications llegan en menos de 3 segundos
- [ ] Exec approval funciona desde lock screen
- [ ] QR pairing funciona a primera en condiciones normales de luz
- [ ] Reconexion automatica tras perdida de red
- [ ] App Store screenshots generadas para todos los tamanos
