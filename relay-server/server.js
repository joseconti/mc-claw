/**
 * McClaw Relay Server
 *
 * Lightweight WebSocket relay that connects McClaw (Mac) with mobile devices
 * when they're on different networks. The relay only forwards frames —
 * it never reads, stores, or processes message content.
 *
 * Architecture:
 *   iPhone (4G) ──wss://──► Relay ◄──wss://── McClaw Mac (home)
 *
 * Flow:
 *   1. McClaw Mac connects as "host" with a relay token
 *   2. Relay assigns the Mac to a room (derived from token)
 *   3. Mobile connects as "device" with the same relay token
 *   4. Relay pairs them and forwards all WebSocket frames bidirectionally
 *
 * Self-hosted: anyone can run this on their own VPS.
 * McClaw Cloud: hosted at relay.joseconti.com (subscription required).
 */

const http = require('http');
const express = require('express');
const { WebSocketServer } = require('ws');
const helmet = require('helmet');
const crypto = require('crypto');
const { RateLimiterMemory } = require('rate-limiter-flexible');

// =============================================================================
// Configuration
// =============================================================================

const PORT = parseInt(process.env.PORT || '8443', 10);
const MAX_ROOMS = parseInt(process.env.MAX_ROOMS || '1000', 10);
const RELAY_JWT_SECRET = process.env.RELAY_JWT_SECRET || '';  // JWT secret shared with api.joseconti.com
const PING_INTERVAL = 30000;  // 30s keepalive
const ROOM_TIMEOUT = 3600000; // 1h max room lifetime

// =============================================================================
// Rate Limiter
// =============================================================================

const rateLimiter = new RateLimiterMemory({
    points: 10,      // 10 connections
    duration: 60,    // per 60 seconds per IP
});

// =============================================================================
// Room Management
// =============================================================================

/** @type {Map<string, Room>} */
const rooms = new Map();

class Room {
    constructor(roomId) {
        this.id = roomId;
        this.host = null;      // McClaw Mac WebSocket
        this.devices = new Map(); // deviceId -> WebSocket
        this.createdAt = Date.now();
        this.lastActivity = Date.now();
    }

    setHost(ws) {
        this.host = ws;
        this.lastActivity = Date.now();
    }

    addDevice(deviceId, ws) {
        this.devices.set(deviceId, ws);
        this.lastActivity = Date.now();
        // Notify host that a device connected
        if (this.host && this.host.readyState === 1) {
            this.host.send(JSON.stringify({
                type: 'relay.device.connected',
                deviceId,
                timestamp: new Date().toISOString(),
            }));
        }
    }

    removeDevice(deviceId) {
        this.devices.delete(deviceId);
        // Notify host
        if (this.host && this.host.readyState === 1) {
            this.host.send(JSON.stringify({
                type: 'relay.device.disconnected',
                deviceId,
                timestamp: new Date().toISOString(),
            }));
        }
    }

    removeHost() {
        this.host = null;
        // Notify all devices
        for (const [, ws] of this.devices) {
            if (ws.readyState === 1) {
                ws.send(JSON.stringify({
                    type: 'relay.host.disconnected',
                    timestamp: new Date().toISOString(),
                }));
            }
        }
    }

    forwardToHost(data) {
        if (this.host && this.host.readyState === 1) {
            this.host.send(data);
            this.lastActivity = Date.now();
        }
    }

    forwardToDevice(deviceId, data) {
        const ws = this.devices.get(deviceId);
        if (ws && ws.readyState === 1) {
            ws.send(data);
            this.lastActivity = Date.now();
        }
    }

    broadcastToDevices(data, excludeDeviceId) {
        for (const [id, ws] of this.devices) {
            if (id !== excludeDeviceId && ws.readyState === 1) {
                ws.send(data);
            }
        }
        this.lastActivity = Date.now();
    }

    isEmpty() {
        return !this.host && this.devices.size === 0;
    }

    isExpired() {
        return Date.now() - this.createdAt > ROOM_TIMEOUT;
    }

    get deviceCount() {
        return this.devices.size;
    }
}

// =============================================================================
// Room helpers
// =============================================================================

/**
 * Derive a room ID from a relay token.
 * The token is never stored — we only use its hash as room key.
 */
function tokenToRoomId(token) {
    return crypto.createHash('sha256').update(token).digest('hex').slice(0, 16);
}

function getOrCreateRoom(roomId) {
    if (rooms.has(roomId)) return rooms.get(roomId);
    if (rooms.size >= MAX_ROOMS) {
        throw new Error('Maximum rooms reached');
    }
    const room = new Room(roomId);
    rooms.set(roomId, room);
    return room;
}

function cleanupRoom(roomId) {
    const room = rooms.get(roomId);
    if (room && room.isEmpty()) {
        rooms.delete(roomId);
    }
}

// =============================================================================
// Express + HTTP server
// =============================================================================

const app = express();
app.use(helmet());

// Health check endpoint
app.get('/v1/health', (req, res) => {
    res.json({
        status: 'ok',
        rooms: rooms.size,
        uptime: Math.floor(process.uptime()),
        version: '1.0.0',
    });
});

// Stats endpoint (optional, can be disabled)
app.get('/v1/stats', (_req, res) => {
    let totalDevices = 0;
    let activeRooms = 0;
    for (const [, room] of rooms) {
        if (room.host || room.devices.size > 0) {
            activeRooms++;
            totalDevices += room.devices.size;
        }
    }
    res.json({
        activeRooms,
        totalDevices,
        maxRooms: MAX_ROOMS,
        uptime: Math.floor(process.uptime()),
    });
});

