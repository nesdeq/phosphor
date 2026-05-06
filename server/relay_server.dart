// PHOSPHOR Relay Server
// Secure WebSocket relay for multiplayer terminal sessions.
// All terminal data is end-to-end encrypted — the server routes opaque ciphertext.
//
// Usage:
//   dart run server/relay_server.dart --cert public.pem --key private.pem
//   dart run server/relay_server.dart --cert public.pem --key private.pem --port 9000

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// --- Limits ---

const _maxSessions = 100;
const _maxPeersPerSession = 10;
const _idleTimeoutMinutes = 5;
const _authTimeoutSeconds = 10;
const _maxMessagesPerSecond = 100;
const _maxSessionsPerIp = 3;
const _maxConnectionsPerIp = 10;
const _maxMessageBytes = 65536; // 64 KB

// --- Data Model ---

class Session {
  final String code;
  final WebSocket host;
  final String hostId;
  final String hostIp;
  final Map<String, Peer> peers = {};
  DateTime lastActivity;

  Session(this.code, this.host, this.hostId, this.hostIp)
      : lastActivity = DateTime.now();

  void touch() => lastActivity = DateTime.now();

  List<WebSocket> get allSockets => [
        host,
        ...peers.values.map((p) => p.socket),
      ];
}

class Peer {
  final String id;
  final WebSocket socket;
  String name;
  String role; // 'viewer' or 'editor'

  Peer(this.id, this.socket, {required this.name, this.role = 'viewer'});
}

// --- Server State ---

final _sessions = <String, Session>{};
int _clientCounter = 0;

String _generateClientId() {
  _clientCounter++;
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
  return '${ts}_$_clientCounter';
}

final _rateLimiters = <WebSocket, _RateState>{};
final _connectionsPerIp = <String, int>{};

class _RateState {
  int count = 0;
  DateTime window = DateTime.now();

  bool check() {
    final now = DateTime.now();
    if (now.difference(window).inSeconds >= 1) {
      count = 0;
      window = now;
    }
    count++;
    return count <= _maxMessagesPerSecond;
  }
}

// --- Main ---

void main(List<String> args) async {
  int port = 8766;
  String? certPath;
  String? keyPath;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--port':
        port = int.parse(args[++i]);
      case '--cert':
        certPath = args[++i];
      case '--key':
        keyPath = args[++i];
    }
  }

  if (certPath == null || keyPath == null) {
    stderr.writeln(
      'Usage: dart run server/relay_server.dart '
      '--cert <cert.pem> --key <key.pem> [--port $port]',
    );
    exit(1);
  }
  final ctx = SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);
  final server = await HttpServer.bindSecure('0.0.0.0', port, ctx);
  print('PHOSPHOR Relay on wss://0.0.0.0:$port');

  // Periodic idle-session cleanup
  Timer.periodic(const Duration(minutes: 1), (_) => _cleanupIdle());

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';

      // Per-IP connection limit
      final current = _connectionsPerIp[ip] ?? 0;
      if (current >= _maxConnectionsPerIp) {
        request.response
          ..statusCode = 429
          ..write('Too many connections');
        unawaited(request.response.close());
        continue;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      _connectionsPerIp[ip] = current + 1;
      _handleConnection(socket, ip);
    } else {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'service': 'PHOSPHOR Relay',
          'sessions': _sessions.length,
        }));
      unawaited(request.response.close());
    }
  }
}

// --- Connection Lifecycle ---

