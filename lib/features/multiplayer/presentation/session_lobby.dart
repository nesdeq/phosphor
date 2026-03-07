import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/crt_colors.dart';
import '../../../app/theme/phosphor_theme.dart';
import '../../../app/widgets/crt_dialog.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sound_service.dart';
import '../../settings/providers/settings_provider.dart';

/// Session sharing dialog — host or join a shared terminal session.
class SessionLobby extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const SessionLobby({super.key, required this.onClose});

  @override
  ConsumerState<SessionLobby> createState() => _SessionLobbyState();
}

class _SessionLobbyState extends ConsumerState<SessionLobby> {
  final _codeController = TextEditingController();
  bool _isJoinMode = false;
  int _prevInputLength = 0;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _serverUrl => ref.read(crtSettingsProvider).relayServerUrl;
  String get _certPath => ref.read(crtSettingsProvider).relayCertPath;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(phosphorPaletteProvider).colors;
    final session = ref.watch(sessionProvider);

    return CrtDialog(
      title: session.isActive
          ? ' S E S S I O N   A C T I V E '
          : ' M U L T I P L A Y E R ',
      width: 440,
      onClose: widget.onClose,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: session.isActive
              ? _buildActiveSession(colors, session)
              : _buildLobby(colors, session),
        ),
      ],
    );
  }

  Widget _buildLobby(CrtColorScheme colors, SessionState session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (session.error != null) ...[
          Text(
            session.error!,
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 12,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (session.connecting) ...[
          Text(
            'Connecting to $_serverUrl ...',
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 13,
              color: colors.textDim,
            ),
          ),
        ] else if (!_isJoinMode) ...[
          if (_serverUrl.isEmpty) ...[
            Text(
              'No relay server configured.\n\n'
              'Set these in Settings:\n'
              '  Relay Server: wss://host:8766\n'
              '  Server Cert:  /path/to/public.pem\n\n'
              'Run server_setup.sh to generate\n'
              'certs for your relay.',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 12,
                color: colors.textDim,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            _lobbyButton('CLOSE', widget.onClose, colors, primary: false),
          ] else ...[
            Text(
              'Share your terminal session with\n'
              'others. All data is end-to-end\n'
              'encrypted via the session code.',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 12,
                color: colors.textDim,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _lobbyButton('HOST SESSION', () {
                    ref.read(sessionProvider.notifier).hostSession(
                          serverUrl: _serverUrl,
                          certPath: _certPath,
                        );
                  }, colors),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _lobbyButton(
                    'JOIN SESSION',
                    () => setState(() => _isJoinMode = true),
                    colors,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _lobbyButton('CANCEL', widget.onClose, colors, primary: false),
          ],
        ] else ...[
          // Join mode — enter code
          Text(
            'Enter session code:',
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 13,
              color: colors.textDim,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: colors.text),
            ),
            child: TextField(
              controller: _codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (value) {
                _prevInputLength = ref
                    .read(soundServiceProvider)
                    .handleTextFieldKeystroke(_prevInputLength, value);
              },
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 20,
                color: colors.text,
                letterSpacing: 4,
              ),
              cursorColor: colors.cursor,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'PHO-XXXXXX-XXXXXXXXXXXX',
                hintStyle: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 20,
                  color: colors.textDim,
                  letterSpacing: 4,
                ),
              ),
              onSubmitted: (_) => _joinWithCode(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _lobbyButton(
                  'BACK',
                  () => setState(() => _isJoinMode = false),
                  colors,
                  primary: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _lobbyButton('CONNECT', _joinWithCode, colors),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _joinWithCode() {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      ref.read(sessionProvider.notifier).joinSession(
            code,
            serverUrl: _serverUrl,
            certPath: _certPath,
          );
    }
  }

  Widget _buildActiveSession(CrtColorScheme colors, SessionState session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Session code
        Row(
          children: [
            Expanded(
              child: Text(
                session.sessionCode ?? '',
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 14,
                  color: colors.text,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (session.sessionCode != null) {
                  Clipboard.setData(
                      ClipboardData(text: session.sessionCode!));
                }
              },
              child: Text(
                '[COPY]',
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 11,
                  color: colors.textDim,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              session.isHost ? 'Role: HOST' : 'Role: PEER',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 12,
                color: colors.textDim,
              ),
            ),
            const Spacer(),
            Text(
              '[ENCRYPTED]',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 10,
                color: colors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Participants
        Text(
          'Participants:',
          style: TextStyle(
            fontFamily: 'PhosphorMono',
            fontSize: 12,
            color: colors.textDim,
          ),
        ),
        const SizedBox(height: 4),
        ...session.participants.map(
          (p) => _buildParticipantRow(p, colors, session),
        ),
        const SizedBox(height: 16),
        _lobbyButton(
          'LEAVE SESSION',
          () {
            ref.read(sessionProvider.notifier).leaveSession();
            widget.onClose();
          },
          colors,
        ),
      ],
    );
  }

  Widget _buildParticipantRow(
    Participant p,
    CrtColorScheme colors,
    SessionState session,
  ) {
    final isSelf = p.id == session.selfId;
    final isHost = session.isHost;
    final roleLabel = p.role == SessionRole.host
        ? 'HOST'
        : p.role == SessionRole.editor
            ? 'EDITOR'
            : 'VIEWER';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '  ${p.name}',
            style: TextStyle(
              fontFamily: 'PhosphorMono',
              fontSize: 12,
              color: colors.text,
            ),
          ),
          const Spacer(),
          // Role badge — tappable by host to toggle peer roles
          if (isHost && !isSelf && p.role != SessionRole.host)
            GestureDetector(
              onTap: () {
                final newRole = p.role == SessionRole.editor
                    ? SessionRole.viewer
                    : SessionRole.editor;
                ref.read(sessionProvider.notifier).setRole(p.id, newRole);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.textDim),
                ),
                child: Text(
                  roleLabel,
                  style: TextStyle(
                    fontFamily: 'PhosphorMono',
                    fontSize: 9,
                    color: p.role == SessionRole.editor
                        ? colors.text
                        : colors.textDim,
                  ),
                ),
              ),
            )
          else
            Text(
              '[$roleLabel]',
              style: TextStyle(
                fontFamily: 'PhosphorMono',
                fontSize: 10,
                color: colors.textDim,
              ),
            ),
          // Kick button (host only, not self)
          if (isHost && !isSelf && p.role != SessionRole.host) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () =>
                  ref.read(sessionProvider.notifier).kick(p.id),
              child: Text(
                '[X]',
                style: TextStyle(
                  fontFamily: 'PhosphorMono',
                  fontSize: 10,
                  color: colors.textDim,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lobbyButton(
    String label,
    VoidCallback onTap,
    CrtColorScheme colors, {
    bool primary = true,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: primary ? colors.text : Colors.transparent,
          border: Border.all(color: colors.text),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'PhosphorMono',
            fontSize: 13,
            color: primary ? colors.background : colors.text,
          ),
        ),
      ),
    );
  }
}
