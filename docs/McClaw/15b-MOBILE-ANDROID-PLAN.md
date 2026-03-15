# 15b - McClaw Mobile Android: Plan de Implementacion

## Referencia: [15-MOBILE-APPS-ARCHITECTURE.md](15-MOBILE-APPS-ARCHITECTURE.md)

---

## 1. Resumen del Proyecto

App nativa Android (Jetpack Compose) que actua como mando a distancia de McClaw. La logica de protocolo, modelos y viewmodels vive en la capa compartida KMP (Kotlin). La app Android consume esa capa directamente (Kotlin a Kotlin, sin bridge) y proporciona la UI nativa y las integraciones de plataforma (EncryptedSharedPreferences, FCM, NSD, camara).

**Requisitos minimos:** Android 10 (API 29)+, phones y tablets.

**Repositorio:** `mcclaw-android` (consume el modulo shared de KMP como dependencia Gradle).

---

## 2. Estructura del Proyecto Android

```
mcclaw-android/
|
+-- app/
|   +-- src/main/
|   |   +-- java/com/mcclaw/mobile/
|   |   |   +-- McClawMobileApp.kt              # Application class (Koin init)
|   |   |   +-- MainActivity.kt                 # ComponentActivity, NavHost
|   |   |   +-- AppState.kt                     # StateFlow estado global
|   |   |   |
|   |   |   +-- navigation/
|   |   |   |   +-- AppNavigation.kt            # NavHost con rutas
|   |   |   |   +-- Screen.kt                   # Sealed class de rutas
|   |   |   |   +-- DeepLinkHandler.kt          # mcclaw:// intent filter
|   |   |   |
|   |   |   +-- ui/
|   |   |   |   +-- pairing/
|   |   |   |   |   +-- WelcomeScreen.kt        # Onboarding primera vez
|   |   |   |   |   +-- QRScannerScreen.kt      # CameraX + ML Kit QR
|   |   |   |   |   +-- PairingProgressScreen.kt
|   |   |   |   |   +-- PairingSuccessScreen.kt
|   |   |   |   |
|   |   |   |   +-- dashboard/
|   |   |   |   |   +-- DashboardScreen.kt      # Pantalla principal
|   |   |   |   |   +-- ConnectionStatusCard.kt
|   |   |   |   |   +-- ActiveSessionsCard.kt
|   |   |   |   |   +-- ChannelsStatusCard.kt
|   |   |   |   |   +-- NextCronJobsCard.kt
|   |   |   |   |   +-- AgentActivityCard.kt
|   |   |   |   |
|   |   |   |   +-- chat/
|   |   |   |   |   +-- SessionListScreen.kt    # Lista de sesiones
|   |   |   |   |   +-- ChatScreen.kt           # Conversacion streaming
|   |   |   |   |   +-- MessageBubble.kt        # Burbuja de mensaje
|   |   |   |   |   +-- MarkdownText.kt         # Render markdown
|   |   |   |   |   +-- CodeBlock.kt            # Codigo con syntax
|   |   |   |   |   +-- ChatInputBar.kt         # Input + adjuntos
|   |   |   |   |   +-- ModelPicker.kt          # Selector modelo/provider
|   |   |   |   |   +-- AttachmentPicker.kt     # Camara + galeria
|   |   |   |   |
|   |   |   |   +-- cronjobs/
|   |   |   |   |   +-- CronJobsListScreen.kt
|   |   |   |   |   +-- CronJobDetailScreen.kt
|   |   |   |   |   +-- CronJobEditorScreen.kt
|   |   |   |   |   +-- SchedulePicker.kt       # Selector visual
|   |   |   |   |   +-- RunHistoryScreen.kt
|   |   |   |   |
|   |   |   |   +-- channels/
|   |   |   |   |   +-- ChannelsListScreen.kt
|   |   |   |   |   +-- ChannelDetailScreen.kt
|   |   |   |   |
|   |   |   |   +-- plugins/
|   |   |   |   |   +-- PluginsListScreen.kt
|   |   |   |   |   +-- PluginDetailScreen.kt
|   |   |   |   |   +-- PluginInstallScreen.kt
|   |   |   |   |
|   |   |   |   +-- canvas/
|   |   |   |   |   +-- CanvasGalleryScreen.kt
|   |   |   |   |   +-- CanvasDetailScreen.kt
|   |   |   |   |
|   |   |   |   +-- approvals/
|   |   |   |   |   +-- ApprovalBanner.kt       # Banner in-app
|   |   |   |   |   +-- ApprovalDetailScreen.kt
|   |   |   |   |
|   |   |   |   +-- nodes/
|   |   |   |   |   +-- NodesListScreen.kt
|   |   |   |   |   +-- NodeDetailScreen.kt
|   |   |   |   |
|   |   |   |   +-- settings/
|   |   |   |       +-- SettingsScreen.kt
|   |   |   |       +-- DevicesScreen.kt
|   |   |   |       +-- ConnectionSettingsScreen.kt
|   |   |   |       +-- NotificationSettingsScreen.kt
|   |   |   |       +-- AboutScreen.kt
|   |   |   |
|   |   |   +-- ui/components/
|   |   |   |   +-- StatusBadge.kt              # Indicador de estado
|   |   |   |   +-- LoadingOverlay.kt
|   |   |   |   +-- ErrorBanner.kt
|   |   |   |   +-- EmptyState.kt
|   |   |   |   +-- ConfirmDialog.kt
|   |   |   |   +-- ShimmerLoading.kt           # Skeleton loading
|   |   |   |   +-- PullToRefresh.kt
|   |   |   |
|   |   |   +-- ui/theme/
|   |   |   |   +-- Theme.kt                    # Material 3 McClaw theme
|   |   |   |   +-- Colors.kt                   # Paleta McClaw
|   |   |   |   +-- Typography.kt
|   |   |   |   +-- Spacing.kt
|   |   |   |
|   |   |   +-- platform/
|   |   |   |   +-- auth/
|   |   |   |   |   +-- EncryptedAuthStore.kt   # actual para AuthStore (KMP)
|   |   |   |   |
|   |   |   |   +-- push/
|   |   |   |   |   +-- FCMService.kt           # FirebaseMessagingService
|   |   |   |   |   +-- PushNotificationParser.kt
|   |   |   |   |   +-- NotificationChannels.kt # Canales por tipo
|   |   |   |   |   +-- ApprovalActionReceiver.kt # BroadcastReceiver approve/reject
|   |   |   |   |
|   |   |   |   +-- discovery/
|   |   |   |   |   +-- NsdDiscovery.kt         # NsdManager para _mcclaw._tcp
|   |   |   |   |   +-- ConnectivityMonitor.kt  # ConnectivityManager callback
|   |   |   |   |
|   |   |   |   +-- camera/
|   |   |   |       +-- QRAnalyzer.kt           # ML Kit barcode scanning
|   |   |   |
|   |   |   +-- di/
|   |   |       +-- AppModule.kt                # Koin module definitions
|   |   |
|   |   +-- res/
|   |   |   +-- values/
|   |   |   |   +-- strings.xml                 # Ingles
|   |   |   |   +-- colors.xml
|   |   |   |   +-- themes.xml
|   |   |   +-- values-es/
|   |   |   |   +-- strings.xml                 # Espanol
|   |   |   +-- drawable/                        # Iconos, assets
|   |   |   +-- mipmap-*/                        # App icon
|   |   |   +-- xml/
|   |   |       +-- backup_rules.xml
|   |   |       +-- network_security_config.xml  # Permitir ws:// solo en LAN
|   |   |
|   |   +-- AndroidManifest.xml
|   |
|   +-- src/test/                                # Unit tests
|   |   +-- java/com/mcclaw/mobile/
|   |       +-- platform/
|   |       |   +-- EncryptedAuthStoreTest.kt
|   |       |   +-- PushNotificationParserTest.kt
|   |       |   +-- NsdDiscoveryTest.kt
|   |       +-- ui/
|   |           +-- DashboardViewModelTest.kt
|   |           +-- ChatViewModelTest.kt
|   |
|   +-- src/androidTest/                         # Instrumented tests
|       +-- java/com/mcclaw/mobile/
|           +-- PairingFlowTest.kt
|           +-- ChatFlowTest.kt
|           +-- CronJobsFlowTest.kt
|
+-- build.gradle.kts                             # Project-level
+-- app/build.gradle.kts                         # App-level
+-- gradle.properties
+-- settings.gradle.kts
```