const server = http.createServer(app);

// =============================================================================
// WebSocket Server
// =============================================================================

const wss = new WebSocketServer({ server, path: '/v1/relay' });

wss.on('connection', async (ws, req) => {
    const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress;

    // Rate limit
    try {
        await rateLimiter.consume(ip);
    } catch {
        ws.close(4029, 'Too many connections');
        return;
    }

    // Parse headers
    const relayToken = req.headers['x-relay-token'];
    const clientType = req.headers['x-client-type'];  // 'host' or 'device'
    const deviceId = req.headers['x-device-id'];

    if (!relayToken || !clientType) {
        ws.close(4001, 'Missing x-relay-token or x-client-type header');
        return;
    }

    // Validate JWT for McClaw Cloud (skip if no secret = self-hosted open mode)
    if (RELAY_JWT_SECRET) {
        const authHeader = req.headers['authorization'];
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            ws.close(4003, 'Missing Authorization header');
            return;
        }
        const token = authHeader.slice(7);
        const payload = verifyJWT(token, RELAY_JWT_SECRET);
        if (!payload) {
            ws.close(4003, 'Invalid or expired token');
            return;
        }
        // Attach license info to the socket for logging
        ws.licenseId = payload.sub;
    }

    const roomId = tokenToRoomId(relayToken);
    let room;

    try {
        room = getOrCreateRoom(roomId);
    } catch (err) {
        ws.close(4029, err.message);
        return;
    }

    // Register connection
    if (clientType === 'host') {
        if (room.host && room.host.readyState === 1) {
            // Another host is already connected — reject
            ws.close(4009, 'Host already connected');
            return;
        }
        room.setHost(ws);
        ws.send(JSON.stringify({
            type: 'relay.connected',
            role: 'host',
            roomId,
            connectedDevices: room.deviceCount,
        }));
    } else if (clientType === 'device') {
        if (!deviceId) {
            ws.close(4001, 'Missing x-device-id header for device');
            return;
        }
        room.addDevice(deviceId, ws);
        ws.send(JSON.stringify({
            type: 'relay.connected',
            role: 'device',
            roomId,
            hostOnline: room.host !== null,
        }));
    } else {
        ws.close(4001, 'x-client-type must be "host" or "device"');
        return;
    }

    // Keepalive
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    // Message forwarding
    ws.on('message', (data, isBinary) => {
        const raw = isBinary ? data : data.toString();

        if (clientType === 'host') {
            // Host -> try to parse target deviceId, or broadcast
            try {
                const parsed = JSON.parse(raw);
                if (parsed.targetDeviceId) {
                    room.forwardToDevice(parsed.targetDeviceId, raw);
                } else {
                    room.broadcastToDevices(raw);
                }
            } catch {
                // Binary or unparseable — broadcast to all devices
                room.broadcastToDevices(raw);
            }
        } else if (clientType === 'device') {
            // Device -> forward to host
            room.forwardToHost(raw);
        }
    });

    // Cleanup on close
    ws.on('close', () => {
        if (clientType === 'host') {
            room.removeHost();
        } else if (clientType === 'device' && deviceId) {
            room.removeDevice(deviceId);
        }
        cleanupRoom(roomId);
    });

    ws.on('error', () => {
        ws.close();
    });
});

// =============================================================================
// Keepalive ping + room cleanup
// =============================================================================

const pingInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
            ws.terminate();
            return;
        }
        ws.isAlive = false;
        ws.ping();
    });

    // Cleanup expired rooms
    for (const [id, room] of rooms) {
        if (room.isExpired() || room.isEmpty()) {
            if (room.host) room.host.close(4008, 'Room expired');
            for (const [, ws] of room.devices) ws.close(4008, 'Room expired');
            rooms.delete(id);
        }
    }
}, PING_INTERVAL);

wss.on('close', () => clearInterval(pingInterval));

// =============================================================================
// JWT Verification (HMAC-SHA256, no external library)
// =============================================================================

/**
 * Verify a JWT signed with HMAC-SHA256.
 * Returns the decoded payload if valid, or null if invalid/expired.
 */
function verifyJWT(token, secret) {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const [headerB64, payloadB64, signatureB64] = parts;

    // Verify signature
    const expected = crypto
        .createHmac('sha256', secret)
        .update(`${headerB64}.${payloadB64}`)
        .digest('base64url');

    if (expected !== signatureB64) return null;

    // Decode payload
    try {
        const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString());

        // Check expiration
        if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
            return null;
        }

        // Check audience (optional, for extra safety)
        if (payload.aud && payload.aud !== 'relay.joseconti.com') {
            return null;
        }

        return payload;
    } catch {
        return null;
    }
}

// =============================================================================
// Start
// =============================================================================

server.listen(PORT, () => {
    console.log(`McClaw Relay Server running on port ${PORT}`);
    console.log(`Health: http://localhost:${PORT}/v1/health`);
    console.log(`WebSocket: ws://localhost:${PORT}/v1/relay`);
    if (AUTH_SECRET) {
        console.log('Auth: RELAY_SECRET is set — Bearer token required');
    } else {
        console.log('Auth: Open mode (no RELAY_SECRET set)');
    }
});
