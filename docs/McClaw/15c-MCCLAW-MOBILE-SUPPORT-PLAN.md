# 15c - McClaw: Plan de Soporte para Apps Moviles

## Referencia: [15-MOBILE-APPS-ARCHITECTURE.md](15-MOBILE-APPS-ARCHITECTURE.md)

---

## 1. Resumen

Este documento detalla todos los cambios necesarios en McClaw (macOS app) y en el Gateway (Node.js) para soportar las apps moviles iOS y Android. Los cambios se organizan en sprints sincronizados con los sprints de las apps moviles.

**Principio clave:** Las apps moviles son clientes del Gateway, igual que McClaw macOS. No se comunican directamente con McClaw macOS. Esto significa que la mayoria de los cambios son en el Gateway, y McClaw macOS anade la UI de gestion de dispositivos y el canal nativo mobile.

---

## 2. Estado Actual: Que Existe y Que Falta

### 2.1 RPCs Implementados (listos para mobile)

Estos RPCs ya estan implementados en `GatewayConnectionService.swift` y funcionan en el Gateway:

| Categoria | RPCs | Estado |
|-----------|------|--------|
| Status | `status`, `health` | Implementado |
| Config | `config.get`, `config.set`, `config.patch` | Implementado |
| Cron | `cron.list`, `cron.add`, `cron.remove`, `cron.update`, `cron.status`, `cron.runs`, `cron.run` | Implementado |
| Channels | `channels.status`, `channels.logout` | Implementado |
| Plugins | `plugins.list`, `plugins.install`, `plugins.uninstall`, `plugins.toggle`, `plugins.config` | Implementado |
| Security | `exec.approval.resolve` | Implementado |
| Voice | `voicewake.get`, `voicewake.set`, `talk.config`, `talk.mode` | Implementado |
| Gateway | `gateway.restart`, `gateway.update` | Implementado |

### 2.2 RPCs Documentados pero NO Implementados (necesarios para mobile)

Estos RPCs estan en la especificacion del protocolo (doc 04) pero no tienen implementacion en el codigo Swift ni confirmacion de implementacion en el Gateway:

| Categoria | RPCs | Necesario para |
|-----------|------|----------------|
| Chat | `chat.send`, `chat.history`, `chat.abort` | Chat remoto (Sprint M4) |
| Sessions | `sessions.list`, `sessions.patch`, `sessions.spawn` | Dashboard + Chat |
| Models | `models.list` | Selector de modelo |
| Devices | `device.pair.list`, `device.pair.approve`, `device.pair.reject` | Emparejamiento (Sprint M1) |
| Nodes | `node.list`, `node.describe`, `node.invoke` | Control de nodos (Sprint M8) |
| Skills | `skills.status`, `skills.install`, `skills.update` | Gestion de skills |
| Web Auth | `web.login.start`, `web.login.wait` | Posible alternativa al QR |

### 2.3 Funcionalidades Completamente Nuevas (no existen)

| Funcionalidad | Descripcion |
|---------------|-------------|
| **mDNS Advertising** | Gateway anuncia su presencia en la red local |
| **Device Pairing** | Flujo completo QR + codigo + token |
| **Push Service** | APNs + FCM desde Gateway |
| **MobileNativeService** | Canal nativo para mobile en McClaw |
| **Device Management UI** | Tab de dispositivos en Settings de McClaw |
| **Permisos Granulares** | Sistema de permisos por dispositivo |
| **Notification Queue** | Cola de mensajes pendientes |

---

## 3. Cambios en el Gateway (Node.js)

### 3.1 mDNS Advertising

**Archivo nuevo:** `gateway/src/services/mdns.js`

```javascript
// El Gateway anuncia su presencia en la red local
// para que las apps moviles lo descubran automaticamente

const mdns = require('mdns');  // o 'bonjour-service' como alternativa

class MdnsAdvertiser {
    constructor(port, instanceName) {
        this.port = port;
        this.instanceName = instanceName || 'McClaw Gateway';
        this.advertisement = null;
    }

    start() {
        this.advertisement = mdns.createAdvertisement(
            mdns.tcp('mcclaw'),
            this.port,
            {
                name: this.instanceName,
                txtRecord: {
                    version: '3',           // Protocolo v3
                    platform: process.platform,
                    features: 'chat,cron,channels,plugins,canvas,nodes'
                }
            }
        );
        this.advertisement.start();
    }

    stop() {
        if (this.advertisement) {
            this.advertisement.stop();
            this.advertisement = null;
        }
    }

    updateTxtRecord(record) {
        // Actualizar metadata sin reiniciar
        this.stop();
        this.start();
    }
}

module.exports = MdnsAdvertiser;
```

**Dependencia npm:** `mdns` o `bonjour-service` (alternativa sin compilacion nativa).

---

### 3.2 Device Pairing Service

**Archivo nuevo:** `gateway/src/services/device-pairing.js`