---

## 3. Integracion con KMP (Shared)

### 3.1 Configuracion Gradle

La ventaja de Android es que KMP es Kotlin nativo. No hay bridge, no hay conversion. El modulo shared se consume directamente:

```kotlin
// settings.gradle.kts
include(":shared")
project(":shared").projectDir = File("../mcclaw-mobile/shared")

// app/build.gradle.kts
dependencies {
    implementation(project(":shared"))
}
```

### 3.2 Consumo directo de ViewModels KMP

```kotlin
// DashboardScreen.kt
@Composable
fun DashboardScreen(viewModel: DashboardViewModel = koinViewModel()) {
    // DashboardViewModel es la clase Kotlin de KMP -- sin wrapper
    val connectionStatus by viewModel.connectionStatusFlow.collectAsStateWithLifecycle()
    val sessions by viewModel.sessionsFlow.collectAsStateWithLifecycle()
    val channels by viewModel.channelsFlow.collectAsStateWithLifecycle()
    val nextCronJobs by viewModel.nextCronJobsFlow.collectAsStateWithLifecycle()

    val pullRefreshState = rememberPullToRefreshState()

    PullToRefreshBox(
        isRefreshing = viewModel.isRefreshing,
        onRefresh = { viewModel.refresh() },
        state = pullRefreshState
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { ConnectionStatusCard(status = connectionStatus) }
            item { ActiveSessionsCard(sessions = sessions) }
            item { ChannelsStatusCard(channels = channels) }
            item { NextCronJobsCard(jobs = nextCronJobs) }
        }
    }
}
```

