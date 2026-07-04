import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// What the server dialog hands back: the (new or edited) server plus the
/// password the user typed — the caller decides when to put it in the secret
/// store (on Settings-Apply, so Cancel stays a full undo).
class DeliveryServerEdit {
  /// Creates a result.
  const DeliveryServerEdit({required this.server, required this.password});

  /// The edited server (same id as before when editing).
  final DeliveryServer server;

  /// The password as typed (possibly unchanged, possibly empty).
  final String password;
}

/// Shows the add/edit dialog for one delivery server (`BUILD_PLAN.md` §11).
/// Returns null when cancelled.
Future<DeliveryServerEdit?> showDeliveryServerDialog(
  BuildContext context, {
  DeliveryServer? initial,
  String initialPassword = '',
}) => showDialog<DeliveryServerEdit>(
  context: context,
  builder: (_) =>
      _DeliveryServerDialog(initial: initial, initialPassword: initialPassword),
);

class _DeliveryServerDialog extends StatefulWidget {
  const _DeliveryServerDialog({
    required this.initial,
    required this.initialPassword,
  });

  final DeliveryServer? initial;
  final String initialPassword;

  @override
  State<_DeliveryServerDialog> createState() => _DeliveryServerDialogState();
}

class _DeliveryServerDialogState extends State<_DeliveryServerDialog> {
  late DeliveryProtocol _protocol =
      widget.initial?.protocol ?? DeliveryProtocol.ftps;
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _host = TextEditingController(
    text: widget.initial?.host ?? '',
  );
  late final TextEditingController _port = TextEditingController(
    text: '${widget.initial?.port ?? _protocol.defaultPort}',
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.initial?.username ?? '',
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.initialPassword,
  );
  late final TextEditingController _remoteDir = TextEditingController(
    text: widget.initial?.remoteDir ?? '',
  );
  late final TextEditingController _keyFile = TextEditingController(
    text: widget.initial?.keyFilePath ?? '',
  );
  late bool _allowSelfSigned = widget.initial?.allowSelfSigned ?? false;

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _remoteDir.dispose();
    _keyFile.dispose();
    super.dispose();
  }

  /// The server as currently described by the fields, or null while they
  /// don't form one (missing name/host, unparseable port).
  DeliveryServer? _serverFromFields() {
    final name = _name.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (name.isEmpty || host.isEmpty || port == null || port <= 0) return null;
    return DeliveryServer(
      id: widget.initial?.id ?? DeliveryServer.newId(),
      name: name,
      protocol: _protocol,
      host: host,
      port: port,
      username: _username.text.trim(),
      remoteDir: _remoteDir.text.trim(),
      allowSelfSigned: _protocol == DeliveryProtocol.ftps && _allowSelfSigned,
      keyFilePath: _protocol == DeliveryProtocol.sftp
          ? _keyFile.text.trim()
          : '',
    );
  }

  void _selectProtocol(DeliveryProtocol? protocol) {
    if (protocol == null) return;
    setState(() {
      // Follow the conventional port unless the user typed their own.
      if (_port.text.trim() == '${_protocol.defaultPort}') {
        _port.text = '${protocol.defaultPort}';
      }
      _protocol = protocol;
    });
  }

  Future<void> _pickKeyFile() async {
    final file = await openFile();
    if (file != null && mounted) setState(() => _keyFile.text = file.path);
  }

  Future<void> _testConnection() async {
    final server = _serverFromFields();
    if (server == null) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final message = await testDeliveryConnection(
      createDeliveryClient(server, _password.text),
      server.remoteDir,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = message == null;
      _testResult = message ?? 'Connection OK — logged in, folder reachable.';
    });
  }

  void _save() {
    final server = _serverFromFields();
    if (server == null) return;
    Navigator.of(context).pop(
      DeliveryServerEdit(server: server, password: _password.text),
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      // Revalidate the Save/Test buttons as the user types.
      onChanged: (_) => setState(() {}),
      decoration: dialogInputDecoration(hint),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final valid = _serverFromFields() != null;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add server' : 'Edit server'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_name, 'Name (e.g. AP wire)'),
              DialogDropdown<DeliveryProtocol>(
                value: _protocol,
                items: [
                  for (final p in DeliveryProtocol.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: _selectProtocol,
              ),
              if (_protocol == DeliveryProtocol.ftp)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Plain FTP sends the password unencrypted — fine on a '
                    'LAN/VPN, avoid on the open internet.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(flex: 3, child: _field(_host, 'Host')),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _field(_port, 'Port')),
                ],
              ),
              if (_protocol == DeliveryProtocol.ftps)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: DialogCheckbox(
                    value: _allowSelfSigned,
                    onChanged: (v) =>
                        setState(() => _allowSelfSigned = v ?? false),
                    label: 'Accept self-signed certificate',
                  ),
                ),
              _field(_username, 'Username (empty = anonymous)'),
              if (_protocol == DeliveryProtocol.sftp)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        _keyFile,
                        'Private key file (empty = password auth)',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Choose key file',
                      icon: const Icon(Icons.folder_open),
                      onPressed: () => unawaited(_pickKeyFile()),
                    ),
                  ],
                ),
              _field(
                _password,
                _protocol == DeliveryProtocol.sftp &&
                        _keyFile.text.trim().isNotEmpty
                    ? 'Key passphrase (empty = unencrypted key)'
                    : 'Password',
                obscure: true,
              ),
              _field(_remoteDir, 'Remote folder (e.g. incoming/photos)'),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: valid && !_testing
                        ? () => unawaited(_testConnection())
                        : null,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 16),
                    label: const Text('Test connection'),
                  ),
                ],
              ),
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testOk ? AppColors.selection : AppColors.labelRed,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: valid ? _save : null, child: const Text('OK')),
      ],
    );
  }
}