```javascript
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

class DevicePairingService {
    constructor(config) {
        this.secret = config.jwtSecret;
        this.pendingPairings = new Map();  // code -> { expires, deviceInfo }
        this.pairedDevices = [];            // Persistido en config
    }

    // Genera codigo de emparejamiento (invocado desde McClaw UI)
    generatePairingCode() {
        const code = [
            this.randomSegment(4),
            this.randomSegment(4),
            this.randomSegment(4)
        ].join('-');

        const expires = Date.now() + 5 * 60 * 1000;  // 5 minutos

        this.pendingPairings.set(code, {
            expires,
            deviceInfo: null,
            status: 'waiting'  // waiting -> requested -> approved/rejected
        });

        // Limpiar expirados
        setTimeout(() => this.pendingPairings.delete(code), 5 * 60 * 1000);

        return { code, expires };
    }

    // Genera datos para QR (invocado desde McClaw UI)
    generateQRPayload(localUrl, remoteUrl) {
        const { code, expires } = this.generatePairingCode();
        return {
            v: 1,
            gateway: localUrl,
            gateway_remote: remoteUrl || null,
            code,
            expires: Math.floor(expires / 1000)
        };
    }

    // App movil solicita emparejamiento con codigo
    async requestPairing(code, deviceInfo) {
        const pending = this.pendingPairings.get(code);
        if (!pending) throw new Error('Invalid or expired pairing code');
        if (Date.now() > pending.expires) {
            this.pendingPairings.delete(code);
            throw new Error('Pairing code expired');
        }
        if (pending.status !== 'waiting') throw new Error('Code already used');

        pending.deviceInfo = deviceInfo;
        pending.status = 'requested';

        // Emitir evento a McClaw UI para mostrar dialogo de aprobacion
        this.emit('pairing.requested', {
            code,
            deviceName: deviceInfo.name,
            devicePlatform: deviceInfo.platform,
            deviceId: deviceInfo.deviceId
        });

        // Esperar aprobacion/rechazo (max 60 segundos)
        return new Promise((resolve, reject) => {
            pending.resolve = resolve;
            pending.reject = reject;
            setTimeout(() => {
                if (pending.status === 'requested') {
                    pending.status = 'timeout';
                    reject(new Error('Pairing request timed out'));
                }
            }, 60000);
        });
    }

    // McClaw UI aprueba
    approvePairing(code) {
        const pending = this.pendingPairings.get(code);
        if (!pending || pending.status !== 'requested') return false;

        const device = {
            deviceId: pending.deviceInfo.deviceId,
            name: pending.deviceInfo.name,
            platform: pending.deviceInfo.platform,
            pairedAt: new Date().toISOString(),
            lastSeen: new Date().toISOString(),
            pushToken: null,
            permissions: this.defaultPermissions()
        };

        // Generar token JWT permanente para el dispositivo
        const token = jwt.sign(
            { deviceId: device.deviceId, type: 'mobile' },
            this.secret,
            { expiresIn: '365d' }
        );

        this.pairedDevices.push(device);
        this.persistDevices();

        pending.status = 'approved';
        pending.resolve({ token, device });
        this.pendingPairings.delete(code);

        return true;
    }

    // McClaw UI rechaza
    rejectPairing(code) {
        const pending = this.pendingPairings.get(code);
        if (!pending || pending.status !== 'requested') return false;

        pending.status = 'rejected';
        pending.reject(new Error('Pairing rejected by user'));
        this.pendingPairings.delete(code);

        return true;
    }

    // Listar dispositivos emparejados
    listDevices() {
        return this.pairedDevices.map(d => ({
            ...d,
            pushToken: undefined  // No exponer tokens
        }));
    }

    // Revocar acceso de dispositivo
    revokeDevice(deviceId) {
        this.pairedDevices = this.pairedDevices.filter(d => d.deviceId !== deviceId);
        this.persistDevices();
        // TODO: cerrar conexion WS activa del dispositivo
    }

    // Permisos por defecto (acceso completo)
    defaultPermissions() {
        return {
            chat: true,
            'cron.read': true,
            'cron.write': true,
            'channels.read': true,
            'channels.write': true,
            'plugins.read': true,
            'plugins.write': true,
            'exec.approve': true,
            'config.read': true,
            'config.write': false,
            'node.invoke': false
        };
    }

    // Actualizar permisos de un dispositivo
    updatePermissions(deviceId, permissions) {
        const device = this.pairedDevices.find(d => d.deviceId === deviceId);
        if (!device) return false;
        device.permissions = { ...device.permissions, ...permissions };
        this.persistDevices();
        return true;
    }

    // Registrar push token
    registerPushToken(deviceId, token, platform) {
        const device = this.pairedDevices.find(d => d.deviceId === deviceId);
        if (!device) return false;
        device.pushToken = token;
        device.pushPlatform = platform;  // 'apns' o 'fcm'
        this.persistDevices();
        return true;
    }

    // Persistencia
    persistDevices() {
        // Guardar en ~/.mcclaw/devices.json
    }

    loadDevices() {
        // Cargar desde ~/.mcclaw/devices.json
    }

    randomSegment(length) {
        return crypto.randomBytes(length).toString('hex').toUpperCase().slice(0, length);
    }
}
```

---

### 3.3 Push Notification Service

**Archivo nuevo:** `gateway/src/services/push-service.js`