**Nota clave:** En Android no hay necesidad de wrappers ni adaptadores. Los `StateFlow` de KMP se consumen directamente con `collectAsStateWithLifecycle()`. Esto es una ventaja significativa sobre iOS donde hay que adaptar Kotlin Flow a Swift Combine/@Observable.

### 3.3 Platform Implementations (actual)

```kotlin
// EncryptedAuthStore.kt
class EncryptedAuthStore(context: Context) : AuthStoreProtocol {
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "mcclaw_auth",
        MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    override fun saveToken(token: String, deviceId: String) {
        prefs.edit().putString("token_$deviceId", token).apply()
    }

    override fun getToken(deviceId: String): String? {
        return prefs.getString("token_$deviceId", null)
    }

    override fun deleteToken(deviceId: String) {
        prefs.edit().remove("token_$deviceId").apply()
    }
}
```

---

## 4. Implementaciones de Plataforma (Detalle)

### 4.1 QR Scanner con CameraX + ML Kit

```kotlin
// QRAnalyzer.kt
class QRAnalyzer(private val onQRDetected: (String) -> Unit) : ImageAnalysis.Analyzer {
    private val scanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
    )

    override fun analyze(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image ?: return
        val inputImage = InputImage.fromMediaImage(
            mediaImage,
            imageProxy.imageInfo.rotationDegrees
        )
        scanner.process(inputImage)
            .addOnSuccessListener { barcodes ->
                barcodes.firstOrNull()?.rawValue?.let { value ->
                    onQRDetected(value)
                }
            }
            .addOnCompleteListener {
                imageProxy.close()
            }
    }
}

// QRScannerScreen.kt
@Composable
fun QRScannerScreen(onCodeScanned: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    AndroidView(
        factory = { ctx ->
            PreviewView(ctx).also { previewView ->
                val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                cameraProviderFuture.addListener({
                    val cameraProvider = cameraProviderFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val analyzer = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also { it.setAnalyzer(Executors.newSingleThreadExecutor(), QRAnalyzer(onCodeScanned)) }

                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview, analyzer
                    )
                }, ContextCompat.getMainExecutor(ctx))
            }
        },
        modifier = Modifier.fillMaxSize()
    )
}
```

