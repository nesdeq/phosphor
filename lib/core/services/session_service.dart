import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../app/theme/crt_colors.dart';
import 'crypto_service.dart';
import 'user_environment.dart';

/// Roles in a shared session.
enum SessionRole {
  host,
  editor,
  viewer;

  /// Single-character tag for compact UI badges (overlay, list rows).
  String get shortLabel => switch (this) {
        SessionRole.host => 'H',
        SessionRole.editor => 'E',
        SessionRole.viewer => 'V',
      };

  /// Full uppercase label for verbose role pills.
  String get label => name.toUpperCase();

  static SessionRole parse(String s) => switch (s) {
        'editor' => SessionRole.editor,
        'host' => SessionRole.host,
        _ => SessionRole.viewer,
      };
}

/// A participant in a shared session.
class Participant {
  final String id;
  final String name;
  final SessionRole role;
  const Participant({
    required this.id,
    required this.name,
    required this.role,
  });

  Participant copyWith({SessionRole? role}) {
    return Participant(
      id: id,
      name: name,
      role: role ?? this.role,
    );
  }
}

/// State for a multiplayer session.
class SessionState {
  final bool isActive;
  final bool isHost;
  final String? sessionCode;
  final List<Participant> participants;

  /// Last error or status message — passed through to copyWith without
  /// `??=` semantics so callers can clear it by passing `error: null`.
  final String? error;

  final bool connecting;
  final String? selfId;

  const SessionState({
    this.isActive = false,
    this.isHost = false,
    this.sessionCode,
    this.participants = const [],
    this.error,
    this.connecting = false,
    this.selfId,
  });