```javascript
const apn = require('@parse/node-apn');
const admin = require('firebase-admin');

class PushService {
    constructor(config) {
        this.apnsProvider = null;
        this.fcmApp = null;
        this.notificationQueue = [];  // Para cuando el dispositivo no esta conectado

        if (config.apns) {
            this.apnsProvider = new apn.Provider({
                token: {
                    key: config.apns.keyPath,     // .p8 file
                    keyId: config.apns.keyId,
                    teamId: config.apns.teamId
                },
                production: config.apns.production || false
            });
        }

        if (config.fcm) {
            this.fcmApp = admin.initializeApp({
                credential: admin.credential.cert(config.fcm.serviceAccountPath)
            });
        }
    }

    // Enviar push a un dispositivo
    async sendPush(device, notification) {
        if (!device.pushToken) {
            this.notificationQueue.push({ deviceId: device.deviceId, notification, timestamp: Date.now() });
            return false;
        }

        if (device.pushPlatform === 'apns') {
            return this.sendAPNs(device.pushToken, notification);
        } else if (device.pushPlatform === 'fcm') {
            return this.sendFCM(device.pushToken, notification);
        }

        return false;
    }

    async sendAPNs(token, notification) {
        if (!this.apnsProvider) return false;

        const note = new apn.Notification();
        note.alert = { title: notification.title, body: notification.body };
        note.sound = notification.sound || 'default';
        note.topic = 'com.mcclaw.mobile';
        note.payload = notification.data || {};
        note.category = notification.category;

        if (notification.priority === 'critical') {
            note.sound = { critical: 1, name: 'default', volume: 1.0 };
        }

        const result = await this.apnsProvider.send(note, token);
        return result.sent.length > 0;
    }

    async sendFCM(token, notification) {
        if (!this.fcmApp) return false;

        const message = {
            token,
            data: notification.data || {},
            notification: {
                title: notification.title,
                body: notification.body
            },
            android: {
                priority: notification.priority === 'critical' ? 'high' : 'normal',
                notification: {
                    channelId: notification.channelId || 'chat_messages',
                    sound: 'default'
                }
            }
        };

        await admin.messaging().send(message);
        return true;
    }

    // Enviar a todos los dispositivos emparejados
    async broadcast(devices, notification) {
        const results = await Promise.allSettled(
            devices.map(device => this.sendPush(device, notification))
        );
        return results;
    }

    // Entregar notificaciones en cola cuando el dispositivo reconecta
    drainQueue(deviceId) {
        const pending = this.notificationQueue.filter(n => n.deviceId === deviceId);
        this.notificationQueue = this.notificationQueue.filter(n => n.deviceId !== deviceId);
        return pending;
    }
}
```

**Dependencias npm:**

| Paquete | Uso |
|---------|-----|
| `@parse/node-apn` | APNs (Apple Push Notifications) |
| `firebase-admin` | FCM (Firebase Cloud Messaging) |

---

### 3.4 RPCs Nuevos en el Gateway

Los siguientes handlers RPC deben implementarse o verificarse en el Gateway:

**Chat RPCs (si no existen):**

```javascript
// gateway/src/rpc/chat.js

// chat.send - Enviar mensaje a sesion
rpc.register('chat.send', async (params, context) => {
    const { sessionKey, message, attachments } = params;
    // Verificar permisos del cliente
    checkPermission(context.client, 'chat');
    // Enviar a la sesion activa del CLI
    const response = await sessionManager.send(sessionKey, message, attachments);
    return response;
});

// chat.history - Obtener historial de sesion
rpc.register('chat.history', async (params, context) => {
    const { sessionKey, limit, before } = params;
    checkPermission(context.client, 'chat');
    return sessionManager.getHistory(sessionKey, { limit, before });
});

// chat.abort - Abortar generacion activa
rpc.register('chat.abort', async (params, context) => {
    const { sessionKey } = params;
    checkPermission(context.client, 'chat');
    return sessionManager.abort(sessionKey);
});
```

**Session RPCs (si no existen):**

```javascript
// sessions.list
rpc.register('sessions.list', async (params, context) => {
    return sessionManager.listSessions();
});

// sessions.spawn
rpc.register('sessions.spawn', async (params, context) => {
    const { sessionKey, message, agentId } = params;
    checkPermission(context.client, 'chat');
    return sessionManager.spawnSubAgent(sessionKey, message, agentId);
});
```

**Models RPC:**

```javascript
// models.list
rpc.register('models.list', async (params, context) => {
    return modelManager.listAvailableModels();
});
```

**Device RPCs:**

```javascript
// device.pair.list
rpc.register('device.pair.list', async (params, context) => {
    return pairingService.listDevices();
});

// device.pair.approve
rpc.register('device.pair.approve', async (params, context) => {
    const { code } = params;
    // Solo clientes de tipo control-ui pueden aprobar
    if (context.client.type !== 'control-ui') throw new Error('Unauthorized');
    return pairingService.approvePairing(code);
});

// device.pair.reject
rpc.register('device.pair.reject', async (params, context) => {
    const { code } = params;
    if (context.client.type !== 'control-ui') throw new Error('Unauthorized');
    return pairingService.rejectPairing(code);
});

// device.pair.generate (nuevo - para generar QR)
rpc.register('device.pair.generate', async (params, context) => {
    if (context.client.type !== 'control-ui') throw new Error('Unauthorized');
    const localUrl = `ws://127.0.0.1:${config.port}`;
    const remoteUrl = config.remoteUrl || null;
    return pairingService.generateQRPayload(localUrl, remoteUrl);
});

// device.pair.revoke (nuevo - revocar acceso)
rpc.register('device.pair.revoke', async (params, context) => {
    const { deviceId } = params;
    if (context.client.type !== 'control-ui') throw new Error('Unauthorized');
    return pairingService.revokeDevice(deviceId);
});

// device.push.register (nuevo - registrar token push)
rpc.register('device.push.register', async (params, context) => {
    const { token, platform } = params;
    if (context.client.type !== 'mobile') throw new Error('Unauthorized');
    return pairingService.registerPushToken(context.client.deviceId, token, platform);
});