### 4.2 NSD Discovery (mDNS)

```kotlin
// NsdDiscovery.kt
class NsdDiscovery(private val context: Context) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val _gateways = MutableStateFlow<List<DiscoveredGateway>>(emptyList())
    val gateways: StateFlow<List<DiscoveredGateway>> = _gateways

    private val discoveryListener = object : NsdManager.DiscoveryListener {
        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            if (serviceInfo.serviceType == "_mcclaw._tcp.") {
                nsdManager.resolveService(serviceInfo, resolveListener)
            }
        }
        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            _gateways.update { current ->
                current.filter { it.name != serviceInfo.serviceName }
            }
        }
        override fun onDiscoveryStarted(serviceType: String) {}
        override fun onDiscoveryStopped(serviceType: String) {}
        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
    }

    private val resolveListener = object : NsdManager.ResolveListener {
        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
            val gateway = DiscoveredGateway(
                host = serviceInfo.host.hostAddress ?: return,
                port = serviceInfo.port,
                name = serviceInfo.serviceName,
                version = serviceInfo.attributes["version"]?.decodeToString() ?: "3"
            )
            _gateways.update { current -> current + gateway }
        }
        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
    }

    fun startDiscovery() {
        nsdManager.discoverServices("_mcclaw._tcp", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
    }

    fun stopDiscovery() {
        try { nsdManager.stopServiceDiscovery(discoveryListener) } catch (_: Exception) {}
    }
}
```

### 4.3 FCM (Firebase Cloud Messaging)

```kotlin
// FCMService.kt
class FCMService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // Enviar nuevo token al Gateway
        CoroutineScope(Dispatchers.IO).launch {
            GatewayClient.instance.registerPushToken(token, platform = "fcm")
        }
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val data = remoteMessage.data
        val type = data["type"] ?: return

        when (type) {
            "exec.approval" -> showExecApprovalNotification(data)
            "chat.message" -> showChatNotification(data)
            "cron.completed" -> showCronNotification(data, success = true)
            "cron.failed" -> showCronNotification(data, success = false)
            "channel.alert" -> showChannelNotification(data)
            "system.health" -> showHealthNotification(data)
        }
    }

    private fun showExecApprovalNotification(data: Map<String, String>) {
        val requestId = data["requestId"] ?: return
        val command = data["command"] ?: "Unknown command"

        // Intent para aprobar
        val approveIntent = PendingIntent.getBroadcast(
            this, 0,
            Intent(this, ApprovalActionReceiver::class.java).apply {
                action = "APPROVE_EXEC"
                putExtra("requestId", requestId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent para rechazar
        val rejectIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(this, ApprovalActionReceiver::class.java).apply {
                action = "REJECT_EXEC"
                putExtra("requestId", requestId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_EXEC_APPROVAL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.exec_approval_title))
            .setContentText(command)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .addAction(R.drawable.ic_approve, getString(R.string.approve), approveIntent)
            .addAction(R.drawable.ic_reject, getString(R.string.reject), rejectIntent)
            .build()

        NotificationManagerCompat.from(this).notify(requestId.hashCode(), notification)
    }
}

// NotificationChannels.kt
object NotificationChannels {
    const val CHANNEL_EXEC_APPROVAL = "exec_approval"
    const val CHANNEL_CHAT = "chat_messages"
    const val CHANNEL_CRON = "cron_events"
    const val CHANNEL_SYSTEM = "system_health"

    fun createAll(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)

        manager.createNotificationChannels(listOf(
            NotificationChannel(CHANNEL_EXEC_APPROVAL, "Exec Approvals", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Command execution approval requests"
                setBypassDnd(true)
            },
            NotificationChannel(CHANNEL_CHAT, "Chat Messages", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Messages from AI assistants"
            },
            NotificationChannel(CHANNEL_CRON, "Scheduled Jobs", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Cron job execution notifications"
            },
            NotificationChannel(CHANNEL_SYSTEM, "System", NotificationManager.IMPORTANCE_LOW).apply {
                description = "System health and status"
            }
        ))
    }
}

// ApprovalActionReceiver.kt
class ApprovalActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val requestId = intent.getStringExtra("requestId") ?: return
        val approved = intent.action == "APPROVE_EXEC"

        CoroutineScope(Dispatchers.IO).launch {
            GatewayClient.instance.resolveExecApproval(requestId, approved)
        }

        // Cerrar la notificacion
        NotificationManagerCompat.from(context).cancel(requestId.hashCode())
    }
}
```