void _handleConnection(WebSocket socket, String ip) {
  final clientId = _generateClientId();
  _rateLimiters[socket] = _RateState();

  void cleanup() {
    _rateLimiters.remove(socket);
    final c = _connectionsPerIp[ip];
    if (c != null) {
      if (c <= 1) {
        _connectionsPerIp.remove(ip);
      } else {
        _connectionsPerIp[ip] = c - 1;
      }
    }
    _handleDisconnect(clientId, socket);
  }

  // Must authenticate (host/join) within timeout
  bool authenticated = false;
  final authTimer = Timer(const Duration(seconds: _authTimeoutSeconds), () {
    if (!authenticated) {
      _sendJson(socket, {'type': 'error', 'message': 'Auth timeout'});
      socket.close();
    }
  });

  // Keepalive ping every 30s
  final pingTimer = Timer.periodic(
    const Duration(seconds: 30),
    (_) {
      try {
        socket.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    },
  );

  socket.listen(
    (data) {
      if (!_rateLimiters[socket]!.check()) {
        _sendJson(socket, {'type': 'error', 'message': 'Rate limit exceeded'});
        return;
      }

      // Message size limit
      if (data is String && data.length > _maxMessageBytes) {
        _sendJson(socket, {'type': 'error', 'message': 'Message too large'});
        return;
      }

      try {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        final type = msg['type'] as String;

        if (!authenticated &&
            type != 'host' &&
            type != 'join' &&
            type != 'pong') {
          _sendJson(socket, {'type': 'error', 'message': 'Not authenticated'});
          return;
        }
        if (type == 'host' || type == 'join') {
          authenticated = true;
          authTimer.cancel();
        }

        _handleMessage(clientId, socket, ip, msg, data);
      } catch (e) {
        print('[$clientId] Error: $e');
      }
    },
    onDone: () {
      authTimer.cancel();
      pingTimer.cancel();
      cleanup();
    },
    onError: (e) {
      authTimer.cancel();
      pingTimer.cancel();
      cleanup();
    },
  );
}

// --- Message Routing ---

void _handleMessage(
  String clientId,
  WebSocket socket,
  String ip,
  Map<String, dynamic> msg,
  String raw,
) {
  switch (msg['type'] as String) {
    case 'host':
      _onHost(clientId, socket, ip, msg);
    case 'join':
      _onJoin(clientId, socket, msg);
    case 'leave':
      _handleDisconnect(clientId, socket);
    case 'role':
      _onRole(clientId, socket, msg);
    case 'kick':
      _onKick(clientId, socket, msg);
    case 'encrypted':
      _onEncrypted(clientId, socket, msg, raw);
    case 'pong' || 'ping':
      if (msg['type'] == 'ping') _sendJson(socket, {'type': 'pong'});
  }
}

void _onHost(
    String clientId, WebSocket socket, String ip, Map<String, dynamic> msg) {
  final code = msg['code'] as String;

  if (_sessions.containsKey(code)) {
    _sendJson(socket, {'type': 'error', 'message': 'Code already in use'});
    return;
  }
  if (_sessions.length >= _maxSessions) {
    _sendJson(socket, {'type': 'error', 'message': 'Server at capacity'});
    return;
  }

  // Per-IP session limit
  final ipSessions = _sessions.values.where((s) => s.hostIp == ip).length;
  if (ipSessions >= _maxSessionsPerIp) {
    _sendJson(
        socket, {'type': 'error', 'message': 'Too many sessions from this IP'});
    return;
  }

  _sessions[code] = Session(code, socket, clientId, ip);
  _sendJson(socket, {'type': 'hosted', 'code': code});
  print('[$clientId] Hosted session $code');
}

void _onJoin(String clientId, WebSocket socket, Map<String, dynamic> msg) {
  final code = msg['code'] as String;
  final session = _sessions[code];

  if (session == null) {
    _sendJson(socket, {'type': 'error', 'message': 'Session not found'});
    return;
  }
  if (session.peers.length >= _maxPeersPerSession) {
    _sendJson(socket, {'type': 'error', 'message': 'Session is full'});
    return;
  }

  final name = 'Peer-${clientId.substring(clientId.length - 4)}';
  session.peers[clientId] = Peer(clientId, socket, name: name);
  session.touch();

  _sendJson(socket, {'type': 'joined', 'peerId': clientId, 'role': 'viewer'});
  _sendJson(session.host, {
    'type': 'peer_joined',
    'peerId': clientId,
    'name': name,
  });

  for (final p in session.peers.values) {
    if (p.id != clientId) {
      _sendJson(p.socket, {
        'type': 'peer_joined',
        'peerId': clientId,
        'name': name,
      });
    }
  }
  print('[$clientId] Joined session $code');
}

void _onRole(String clientId, WebSocket socket, Map<String, dynamic> msg) {
  final targetId = msg['target'] as String;
  final newRole = msg['role'] as String;
  if (newRole != 'viewer' && newRole != 'editor') return;

  for (final session in _sessions.values) {
    if (session.hostId != clientId) continue;
    final peer = session.peers[targetId];
    if (peer == null) return;

    peer.role = newRole;
    _sendJson(peer.socket, {'type': 'role_changed', 'role': newRole});
    _sendJson(socket, {
      'type': 'role_changed',
      'peerId': targetId,
      'role': newRole,
    });
    session.touch();
    return;
  }
}

void _onKick(String clientId, WebSocket socket, Map<String, dynamic> msg) {
  final targetId = msg['target'] as String;

  for (final session in _sessions.values) {
    if (session.hostId != clientId) continue;
    final peer = session.peers.remove(targetId);
    if (peer == null) return;

    _sendJson(peer.socket, {'type': 'kicked'});
    peer.socket.close();

    // Notify remaining
    _sendJson(session.host, {'type': 'peer_left', 'peerId': targetId});
    for (final p in session.peers.values) {
      _sendJson(p.socket, {'type': 'peer_left', 'peerId': targetId});
    }
    session.touch();
    print('[$targetId] Kicked from ${session.code}');
    return;
  }
}

void _onEncrypted(
  String clientId,
  WebSocket socket,
  Map<String, dynamic> msg,
  String raw,
) {
  final sessionCode = msg['sessionCode'] as String;
  final msgType = msg['msgType'] as String;
  final session = _sessions[sessionCode];
  if (session == null) return;
  session.touch();

  switch (msgType) {
    case 'output' || 'resize':
      // Host -> all peers
      if (socket == session.host) {
        for (final peer in session.peers.values) {
          _trySend(peer.socket, raw);
        }
      }
    case 'input':
      // Editor peer -> host
      final peer = session.peers[clientId];
      if (peer != null && peer.role == 'editor') {
        _trySend(session.host, raw);
      }
    case 'cursor':
      // Any -> all others
      for (final target in session.allSockets) {
        if (target != socket) _trySend(target, raw);
      }
  }
}

// --- Disconnect / Cleanup ---

void _handleDisconnect(String clientId, WebSocket socket) {
  _sessions.removeWhere((code, session) {
    if (session.host == socket) {
      for (final peer in session.peers.values) {
        _sendJson(peer.socket, {
          'type': 'session_ended',
          'reason': 'host_left',
        });
      }
      print('Session $code ended (host left)');
      return true;
    }

    final peer = session.peers.remove(clientId);
    if (peer != null) {
      _sendJson(session.host, {'type': 'peer_left', 'peerId': clientId});
      for (final p in session.peers.values) {
        _sendJson(p.socket, {'type': 'peer_left', 'peerId': clientId});
      }
      session.touch();
      print('[$clientId] Left session $code');
    }
    return false;
  });
}

void _cleanupIdle() {
  final now = DateTime.now();
  _sessions.removeWhere((code, session) {
    if (now.difference(session.lastActivity).inMinutes < _idleTimeoutMinutes) {
      return false;
    }
    for (final target in session.allSockets) {
      _sendJson(target, {'type': 'session_ended', 'reason': 'timeout'});
    }
    print('Session $code timed out');
    return true;
  });
}

// --- Helpers ---

void _sendJson(WebSocket socket, Map<String, dynamic> data) {
  _trySend(socket, jsonEncode(data));
}

void _trySend(WebSocket socket, String data) {
  try {
    socket.add(data);
  } catch (_) {}
}