// device.permissions.update (nuevo)
rpc.register('device.permissions.update', async (params, context) => {
    const { deviceId, permissions } = params;
    if (context.client.type !== 'control-ui') throw new Error('Unauthorized');
    return pairingService.updatePermissions(deviceId, permissions);
});
```

### 3.5 Middleware de Autenticacion Mobile

**Archivo nuevo:** `gateway/src/middleware/mobile-auth.js`

```javascript
const jwt = require('jsonwebtoken');

function mobileAuthMiddleware(pairingService, secret) {
    return (ws, req, next) => {
        const clientType = req.headers['x-client-type'];

        if (clientType === 'mobile') {
            const auth = req.headers['authorization'];
            if (!auth || !auth.startsWith('Bearer ')) {
                ws.close(4001, 'Authentication required');
                return;
            }

            try {
                const token = auth.slice(7);
                const decoded = jwt.verify(token, secret);
                const device = pairingService.pairedDevices.find(
                    d => d.deviceId === decoded.deviceId
                );

                if (!device) {
                    ws.close(4003, 'Device not paired');
                    return;
                }

                // Adjuntar info del dispositivo al contexto
                req.mobileDevice = device;
                req.clientType = 'mobile';
                req.deviceId = decoded.deviceId;

                // Actualizar last seen
                device.lastSeen = new Date().toISOString();

            } catch (err) {
                ws.close(4001, 'Invalid token');
                return;
            }
        }

        next();
    };
}
```

### 3.6 Middleware de Permisos

```javascript
// gateway/src/middleware/permission-check.js

const PERMISSION_MAP = {
    'chat.send': 'chat',
    'chat.history': 'chat',
    'chat.abort': 'chat',
    'sessions.list': 'chat',
    'sessions.spawn': 'chat',
    'cron.list': 'cron.read',
    'cron.status': 'cron.read',
    'cron.runs': 'cron.read',
    'cron.add': 'cron.write',
    'cron.update': 'cron.write',
    'cron.remove': 'cron.write',
    'cron.run': 'cron.write',
    'channels.status': 'channels.read',
    'channels.logout': 'channels.write',
    'plugins.list': 'plugins.read',
    'plugins.config': 'plugins.read',
    'plugins.install': 'plugins.write',
    'plugins.uninstall': 'plugins.write',
    'plugins.toggle': 'plugins.write',
    'exec.approval.resolve': 'exec.approve',
    'config.get': 'config.read',
    'config.set': 'config.write',
    'config.patch': 'config.write',
    'node.list': 'config.read',
    'node.describe': 'config.read',
    'node.invoke': 'node.invoke'
};

function checkPermission(context, method) {
    // Solo aplicar a clientes mobile
    if (context.clientType !== 'mobile') return true;

    const requiredPermission = PERMISSION_MAP[method];
    if (!requiredPermission) return true;  // Metodos sin restriccion

    const device = context.mobileDevice;
    if (!device || !device.permissions[requiredPermission]) {
        throw { code: 4003, message: `Permission denied: ${requiredPermission}` };
    }

    return true;
}
```

### 3.7 Event Forwarding a Push

```javascript
// gateway/src/services/event-push-forwarder.js

class EventPushForwarder {
    constructor(pushService, pairingService, wsServer) {
        this.pushService = pushService;
        this.pairingService = pairingService;
        this.wsServer = wsServer;
    }

    // Llamar cuando ocurre un evento que debe llegar al movil
    async forwardEvent(eventType, data) {
        const devices = this.pairingService.pairedDevices;

        for (const device of devices) {
            // Si el dispositivo esta conectado via WS -> no enviar push
            if (this.wsServer.isDeviceConnected(device.deviceId)) continue;

            // Construir notificacion segun tipo
            const notification = this.buildNotification(eventType, data);
            if (notification) {
                await this.pushService.sendPush(device, notification);
            }
        }
    }

    buildNotification(eventType, data) {
        switch (eventType) {
            case 'chat.message':
                return {
                    title: 'McClaw',
                    body: this.truncate(data.content, 100),
                    data: { type: 'chat.message', sessionKey: data.sessionKey },
                    channelId: 'chat_messages',
                    priority: 'high'
                };

            case 'cron.completed':
                return {
                    title: `Job completed: ${data.jobName}`,
                    body: `Duration: ${data.duration}s`,
                    data: { type: 'cron.completed', jobId: data.jobId },
                    channelId: 'cron_events',
                    priority: 'normal'
                };

            case 'cron.failed':
                return {
                    title: `Job failed: ${data.jobName}`,
                    body: this.truncate(data.error, 100),
                    data: { type: 'cron.failed', jobId: data.jobId },
                    channelId: 'cron_events',
                    priority: 'high'
                };

            case 'exec.approval.requested':
                return {
                    title: 'Exec Approval Required',
                    body: this.truncate(data.command, 100),
                    data: {
                        type: 'exec.approval',
                        requestId: data.requestId,
                        command: data.command,
                        source: data.source
                    },
                    category: 'EXEC_APPROVAL',
                    channelId: 'exec_approval',
                    priority: 'critical'
                };

            case 'system.health':
                return {
                    title: 'McClaw System',
                    body: data.message,
                    data: { type: 'system.health' },
                    channelId: 'system_health',
                    priority: 'low'
                };

            default:
                return null;
        }
    }