### 4.4 Connectivity Monitor

```kotlin
// ConnectivityMonitor.kt
class ConnectivityMonitor(context: Context) {
    private val connectivityManager = context.getSystemService(ConnectivityManager::class.java)
    private val _state = MutableStateFlow(NetworkState())
    val state: StateFlow<NetworkState> = _state

    data class NetworkState(
        val isConnected: Boolean = false,
        val isWifi: Boolean = false,
        val isCellular: Boolean = false
    )

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            _state.value = NetworkState(
                isConnected = true,
                isWifi = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                isCellular = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
            )
        }
        override fun onLost(network: Network) {
            _state.value = NetworkState(isConnected = false)
        }
    }

    fun start() {
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        connectivityManager.registerNetworkCallback(request, callback)
    }

    fun stop() {
        connectivityManager.unregisterNetworkCallback(callback)
    }
}
```

---

## 5. Navegacion y Flujo de Pantallas

### 5.1 Navigation Compose

```kotlin
// Screen.kt
sealed class Screen(val route: String) {
    data object Welcome : Screen("welcome")
    data object QRScanner : Screen("qr_scanner")
    data object PairingProgress : Screen("pairing_progress")
    data object Dashboard : Screen("dashboard")
    data object SessionList : Screen("sessions")
    data class Chat(val sessionKey: String) : Screen("chat/{sessionKey}")
    data object CronJobs : Screen("cron_jobs")
    data class CronJobDetail(val jobId: String) : Screen("cron_jobs/{jobId}")
    data object CronJobEditor : Screen("cron_jobs/editor")
    data object Channels : Screen("channels")
    data object Plugins : Screen("plugins")
    data object Canvas : Screen("canvas")
    data object Nodes : Screen("nodes")
    data object Settings : Screen("settings")
    data object Devices : Screen("settings/devices")
    data class Approval(val requestId: String) : Screen("approval/{requestId}")
}

// AppNavigation.kt
@Composable
fun AppNavigation(navController: NavHostController, isPaired: Boolean) {
    NavHost(
        navController = navController,
        startDestination = if (isPaired) "dashboard" else "welcome"
    ) {
        composable("welcome") { WelcomeScreen(navController) }
        composable("qr_scanner") { QRScannerScreen(navController) }
        composable("dashboard") { DashboardScreen(navController) }
        composable("sessions") { SessionListScreen(navController) }
        composable("chat/{sessionKey}") { backStackEntry ->
            ChatScreen(sessionKey = backStackEntry.arguments?.getString("sessionKey") ?: "")
        }
        // ... etc
    }
}
```

### 5.2 Bottom Navigation

```kotlin
// MainActivity.kt
@Composable
fun MainScreen() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    icon = { Icon(Icons.Default.Dashboard, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_dashboard)) },
                    selected = currentRoute == "dashboard",
                    onClick = { navController.navigate("dashboard") }
                )
                NavigationBarItem(
                    icon = { Icon(Icons.Default.Chat, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_chat)) },
                    selected = currentRoute == "sessions",
                    onClick = { navController.navigate("sessions") }
                )
                NavigationBarItem(
                    icon = { Icon(Icons.Default.Schedule, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_cron)) },
                    selected = currentRoute == "cron_jobs",
                    onClick = { navController.navigate("cron_jobs") }
                )
                NavigationBarItem(
                    icon = { Icon(Icons.Default.MoreHoriz, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_more)) },
                    selected = currentRoute == "more",
                    onClick = { navController.navigate("more") }
                )
            }
        }
    ) { paddingValues ->
        AppNavigation(navController, Modifier.padding(paddingValues))
    }
}
```