  SessionState copyWith({
    bool? isActive,
    bool? isHost,
    String? sessionCode,
    List<Participant>? participants,
    String? error,
    bool? connecting,
    String? selfId,
  }) {
    return SessionState(
      isActive: isActive ?? this.isActive,
      isHost: isHost ?? this.isHost,
      sessionCode: sessionCode ?? this.sessionCode,
      participants: participants ?? this.participants,
      error: error,
      connecting: connecting ?? this.connecting,
      selfId: selfId ?? this.selfId,
    );
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

class SessionNotifier extends Notifier<SessionState> {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  final _random = Random.secure();
  final _crypto = CryptoService();
  String? _routingCode;

  /// Peer display terminal — created when joining as non-host.
  /// Receives decrypted output from the host. Input goes through [sendInput].
  Terminal? peerTerminal;

  /// Stream of decrypted peer input received by the host. The terminal
  /// session subscribes to write into the PTY. Replaces the previous
  /// public-mutable callback.
  final _peerInputController = StreamController<String>.broadcast();
  Stream<String> get peerInputStream => _peerInputController.stream;

  /// Last broadcast terminal dimensions — re-sent when a new peer joins so
  /// they don't render the stream at the hardcoded 80×24 default.
  int? _lastCols;
  int? _lastRows;

  /// Pinned server cert DER bytes, loaded from user-configured path.
  Uint8List? _pinnedCertDer;
  String? _pinnedCertSource;

  @override
  SessionState build() {
    ref.onDispose(() {
      _cleanup();
      _peerInputController.close();
    });
    return const SessionState();
  }

  /// Parse PEM certificate text into DER bytes.
  static Uint8List? _parsePem(String pem) {
    if (!pem.contains('-----BEGIN CERTIFICATE-----')) return null;
    final lines = pem
        .split('\n')
        .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
        .join();
    return base64.decode(lines);
  }

  /// Load the pinned server cert from the user-configured path.
  Future<Uint8List?> _loadPinnedCert(String certPath) async {
    if (certPath.isEmpty) return null;

    // Re-use cached cert if path hasn't changed
    if (_pinnedCertDer != null && _pinnedCertSource == certPath) {
      return _pinnedCertDer;
    }

    try {
      final expanded = certPath.startsWith('~/')
          ? certPath.replaceFirst('~', userEnvironment['HOME'] ?? '')
          : certPath;
      final file = File(expanded);
      if (await file.exists()) {
        final pem = await file.readAsString();
        final der = _parsePem(pem);
        if (der != null) {
          _pinnedCertDer = der;
          _pinnedCertSource = certPath;
          return der;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Connect WSS with certificate pinning + HTTP upgrade via HttpClient.
  Future<WebSocket> _connectWss(String url, String certPath) async {
    final pinnedDer = await _loadPinnedCert(certPath);
    if (pinnedDer == null) {
      throw Exception(
        'No server certificate configured.\n'
        'Set the cert path in Settings → Server Cert.',
      );
    }
    final uri = Uri.parse(url);

    // HttpClient with cert pinning — only our exact server cert is accepted
    final client = HttpClient()
      ..badCertificateCallback =
          (cert, host, port) => listEquals(cert.der, pinnedDer);

    // HTTP WebSocket upgrade over TLS
    final key = base64.encode(List.generate(16, (_) => _random.nextInt(256)));
    final request = await client.openUrl('GET', uri.replace(scheme: 'https'));
    request.headers
      ..set('Connection', 'Upgrade')
      ..set('Upgrade', 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', key);
    final response = await request.close();
    if (response.statusCode != HttpStatus.switchingProtocols) {
      throw Exception('WebSocket upgrade failed: ${response.statusCode}');
    }
    // The detached Socket is wrapped by WebSocket.fromUpgradedSocket; closing
    // the WebSocket closes the underlying Socket. The linter can't trace
    // ownership across this hand-off, hence the suppression.
    // ignore: close_sinks
    final socket = await response.detachSocket();
    return WebSocket.fromUpgradedSocket(socket, serverSide: false);
  }

  /// Generate session code: PHO-XXXXXX-YYYYYYYYYYYY
  ///   XXXXXX  = routing code (sent to server, ~30 bits)
  ///   YYYYYYYYYYYY = encryption secret (never leaves clients, ~60 bits)
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String chunk(int n) =>
        List.generate(n, (_) => chars[_random.nextInt(chars.length)]).join();
    return 'PHO-${chunk(6)}-${chunk(12)}';
  }

  /// Split full code into routing (for server) and secret (for encryption).
  static ({String routing, String secret}) _splitCode(String fullCode) {
    final parts = fullCode.split('-');
    if (parts.length != 3 || parts[0] != 'PHO') {
      throw FormatException('Invalid session code: $fullCode');
    }
    return (routing: parts[1], secret: parts[2]);
  }

  /// Host a new session.
  Future<void> hostSession({
    required String serverUrl,
    String certPath = '',
  }) async {
    await _connect(
        url: serverUrl,
        code: _generateCode(),
        isHost: true,
        certPath: certPath);
  }

  /// Join an existing session.
  Future<void> joinSession(
    String code, {
    required String serverUrl,
    String certPath = '',
  }) async {
    await _connect(
        url: serverUrl,
        code: code.toUpperCase(),
        isHost: false,
        certPath: certPath);
  }

  Future<void> _connect({
    required String url,
    required String code,
    required bool isHost,
    required String certPath,
  }) async {
    state = state.copyWith(
      connecting: true,
      isHost: isHost,
      sessionCode: code,
    );

    try {
      // Split code: routing goes to server, secret stays local for encryption
      final split = _splitCode(code);
      _routingCode = split.routing;
      await _crypto.deriveKey(split.secret);

      // Only WSS allowed
      if (!url.startsWith('wss://')) {
        throw ArgumentError('Invalid relay URL. Use format: wss://host:port');
      }

      _socket = await _connectWss(url, certPath);

      _send({'type': isHost ? 'host' : 'join', 'code': _routingCode!});

      _subscription = _socket!.listen(
        (data) => _handleMessage(data as String),
        onError: (e) {
          state = state.copyWith(
            isActive: false,
            connecting: false,
            error: 'Connection error: $e',
          );
          _cleanup();
        },
        onDone: () {
          if (state.isActive) {
            state = state.copyWith(isActive: false, connecting: false);
          }
          _cleanup();
        },
      );

      // Keepalive
      _pingTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _send({'type': 'ping'}),
      );
    } catch (e) {
      state = state.copyWith(
        connecting: false,
        error: 'Failed to connect: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  void _send(Map<String, dynamic> data) {
    try {
      _socket?.add(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _encryptAndSend(String msgType, String plaintext) async {
    try {
      final enc = await _crypto.encrypt(plaintext, msgType);
      _send({
        'type': 'encrypted',
        'sessionCode': _routingCode!,
        'msgType': msgType,
        'nonce': enc.nonce,
        'ciphertext': enc.ciphertext,
      });
    } catch (_) {}
  }

  /// Broadcast terminal output to all peers (host only, encrypted).
  void broadcastOutput(String data) {
    if (!state.isActive || !state.isHost || _socket == null) return;
    _encryptAndSend('output', jsonEncode({'data': data}));
  }

  /// Send keystroke to host (peer only, encrypted).
  void sendInput(String data) {
    if (!state.isActive || _socket == null) return;
    _encryptAndSend('input', jsonEncode({'data': data}));
  }

  /// Broadcast terminal resize (host only, encrypted).
  void broadcastResize(int cols, int rows) {
    _lastCols = cols;
    _lastRows = rows;
    if (!state.isActive || !state.isHost || _socket == null) return;
    _encryptAndSend('resize', jsonEncode({'cols': cols, 'rows': rows}));
  }

  /// Change a participant's role (host only).
  void setRole(String participantId, SessionRole role) {
    if (!state.isHost) return;
    _send({'type': 'role', 'target': participantId, 'role': role.name});
  }

  /// Remove a participant (host only).
  void kick(String participantId) {
    if (!state.isHost) return;
    _send({'type': 'kick', 'target': participantId});
  }

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  void _handleMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      switch (msg['type'] as String) {
        case 'hosted':
          state = state.copyWith(
            isActive: true,
            connecting: false,
            selfId: 'host',
            participants: [
              const Participant(
                id: 'host',
                name: 'You (host)',
                role: SessionRole.host,
              ),
            ],
          );

        case 'joined':
          final peerId = msg['peerId'] as String;
          final role = msg['role'] as String;
          peerTerminal = Terminal(maxLines: 10000)
            ..resize(kInitialTerminalCols, kInitialTerminalRows, 0, 0)
            ..onOutput = sendInput;
          state = state.copyWith(
            isActive: true,
            connecting: false,
            selfId: peerId,
            participants: [
              Participant(
                id: peerId,
                name: 'You',
                role: SessionRole.parse(role),
              ),
            ],
          );

        case 'peer_joined':
          final peerId = msg['peerId'] as String;
          final name = msg['name'] as String? ?? 'Peer';
          state = state.copyWith(
            participants: [
              ...state.participants,
              Participant(
                id: peerId,
                name: name,
                role: SessionRole.viewer,
              ),
            ],
          );
          // Re-broadcast current dims so the new peer renders at the
          // host's actual size instead of the 80×24 fallback.
          if (state.isHost && _lastCols != null && _lastRows != null) {
            broadcastResize(_lastCols!, _lastRows!);
          }

        case 'peer_left':
          final peerId = msg['peerId'] as String;
          state = state.copyWith(
            participants:
                state.participants.where((p) => p.id != peerId).toList(),
          );

        case 'role_changed':
          _handleRoleChanged(msg);

        case 'kicked':
          peerTerminal = null;
          _cleanup();
          state = state.copyWith(
            isActive: false,
            error: 'You were removed from the session.',
          );

        case 'session_ended':
          final reason = msg['reason'] as String?;
          peerTerminal = null;
          _cleanup();
          state = state.copyWith(
            isActive: false,
            error: reason == 'timeout'
                ? 'Session timed out.'
                : 'Host ended the session.',
          );

        case 'encrypted':
          _handleEncrypted(msg);

        case 'error':
          state = state.copyWith(
            error: msg['message'] as String,
            connecting: false,
          );

        case 'pong':
          break;
      }
    } catch (_) {}
  }

  void _handleRoleChanged(Map<String, dynamic> msg) {
    final role = SessionRole.parse(msg['role'] as String);
    // Host messages name the affected peer; peer-targeted messages omit
    // peerId and refer to the receiving peer themselves.
    final targetId = (msg['peerId'] as String?) ?? state.selfId;
    if (targetId == null) return;
    state = state.copyWith(
      participants: state.participants
          .map((p) => p.id == targetId ? p.copyWith(role: role) : p)
          .toList(),
    );
  }

  Future<void> _handleEncrypted(Map<String, dynamic> msg) async {
    try {
      final msgType = msg['msgType'] as String;
      final plaintext = await _crypto.decrypt(
        msg['nonce'] as String,
        msg['ciphertext'] as String,
        msgType,
      );
      final inner = jsonDecode(plaintext) as Map<String, dynamic>;

      switch (msgType) {
        case 'output':
          peerTerminal?.write(inner['data'] as String);

        case 'input':
          _peerInputController.add(inner['data'] as String);

        case 'resize':
          peerTerminal?.resize(
            inner['cols'] as int,
            inner['rows'] as int,
            0,
            0,
          );
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void leaveSession() {
    _send({'type': 'leave'});
    peerTerminal = null;
    _routingCode = null;
    _lastCols = null;
    _lastRows = null;
    _cleanup();
    state = const SessionState();
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