    truncate(str, maxLength) {
        if (!str) return '';
        return str.length > maxLength ? str.slice(0, maxLength) + '...' : str;
    }
}
```

---

## 4. Cambios en McClaw macOS (Swift)

### 4.1 Device Pairing RPCs en GatewayConnectionService

**Archivo:** `McClaw/Sources/McClaw/Services/Gateway/GatewayConnectionService.swift`

Anadir los siguientes metodos:

```swift
// MARK: - Device Pairing

/// Generate QR payload for device pairing.
func generatePairingQR() async throws -> PairingQRPayload {
    try await call(method: "device.pair.generate")
}

/// List all paired devices.
func listPairedDevices() async throws -> [PairedDevice] {
    try await call(method: "device.pair.list")
}

/// Approve a pending pairing request.
func approvePairing(code: String) async throws -> Bool {
    try await call(method: "device.pair.approve", params: ["code": code])
}

/// Reject a pending pairing request.
func rejectPairing(code: String) async throws -> Bool {
    try await call(method: "device.pair.reject", params: ["code": code])
}

/// Revoke access for a paired device.
func revokeDevice(deviceId: String) async throws -> Bool {
    try await call(method: "device.pair.revoke", params: ["deviceId": deviceId])
}

/// Update permissions for a device.
func updateDevicePermissions(deviceId: String, permissions: DevicePermissions) async throws -> Bool {
    let encoded = try JSONEncoder().encode(permissions)
    let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    return try await call(method: "device.permissions.update", params: [
        "deviceId": deviceId,
        "permissions": dict
    ])
}
```

### 4.2 Chat/Session RPCs en GatewayConnectionService

```swift
// MARK: - Chat (para mobile y otros clientes)

/// Send a chat message to a session.
func chatSend(sessionKey: String, message: String, attachments: [[String: Any]]? = nil) async throws -> ChatSendResult {
    var params: [String: Any] = ["sessionKey": sessionKey, "message": message]
    if let attachments { params["attachments"] = attachments }
    return try await call(method: "chat.send", params: params)
}

/// Get chat history for a session.
func chatHistory(sessionKey: String, limit: Int? = nil, before: String? = nil) async throws -> [ChatMessage] {
    var params: [String: Any] = ["sessionKey": sessionKey]
    if let limit { params["limit"] = limit }
    if let before { params["before"] = before }
    return try await call(method: "chat.history", params: params)
}

/// Abort active generation in a session.
func chatAbort(sessionKey: String) async throws -> Bool {
    try await call(method: "chat.abort", params: ["sessionKey": sessionKey])
}

/// List active sessions.
func sessionsList() async throws -> [SessionInfo] {
    try await call(method: "sessions.list")
}

/// Spawn a sub-agent session.
func sessionsSpawn(sessionKey: String, message: String, agentId: String? = nil) async throws -> SessionInfo {
    var params: [String: Any] = ["sessionKey": sessionKey, "message": message]
    if let agentId { params["agentId"] = agentId }
    return try await call(method: "sessions.spawn", params: params)
}

/// List available models.
func modelsList() async throws -> [ModelInfo] {
    try await call(method: "models.list")
}
```

### 4.3 Modelos Nuevos

**Archivo nuevo:** `McClaw/Sources/McClaw/Models/Device/DeviceModels.swift`

```swift
import Foundation

/// Paired mobile device.
struct PairedDevice: Codable, Identifiable {
    let deviceId: String
    let name: String
    let platform: DevicePlatform
    let pairedAt: Date
    var lastSeen: Date
    var permissions: DevicePermissions

    var id: String { deviceId }
}

enum DevicePlatform: String, Codable {
    case ios
    case android
}

struct DevicePermissions: Codable {
    var chat: Bool = true
    var cronRead: Bool = true
    var cronWrite: Bool = true
    var channelsRead: Bool = true
    var channelsWrite: Bool = true
    var pluginsRead: Bool = true
    var pluginsWrite: Bool = true
    var execApprove: Bool = true
    var configRead: Bool = true
    var configWrite: Bool = false
    var nodeInvoke: Bool = false

    enum CodingKeys: String, CodingKey {
        case chat
        case cronRead = "cron.read"
        case cronWrite = "cron.write"
        case channelsRead = "channels.read"
        case channelsWrite = "channels.write"
        case pluginsRead = "plugins.read"
        case pluginsWrite = "plugins.write"
        case execApprove = "exec.approve"
        case configRead = "config.read"
        case configWrite = "config.write"
        case nodeInvoke = "node.invoke"
    }
}

struct PairingQRPayload: Codable {
    let v: Int
    let gateway: String
    let gatewayRemote: String?
    let code: String
    let expires: Int

    enum CodingKeys: String, CodingKey {
        case v, gateway, code, expires
        case gatewayRemote = "gateway_remote"
    }
}

struct PairingRequest: Codable {
    let code: String
    let deviceName: String
    let devicePlatform: DevicePlatform
    let deviceId: String
}
```

### 4.4 MobileNativeService

**Archivo nuevo:** `McClaw/Sources/McClaw/Services/NativeChannels/MobileNativeService.swift`

```swift
import Foundation
import Logging

