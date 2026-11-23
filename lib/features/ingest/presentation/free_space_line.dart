import 'dart:async';
import 'dart:isolate';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/files/destination_check.dart';
import 'package:cullimingo/core/files/posix_fs.dart';
import 'package:flutter/material.dart';

/// Looks up the volume a path is on (blocking FFI, so off the UI isolate).
Future<VolumeInfo?> probeVolumeOffUiIsolate(String path) =>
    Isolate.run(() => volumeInfo(path));

/// "127 GB free on C:\" under a destination — so the free room is visible
/// before an import, not only as a refusal once it runs out. Re-probes when
/// [path] changes; shows nothing while unknown or when the volume can't be
/// read. [probe] is injectable for tests.
class FreeSpaceLine extends StatefulWidget {
  /// Creates the line for [path] (nothing for null).
  const FreeSpaceLine({
    required this.path,
    this.probe = probeVolumeOffUiIsolate,
    super.key,
  });

  /// The chosen destination folder, or null.
  final String? path;

  /// Resolves [path]'s volume.
  final Future<VolumeInfo?> Function(String path) probe;

  @override
  State<FreeSpaceLine> createState() => _FreeSpaceLineState();
}

class _FreeSpaceLineState extends State<FreeSpaceLine> {
  VolumeInfo? _volume;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void didUpdateWidget(FreeSpaceLine old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _probe();
  }

  void _probe() {
    final path = widget.path;
    final generation = ++_generation;
    _volume = null;
    if (path == null) return;
    unawaited(
      widget
          .probe(path)
          .then((v) {
            if (mounted && generation == _generation) {
              setState(() => _volume = v);
            }
          })
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _volume;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        '${formatBytes(v.freeBytes)} free on ${v.mountPoint}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}