### 5.3 Deep Links

```xml
<!-- AndroidManifest.xml -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="mcclaw" />
</intent-filter>
```

```
mcclaw://chat/{sessionKey}          -> Abre sesion de chat
mcclaw://approval/{requestId}       -> Pantalla de aprobacion
mcclaw://cron/{jobId}               -> Detalle de cron job
mcclaw://pair?code={pairingCode}    -> Inicia emparejamiento
```

---

## 6. Sprints Android (Detalle)

### Sprint AND-1: Scaffolding y Pairing (2 semanas)

**Tareas:**

1. Crear proyecto Android Studio con estructura de carpetas
2. Configurar build.gradle.kts con dependencias (KMP shared, Compose, CameraX, ML Kit, Firebase)
3. Configurar Koin DI (AppModule.kt)
4. Crear NotificationChannels y registrar en Application.onCreate
5. Implementar WelcomeScreen (onboarding Material 3)
6. Implementar QRAnalyzer (ML Kit barcode scanning)
7. Implementar QRScannerScreen (CameraX preview + analyzer)
8. Implementar PairingProgressScreen (animacion Lottie o Compose)
9. Implementar PairingSuccessScreen (confirmacion)
10. Implementar EncryptedAuthStore (EncryptedSharedPreferences)
11. Conectar PairingService (KMP) con QRScannerScreen
12. Configurar network_security_config.xml (permitir ws:// en LAN)
13. Test: EncryptedAuthStoreTest
14. Test: QR payload parsing tests
15. Test: PairingFlowTest (instrumented, happy path)

**Entregable:** App que escanea QR y se empareja con McClaw.

**Dependencias McClaw:** Sprint MC-1 (device pairing en Gateway) debe estar listo.

---

### Sprint AND-2: Conexion y Dashboard (2 semanas)

**Tareas:**

1. Implementar NsdDiscovery (NsdManager para _mcclaw._tcp)
2. Implementar ConnectivityMonitor (ConnectivityManager callbacks)
3. Implementar AppState (StateFlow global)
4. Implementar MainActivity con Scaffold y NavigationBar
5. Implementar AppNavigation (NavHost con todas las rutas)
6. Implementar DashboardScreen con LazyColumn
7. Implementar ConnectionStatusCard (estado, latencia, modo)
8. Implementar ActiveSessionsCard (LazyRow con preview)
9. Implementar ChannelsStatusCard (FlowRow con iconos y badge)
10. Implementar NextCronJobsCard (proximos 3 jobs)
11. Implementar AgentActivityCard (actividad reciente)
12. Implementar StatusBadge (composable reutilizable)
13. Implementar PullToRefreshBox en DashboardScreen
14. Consumir DashboardViewModel (KMP) con collectAsStateWithLifecycle
15. Implementar ShimmerLoading para skeleton loading
16. Test: NsdDiscoveryTest
17. Test: DashboardViewModelTest

**Entregable:** App con dashboard funcional mostrando estado real de McClaw.

---

### Sprint AND-3: Chat Remoto (2 semanas)

**Tareas:**

1. Implementar SessionListScreen (lista con preview y badge)
2. Implementar ChatScreen (LazyColumn invertida, scroll automatico)
3. Implementar MessageBubble (user vs assistant, timestamps)
4. Implementar MarkdownText (richtext con formato)
5. Implementar CodeBlock (syntax highlighting, boton copy)
6. Implementar ChatInputBar (TextField + boton send + clip adjuntos)
7. Implementar streaming de respuestas (recomposition incremental)
8. Implementar ModelPicker (BottomSheet con providers/modelos)
9. Implementar AttachmentPicker (ActivityResultContracts para camara/galeria)
10. Implementar indicador "typing" cuando el agente trabaja
11. Implementar abort de generacion (boton stop)
12. Implementar haptic feedback (HapticFeedbackType)
13. Consumir ChatViewModel (KMP)
14. Test: MarkdownText rendering tests
15. Test: ChatFlowTest (instrumented)

**Entregable:** Chat funcional con streaming, markdown y adjuntos.

---

### Sprint AND-4: Cron Jobs (2 semanas)

**Tareas:**

1. Implementar CronJobsListScreen (filtrable: activos/pausados/todos)
2. Implementar CronJobDetailScreen (info, estado, next run, historial)
3. Implementar CronJobEditorScreen (formulario crear/editar)
4. Implementar SchedulePicker (visual: rapido vs cron expression)
5. Implementar RunHistoryScreen (lista con status chips)
6. Implementar accion "Run Now" con ConfirmDialog
7. Implementar Switch enable/disable con optimistic update
8. Implementar swipe-to-dismiss (delete, run now)
9. Consumir CronViewModel (KMP)
10. Test: SchedulePicker tests
11. Test: CronJobsFlowTest (instrumented)

**Entregable:** Gestion completa de cron jobs desde Android.

---

### Sprint AND-5: Channels, Plugins y Canvas (2 semanas)

**Tareas:**

1. Implementar ChannelsListScreen (LazyVerticalGrid con estado)
2. Implementar ChannelDetailScreen (stats, connect/disconnect)
3. Implementar PluginsListScreen (lista con Switch toggle)
4. Implementar PluginDetailScreen (info, version, config)
5. Implementar PluginInstallScreen (busqueda + instalacion)
6. Implementar CanvasGalleryScreen (LazyVerticalStaggeredGrid de snapshots)
7. Implementar CanvasDetailScreen (zoom gesture, compartir)
8. Consumir ChannelsViewModel, PluginsViewModel, CanvasViewModel (KMP)
9. Test: ChannelsListScreen tests
10. Test: PluginsListScreen tests

**Entregable:** Gestion de channels, plugins y galeria de canvas.

---

### Sprint AND-6: Push Notifications y Approvals (2 semanas)

**Tareas:**

1. Configurar Firebase project y google-services.json
2. Implementar FCMService (onNewToken, onMessageReceived)
3. Implementar PushNotificationParser (parseo por tipo)
4. Implementar ApprovalActionReceiver (BroadcastReceiver approve/reject)
5. Configurar NotificationChannel EXEC_APPROVAL con IMPORTANCE_HIGH y bypass DND
6. Implementar ApprovalBanner (banner in-app con Snackbar/Banner)
7. Implementar ApprovalDetailScreen (comando, origen, botones)
8. Implementar NotificationSettingsScreen (seleccionar tipos de push)
9. Registrar device token en Gateway
10. Implementar WorkManager para sincronizacion en background
11. Test: PushNotificationParserTest
12. Test: ApprovalActionReceiver test

**Entregable:** Push notifications funcionales con approve/reject desde notification shade.

**Dependencias McClaw:** Sprint MC-4 (PushService en Gateway) debe estar listo.

---

### Sprint AND-7: Nodos, Settings y Config Remota (1.5 semanas)

**Tareas:**

1. Implementar NodesListScreen (nodos con capacidades)
2. Implementar NodeDetailScreen (info, invoke commands)
3. Implementar SettingsScreen (hub de settings, Material 3)
4. Implementar DevicesScreen (dispositivos emparejados, revocar)
5. Implementar ConnectionSettingsScreen (LAN auto / remote URL)
6. Implementar DeepLinkHandler (mcclaw:// intent filter)
7. Consumir NodesViewModel, SettingsViewModel (KMP)
8. Test: DeepLinkHandler tests

**Entregable:** Control completo de nodos y configuracion remota.

---

### Sprint AND-8: Polish y Release (2 semanas)

**Tareas:**

1. Implementar Material 3 Dynamic Color (Material You en Android 12+)
2. Fallback a paleta McClaw en Android < 12
3. Adaptive icon con foreground/background layers
4. Splash screen API (Android 12+ SplashScreen)
5. Animaciones de transicion (shared element transitions Compose)
6. Shimmer/skeleton loading en todas las listas
7. EmptyState composables para listas vacias
8. Accessibility audit (TalkBack, content descriptions, touch targets 48dp)
9. Localizacion completa (es, en) con Compose stringResource
10. Offline mode: Room cache de ultima lectura, WorkManager cola de acciones
11. Performance profiling (Android Studio profiler: memory, CPU, battery)
12. Baseline profiles para arranque rapido
13. ProGuard/R8 rules optimizadas
14. Screenshots para Play Store (phone 6.5", tablet 10", Pixel)
15. Play Store metadata (descripcion, screenshots, categorias)
16. Subir a Internal Testing track
17. Resolver feedback de beta testers

**Entregable:** App lista para envio a Play Store.

---

## 7. Dependencias Externas Android

| Dependencia | Version | Uso |
|-------------|---------|-----|
| KMP Shared | (interna) | Protocolo, modelos, viewmodels |
| **Jetpack Compose BOM** | 2024.12+ | UI toolkit |
| **Navigation Compose** | 2.8+ | Navegacion |
| **Lifecycle** | 2.8+ | collectAsStateWithLifecycle |
| **CameraX** | 1.4+ | Preview de camara para QR |
| **ML Kit Barcode** | 17.3+ | Decodificacion QR |
| **Firebase Messaging** | 24.1+ | Push notifications |
| **AndroidX Security** | 1.1+ | EncryptedSharedPreferences |
| **Koin Android** | 3.5+ | Inyeccion de dependencias |
| **Room** | 2.6+ | Cache local offline |
| **WorkManager** | 2.9+ | Background sync |

---

## 8. Configuracion Especial

### 8.1 AndroidManifest.xml (Permisos)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />  <!-- Android 13+ -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />  <!-- NSD -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />  <!-- WorkManager -->

<uses-feature android:name="android.hardware.camera" android:required="false" />
```

### 8.2 Network Security Config

```xml
<!-- xml/network_security_config.xml -->
<network-security-config>
    <!-- Permitir ws:// cleartext solo en rangos de LAN -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">192.168.0.0/16</domain>
        <domain includeSubdomains="true">10.0.0.0/8</domain>
        <domain includeSubdomains="true">172.16.0.0/12</domain>
        <domain>localhost</domain>
    </domain-config>
    <!-- Todo lo demas requiere HTTPS/WSS -->
    <base-config cleartextTrafficPermitted="false" />
</network-security-config>
```

### 8.3 ProGuard/R8 Rules

```proguard
# KMP shared module
-keep class com.mcclaw.shared.** { *; }

# Ktor
-keep class io.ktor.** { *; }

# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep,includedescriptorclasses class com.mcclaw.shared.**$$serializer { *; }
```

---

## 9. Checklist de Calidad Pre-Release

- [ ] Todos los textos usan stringResource() -- ningun string hardcoded
- [ ] TalkBack funcional en todas las pantallas
- [ ] Touch targets de 48dp minimo
- [ ] Material 3 Dynamic Color en Android 12+, fallback en versiones anteriores
- [ ] Dark theme correcto (Material 3 auto)
- [ ] No hay memory leaks (verificado con Android Studio Profiler)
- [ ] Battery drain minimo en background (verificado con Battery Historian)
- [ ] Crash rate 0% en Internal Testing con 10+ testers durante 1 semana
- [ ] Funciona en pantallas de 5" a 10"
- [ ] Deep links funcionan correctamente
- [ ] Push notifications llegan en menos de 3 segundos
- [ ] Exec approval funciona desde notification shade
- [ ] QR pairing funciona a primera en condiciones normales de luz
- [ ] Reconexion automatica tras perdida de red
- [ ] Baseline profile generado para arranque rapido
- [ ] APK size < 15MB (sin dependencias de debug)
- [ ] Play Store screenshots generadas para phone y tablet