/// Native channel that routes messages to/from paired mobile devices.
/// When a mobile device is connected via WebSocket, messages go directly.
/// When disconnected, messages are queued and a push notification is sent.
actor MobileNativeService: NativeChannel {
    let channelId = "mobile"
    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats: NativeChannelStats = NativeChannelStats()
    private var onMessage: (@Sendable (NativeChannelMessage) async -> String?)?
    private let logger = Logger(label: "ai.mcclaw.channel.mobile")

    func start(config: NativeChannelConfig) async {
        state = .connected
        logger.info("Mobile native channel started")
    }

    func stop() async {
        state = .disconnected
        logger.info("Mobile native channel stopped")
    }

    func setOnMessage(_ handler: @escaping @Sendable (NativeChannelMessage) async -> String?) async {
        self.onMessage = handler
    }

    /// Send a message to a mobile device.
    /// If device is connected via WS -> sends event directly.
    /// If not -> queues + push notification via Gateway.
    func sendOutbound(text: String, recipientId: String) async -> Bool {
        // Route through Gateway which handles WS delivery and push fallback
        do {
            let result: Bool = try await GatewayConnectionService.shared.call(
                method: "mobile.send",
                params: [
                    "deviceId": recipientId,
                    "text": text
                ]
            )
            if result { stats.messagesSent += 1 }
            return result
        } catch {
            logger.error("Failed to send to mobile \(recipientId): \(error)")
            return false
        }
    }

    /// Called when a message arrives from a mobile device.
    func handleIncoming(message: NativeChannelMessage) async {
        stats.messagesReceived += 1
        if let handler = onMessage {
            let _ = await handler(message)
        }
    }
}
```

### 4.5 Settings > Devices Tab

**Archivo nuevo:** `McClaw/Sources/McClaw/Views/Settings/DevicesSettingsTab.swift`

```swift
import SwiftUI

struct DevicesSettingsTab: View {
    @State private var devices: [PairedDevice] = []
    @State private var isGeneratingQR = false
    @State private var qrPayload: PairingQRPayload?
    @State private var pendingRequest: PairingRequest?
    @State private var isLoading = true

    var body: some View {
        Form {
            // Seccion QR para emparejar
            Section {
                Button(String(localized: "pair_new_device", bundle: .module)) {
                    Task { await generateQR() }
                }

                if let qrPayload {
                    QRCodeView(payload: qrPayload)
                        .frame(width: 200, height: 200)
                        .padding()
                }
            } header: {
                Text(String(localized: "pair_device_header", bundle: .module))
            }

            // Solicitud pendiente
            if let request = pendingRequest {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(request.deviceName)
                                .font(.headline)
                            Text(request.devicePlatform.rawValue.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(String(localized: "approve", bundle: .module)) {
                            Task { await approve(code: request.code) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button(String(localized: "reject", bundle: .module)) {
                            Task { await reject(code: request.code) }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                } header: {
                    Text(String(localized: "pending_request_header", bundle: .module))
                }
            }

            // Lista de dispositivos emparejados
            Section {
                if devices.isEmpty {
                    Text(String(localized: "no_devices_paired", bundle: .module))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(devices) { device in
                        DeviceRow(device: device, onRevoke: {
                            Task { await revoke(deviceId: device.deviceId) }
                        })
                    }
                }
            } header: {
                Text(String(localized: "paired_devices_header", bundle: .module))
            }
        }
        .task { await loadDevices() }
    }

    private func generateQR() async {
        isGeneratingQR = true
        do {
            qrPayload = try await GatewayConnectionService.shared.generatePairingQR()
        } catch {
            // Handle error
        }
        isGeneratingQR = false
    }

    private func loadDevices() async {
        isLoading = true
        do {
            devices = try await GatewayConnectionService.shared.listPairedDevices()
        } catch {
            // Handle error
        }
        isLoading = false
    }

    private func approve(code: String) async {
        let _ = try? await GatewayConnectionService.shared.approvePairing(code: code)
        pendingRequest = nil
        await loadDevices()
    }

    private func reject(code: String) async {
        let _ = try? await GatewayConnectionService.shared.rejectPairing(code: code)
        pendingRequest = nil
    }

    private func revoke(deviceId: String) async {
        let _ = try? await GatewayConnectionService.shared.revokeDevice(deviceId: deviceId)
        await loadDevices()
    }
}
```

### 4.6 QR Code Generator

**Archivo nuevo:** `McClaw/Sources/McClaw/Views/Settings/QRCodeView.swift`

```swift
import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let payload: PairingQRPayload

    var body: some View {
        if let image = generateQRCode() {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }

    private func generateQRCode() -> NSImage? {
        guard let data = try? JSONEncoder().encode(payload),
              let base64 = data.base64EncodedString().data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = base64
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
```

### 4.7 Event Handlers para Pairing

Anadir al manejo de eventos en `GatewayConnectionService.swift`:

```swift
// En handleEvent(_:)
case "pairing.requested":
    if let request = try? decode(PairingRequest.self, from: event.data) {
        await MainActor.run {
            // Mostrar notificacion en McClaw
            NotificationCenter.default.post(
                name: .devicePairingRequested,
                object: request
            )
        }
    }

case "device.connected":
    if let deviceInfo = try? decode(DeviceConnectionEvent.self, from: event.data) {
        await MainActor.run {
            // Actualizar UI de dispositivos
            NotificationCenter.default.post(
                name: .deviceConnectionChanged,
                object: deviceInfo
            )
        }
    }

case "device.disconnected":
    // Similar al anterior
```

### 4.8 Localization Keys

Anadir a `Localizable.strings`:

```
"pair_new_device" = "Pair New Device";
"pair_device_header" = "Pair a Mobile Device";
"approve" = "Approve";
"reject" = "Reject";
"pending_request_header" = "Pending Pairing Request";
"no_devices_paired" = "No devices paired yet. Scan the QR code from the McClaw Mobile app to pair.";
"paired_devices_header" = "Paired Devices";
"device_last_seen" = "Last seen: %@";
"device_platform_ios" = "iOS";
"device_platform_android" = "Android";
"revoke_device" = "Revoke Access";
"revoke_device_confirm" = "Are you sure you want to revoke access for %@? The device will need to pair again.";
"devices_tab_title" = "Devices";
```

---

## 5. Sprints McClaw (Detalle)

### Sprint MC-1: Device Pairing en Gateway (2 semanas)

Sincronizado con: Sprint M1 + M2 de mobile.

**Gateway (Node.js):**

1. Implementar DevicePairingService (generacion de codigo, validacion, JWT tokens)
2. Implementar RPCs: `device.pair.generate`, `device.pair.list`, `device.pair.approve`, `device.pair.reject`, `device.pair.revoke`
3. Implementar middleware de autenticacion mobile (JWT validation)
4. Implementar middleware de permisos (PERMISSION_MAP)
5. Implementar registro de tipo `mobile` en presencia
6. Implementar persistencia de dispositivos en `~/.mcclaw/devices.json`
7. Implementar mDNS advertising (`_mcclaw._tcp`)
8. Emitir evento `pairing.requested` a clientes `control-ui`
9. Tests: pairing flow, JWT validation, permission checking

**McClaw macOS (Swift):**

10. Crear DeviceModels.swift (PairedDevice, DevicePermissions, PairingQRPayload)
11. Implementar RPCs en GatewayConnectionService (generatePairingQR, listPairedDevices, approvePairing, rejectPairing, revokeDevice)
12. Implementar DevicesSettingsTab.swift (UI de gestion)
13. Implementar QRCodeView.swift (generador QR con CoreImage)
14. Anadir handler de evento `pairing.requested` en handleEvent
15. Anadir "Devices" tab en SettingsWindow
16. Localization keys en Localizable.strings
17. Tests: DeviceModels encoding/decoding

**Entregable:** Se puede generar QR desde McClaw, escanear desde mobile, aprobar, y el dispositivo queda emparejado.

---

### Sprint MC-2: Chat y Sessions RPCs (2 semanas)

Sincronizado con: Sprint M3 + M4 de mobile.

**Gateway (Node.js):**

1. Verificar/implementar `chat.send` RPC
2. Verificar/implementar `chat.history` RPC
3. Verificar/implementar `chat.abort` RPC
4. Verificar/implementar `sessions.list` RPC
5. Verificar/implementar `sessions.spawn` RPC
6. Verificar/implementar `models.list` RPC
7. Asegurar que eventos `chat.message` y `agent` se emiten a clientes `mobile`
8. Tests: chat RPCs con cliente mobile simulado

**McClaw macOS (Swift):**

9. Implementar chatSend, chatHistory, chatAbort en GatewayConnectionService
10. Implementar sessionsList, sessionsSpawn en GatewayConnectionService
11. Implementar modelsList en GatewayConnectionService
12. Tests: RPC wrappers

**Entregable:** Las apps moviles pueden enviar mensajes, ver historial, abortar generacion y listar sesiones/modelos.

---

### Sprint MC-3: Mobile Presence y Events (1 semana)

Sincronizado con: Sprint M3 de mobile.

**Gateway (Node.js):**

1. Trackear dispositivos mobile conectados via WS
2. Emitir `device.connected` / `device.disconnected` a clientes `control-ui`
3. Actualizar `lastSeen` en PairingService al conectar/desconectar
4. Incluir dispositivos mobile en respuesta de `status` RPC
5. Enviar eventos de health, presence, channels, cron a clientes mobile
6. Tests: presence tracking

**McClaw macOS (Swift):**

7. Manejar eventos `device.connected` / `device.disconnected`
8. Mostrar indicador en Devices tab (online/offline dot)
9. Badge en menu bar cuando hay dispositivos conectados (opcional)

**Entregable:** McClaw muestra que dispositivos estan conectados en tiempo real.

---

### Sprint MC-4: Push Notifications (2 semanas)

Sincronizado con: Sprint M7 de mobile.

**Gateway (Node.js):**

1. Implementar PushService (APNs + FCM adapters)
2. Implementar RPC `device.push.register` para registrar tokens
3. Implementar EventPushForwarder (reenvio de eventos a push)
4. Implementar NotificationQueue para mensajes pendientes
5. Implementar drain de cola al reconectar dispositivo
6. Configuracion de APNs key (.p8) y FCM service account en config
7. Enviar push para: chat.message, cron.completed, cron.failed, exec.approval.requested
8. Tests: push building, queue drain

**McClaw macOS (Swift):**

9. Implementar MobileNativeService (NativeChannel)
10. Registrar MobileNativeService en NativeChannelsManager
11. Anadir canal "mobile" en la UI de channels
12. Tests: MobileNativeService

**Dependencias externas:**
- Apple Developer Program: crear APNs key (.p8)
- Firebase project: crear service account para FCM

**Entregable:** Las apps reciben push notifications cuando no estan conectadas via WS.

---

### Sprint MC-5: Permisos Granulares y Polish (1 semana)

Sincronizado con: Sprint M9 de mobile.

**Gateway (Node.js):**

1. Implementar RPC `device.permissions.update`
2. Aplicar permission check en todos los RPCs
3. Log de accesos denegados para debugging
4. Tests: permission enforcement

**McClaw macOS (Swift):**

5. Implementar UI de permisos por dispositivo (checkboxes en DeviceDetailView)
6. Implementar updateDevicePermissions en GatewayConnectionService
7. Tests: permisos UI

**Entregable:** Se pueden configurar permisos granulares por dispositivo desde McClaw.

---

## 6. Resumen de Archivos por Sprint

### Sprint MC-1 (Nuevos)

**Gateway:**
- `gateway/src/services/mdns.js`
- `gateway/src/services/device-pairing.js`
- `gateway/src/middleware/mobile-auth.js`
- `gateway/src/middleware/permission-check.js`
- `gateway/src/rpc/device.js`

**McClaw macOS:**
- `McClaw/Sources/McClaw/Models/Device/DeviceModels.swift`
- `McClaw/Sources/McClaw/Views/Settings/DevicesSettingsTab.swift`
- `McClaw/Sources/McClaw/Views/Settings/QRCodeView.swift`
- `McClaw/Sources/McClawKit/DeviceKit.swift` (pure logic: QR encoding, permission defaults)
- `McClaw/Tests/McClawKitTests/DeviceKitTests.swift`

**Modificados:**
- `GatewayConnectionService.swift` (nuevos RPCs + event handlers)
- `SettingsWindow.swift` (nueva tab Devices)
- `Localizable.strings` (nuevas keys)

### Sprint MC-2 (Nuevos)

**Gateway:**
- `gateway/src/rpc/chat.js` (si no existe)
- `gateway/src/rpc/sessions.js` (si no existe)
- `gateway/src/rpc/models.js` (si no existe)

**McClaw macOS:**
- Modificar `GatewayConnectionService.swift` (nuevos RPCs chat/sessions/models)

### Sprint MC-3 (Modificados)

**Gateway:**
- Modificar WebSocket server (tracking mobile presence)
- Modificar status RPC (incluir mobile devices)

**McClaw macOS:**
- Modificar `DevicesSettingsTab.swift` (indicador online)
- Modificar event handler en `GatewayConnectionService.swift`

### Sprint MC-4 (Nuevos)

**Gateway:**
- `gateway/src/services/push-service.js`
- `gateway/src/services/event-push-forwarder.js`
- `gateway/src/rpc/device-push.js`

**McClaw macOS:**
- `McClaw/Sources/McClaw/Services/NativeChannels/MobileNativeService.swift`

### Sprint MC-5 (Modificados)

**Gateway:**
- Modificar permission middleware (enforcement)

**McClaw macOS:**
- Nueva DeviceDetailView con permission checkboxes

---

## 7. Timeline de Sincronizacion

```
Semana  | Mobile (iOS + Android)      | McClaw / Gateway
--------|-----------------------------|--------------------------
1-2     | M1: KMP shared, protocolo   | MC-1: Device pairing
3-4     | M2: Pairing, QR, discovery  | MC-1: continua (QR, UI)
5-6     | M3: Dashboard               | MC-2: Chat/Session RPCs
7-8     | M4: Chat remoto             | MC-2: continua + MC-3
9-10    | M5: Cron jobs               | (sin cambios McClaw)
11-12   | M6: Channels + Plugins      | (sin cambios McClaw)
13-14   | M7: Push notifications      | MC-4: PushService
15-16   | M8: Canvas, Nodos, Config   | (sin cambios McClaw)
17      | M9: Exec approvals          | MC-5: Permisos granulares
18-19   | M10: Polish + Release       | Soporte + bugfixes
```

**Nota:** Los sprints McClaw son mas cortos porque aprovechan la infraestructura existente. El grueso del trabajo es en el Gateway (Node.js) y las apps moviles.

---

## 8. Tests McClaw

### Tests Unitarios (McClawKit)

| Test File | Tests | Cobertura |
|-----------|-------|-----------|
| DeviceKitTests.swift | 20+ | QR encoding/decoding, permission defaults, device model validation |

### Tests de Integracion

| Area | Metodo | Que verifica |
|------|--------|--------------|
| Pairing | Manual + automatizado | QR genera, mobile escanea, McClaw aprueba, token funciona |
| Chat via mobile | Automatizado | Mobile envia mensaje, CLI responde, mobile recibe streaming |
| Push notifications | Manual | Evento -> push llega en < 3s al dispositivo |
| Permisos | Automatizado | RPC rechazado si el dispositivo no tiene permiso |
| Reconexion | Manual | Mobile pierde red, reconecta, recibe mensajes pendientes |

---

## 9. Configuracion Push (Prerequisitos)

### APNs (iOS)

1. En Apple Developer Portal: crear APNs Key (.p8)
2. Anotar: Key ID, Team ID
3. Guardar .p8 en `~/.mcclaw/push/apns-key.p8`
4. Configurar en `~/.mcclaw/mcclaw.json`:

```json
{
  "push": {
    "apns": {
      "keyPath": "~/.mcclaw/push/apns-key.p8",
      "keyId": "ABCDE12345",
      "teamId": "TEAM123456",
      "production": false
    }
  }
}
```

### FCM (Android)

1. En Firebase Console: crear proyecto + app Android
2. Generar service account JSON
3. Guardar en `~/.mcclaw/push/firebase-service-account.json`
4. Configurar en `~/.mcclaw/mcclaw.json`:

```json
{
  "push": {
    "fcm": {
      "serviceAccountPath": "~/.mcclaw/push/firebase-service-account.json"
    }
  }
}
```

**Nota:** Push notifications son opcionales. Si no se configuran, los mensajes se entregan solo via WebSocket (cuando la app esta activa). La app funcionara perfectamente sin push, pero no recibira notificaciones en background.
