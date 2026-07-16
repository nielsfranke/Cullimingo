import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/format/dates.dart';
import 'package:cullimingo/core/raw/orientation_math.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/inspector/data/exif_detail.dart';
import 'package:cullimingo/features/inspector/domain/exif_format.dart';
import 'package:cullimingo/features/inspector/presentation/inspector_providers.dart';
import 'package:cullimingo/features/metadata/domain/crop_rect.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_editor_dialog.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:cullimingo/shared/widgets/color_dot.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:cullimingo/shared/widgets/flag_badge.dart';
import 'package:cullimingo/shared/widgets/rating_stars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Fixed width of the inspector side panel.
const double kInspectorWidth = 300;

/// Read-only metadata for the inspector body, already resolved off the drift
/// row + lazily-read [ExifDetail] — so the body widget is pure and testable
/// without a database or a file read.
class InspectorData {
  /// Creates inspector view data.
  const InspectorData({
    required this.filename,
    required this.isRaw,
    required this.rating,
    required this.color,
    required this.flag,
    required this.keywords,
    this.iptc = const IptcCore(),
    this.camera,
    this.capturedAt,
    this.fallbackWidth,
    this.fallbackHeight,
    this.orientation = 1,
    this.crop,
    this.exif,
  });

  /// Builds view data from a drift [photo] and its (optional) [exif].
  factory InspectorData.from(Photo photo, ExifDetail? exif) => InspectorData(
    filename: p.basename(photo.path),
    isRaw: photo.isRaw,
    rating: photo.rating,
    color: photo.colorLabel,
    flag: photo.flag,
    keywords: photo.keywords,
    iptc: photo.iptc,
    camera: photo.camera,
    capturedAt: photo.capturedAt,
    fallbackWidth: photo.width,
    fallbackHeight: photo.height,
    // Effective orientation = the file's EXIF composed with the user's rotate.
    orientation: rotateOrientation(photo.orientation, photo.userRotation),
    crop: photo.hasCrop && photo.cropLeft != null
        ? CropRect(
            left: photo.cropLeft!,
            top: photo.cropTop ?? 0,
            right: photo.cropRight ?? 1,
            bottom: photo.cropBottom ?? 1,
            angle: photo.cropAngle ?? 0,
          )
        : null,
    exif: exif,
  );

  /// File name (basename).
  final String filename;

  /// True for RAW files.
  final bool isRaw;

  /// Star rating 0–5.
  final int rating;

  /// Colour label.
  final ColorLabel color;

  /// Pick/reject flag.
  final PickFlag flag;

  /// Keyword list.
  final List<String> keywords;

  /// Descriptive IPTC Core fields (caption, creator, credit, location…).
  final IptcCore iptc;

  /// Camera model from the drift row.
  final String? camera;

  /// Capture time from the drift row.
  final DateTime? capturedAt;

  /// Pixel width from the drift row, used if EXIF detail lacks it.
  final int? fallbackWidth;

  /// Pixel height from the drift row, used if EXIF detail lacks it.
  final int? fallbackHeight;

  /// EXIF orientation (1–8) from the drift row.
  final int orientation;

  /// Non-destructive Lightroom/Camera-Raw crop, when the source has one.
  final CropRect? crop;

  /// Lazily-read detail EXIF (lens/exposure/dimensions), when available.
  final ExifDetail? exif;

  /// Effective pixel width: EXIF detail wins, else the drift row.
  int? get width => exif?.width ?? fallbackWidth;

  /// Effective pixel height: EXIF detail wins, else the drift row.
  int? get height => exif?.height ?? fallbackHeight;
}

/// The read-only metadata inspector side panel (Phase 8). Shows the focused
/// photo's cull marks (Phase 4) plus EXIF (camera/lens/exposure/time/size).
/// Collapsible like the filter panel; toggled from the toolbar.
class InspectorPanel extends ConsumerWidget {
  /// Creates the inspector panel.
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusedId = ref.watch(
      cullControllerProvider.select((s) => s.focusedId),
    );
    final photos = ref.watch(photosProvider).value ?? const <Photo>[];
    Photo? photo;
    for (final candidate in photos) {
      if (candidate.id == focusedId) {
        photo = candidate;
        break;
      }
    }

    ExifDetail? exif;
    if (photo != null) {
      exif = ref.watch(focusedExifProvider(photo.path)).value;
    }

    final target = photo;
    return InspectorPanelBody(
      data: target == null ? null : InspectorData.from(target, exif),
      onClose: () => ref.read(inspectorOpenProvider.notifier).toggle(),
      onEditMetadata: () => showIptcEditor(context, ref),
      onSaveIptc: target == null
          ? null
          : (field, value) => ref
                .read(cullControllerProvider.notifier)
                .setIptc(target.id, target.iptc.withOverrides({field: value})),
    );
  }
}

/// The pure inspector chrome: a fixed-width bordered panel rendering [data]
/// (or an empty state when null). Split out so it can be widget-tested with
/// constructed [InspectorData], no providers or file reads.
class InspectorPanelBody extends StatelessWidget {
  /// Creates the inspector body.
  const InspectorPanelBody({
    required this.data,
    required this.onClose,
    this.onEditMetadata,
    this.onSaveIptc,
    super.key,
  });

  /// The metadata to show, or null when no photo is focused.
  final InspectorData? data;

  /// Called when the close (chevron) button is tapped.
  final VoidCallback onClose;

  /// Called when the IPTC section's Edit button is tapped; null hides it (e.g.
  /// in widget tests that render the pure body without providers).
  final VoidCallback? onEditMetadata;

  /// Writes one inline-edited IPTC field through to the focused photo
  /// (`BUILD_PLAN.md` Phase 9 backlog — the inspector used to be read-only).
  /// Null keeps the section read-only.
  final Future<void> Function(IptcField field, String value)? onSaveIptc;

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Container(
      width: kInspectorWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: d == null
                ? const _Empty()
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: _sections(d),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Container(
    height: 52,
    padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        const Text(
          'Info',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onClose,
          tooltip: 'Hide inspector (I)',
          icon: const Icon(Icons.chevron_right, size: 18),
        ),
      ],
    ),
  );

  List<Widget> _sections(InspectorData d) {
    final exif = d.exif;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              d.filename,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (d.isRaw)
            Container(
              margin: const EdgeInsets.only(left: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'RAW',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),

      const DialogSection('Marks'),
      _MarksRow(rating: d.rating, color: d.color, flag: d.flag),
      if (d.keywords.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        _Keywords(keywords: d.keywords),
      ],
      const SizedBox(height: AppSpacing.lg),

      _IptcHeader(onEdit: onEditMetadata),
      _IptcSection(iptc: d.iptc, onSave: onSaveIptc),
      _IptcTables(iptc: d.iptc),
      const SizedBox(height: AppSpacing.lg),

      const DialogSection('Camera'),
      _Kv('Camera', d.camera),
      _Kv('Lens', exif?.lens),
      _Kv(
        'Exposure',
        exif?.shutterSeconds == null
            ? null
            : formatShutter(exif!.shutterSeconds!),
      ),
      _Kv(
        'Aperture',
        exif?.aperture == null ? null : formatAperture(exif!.aperture!),
      ),
      _Kv('ISO', exif?.iso == null ? null : formatIso(exif!.iso!)),
      _Kv(
        'Focal length',
        exif?.focalLength == null
            ? null
            : formatFocalLength(exif!.focalLength!),
      ),
      _Kv(
        'Exp. comp.',
        exif?.exposureBias == null
            ? null
            : formatExposureBias(exif!.exposureBias!),
      ),
      const SizedBox(height: AppSpacing.lg),

      const DialogSection('Image'),
      _Kv(
        'Dimensions',
        (d.width == null || d.height == null)
            ? null
            : formatDimensions(d.width!, d.height!),
      ),
      _Kv(
        'Resolution',
        (d.width == null || d.height == null)
            ? null
            : formatMegapixels(d.width!, d.height!),
      ),
      _Kv('Orientation', formatOrientation(d.orientation)),
      if (d.crop != null)
        _Kv(
          'Crop',
          'Cropped (LR) · '
              '${formatCrop(d.crop!.width, d.crop!.height, d.crop!.angle)}',
        ),
      _Kv(
        'Captured',
        d.capturedAt == null
            ? null
            : displayDateTime(d.capturedAt!, seconds: true),
      ),
    ];
  }
}

/// The IPTC rows: non-empty fields, each value editable in place when [onSave]
/// is wired (click → inline field, Enter/blur commits, Esc cancels), plus an
/// "Add field" menu over the still-empty fields. Inline editors are
/// single-line by design — long captions belong in the M editor.
class _IptcSection extends StatefulWidget {
  const _IptcSection({required this.iptc, required this.onSave});

  final IptcCore iptc;
  final Future<void> Function(IptcField field, String value)? onSave;

  @override
  State<_IptcSection> createState() => _IptcSectionState();
}

class _IptcSectionState extends State<_IptcSection> {
  /// An empty field the user is adding via the menu (rendered as an editor).
  IptcField? _adding;

  @override
  Widget build(BuildContext context) {
    final iptc = widget.iptc;
    final onSave = widget.onSave;
    final visible = [
      for (final field in IptcField.values)
        if (iptc.valueFor(field).isNotEmpty || field == _adding) field,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 3),
            child: Text(
              'No caption or credit',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        for (final field in visible)
          _IptcRow(
            // Remount when the value changes underneath (external edit).
            key: ValueKey('${field.name}:${iptc.valueFor(field)}'),
            field: field,
            value: iptc.valueFor(field),
            startEditing: field == _adding,
            onSave: onSave == null
                ? null
                : (value) async {
                    if (_adding == field) setState(() => _adding = null);
                    await onSave(field, value);
                  },
            onCancel: () {
              if (_adding == field) setState(() => _adding = null);
            },
          ),
        if (onSave != null)
          PopupMenuButton<IptcField>(
            tooltip: 'Add a metadata field',
            popUpAnimationStyle: kMenuAnimationStyle,
            onSelected: (field) => setState(() => _adding = field),
            itemBuilder: (_) => [
              for (final field in IptcField.values)
                if (iptc.valueFor(field).isEmpty)
                  PopupMenuItem(value: field, child: Text(field.label)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '+ Add field',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

/// Read-only summary of the structured IPTC tables (Location Shown, Artwork,
/// Image Creators…). Editing lives in the M editor — the inspector just shows
/// that they exist, one compact line per row. Renders nothing when empty.
class _IptcTables extends StatelessWidget {
  const _IptcTables({required this.iptc});

  final IptcCore iptc;

  // Joins a record's non-empty parts (its [toJson] values, in field order).
  static String _row(Map<String, dynamic> json) =>
      json.values.map((v) => '$v').join(' · ');

  @override
  Widget build(BuildContext context) {
    final groups = <({String title, List<String> rows})>[
      (
        title: 'Locations shown',
        rows: [for (final l in iptc.locationsShown) _row(l.toJson())],
      ),
      (
        title: 'Artwork or object',
        rows: [for (final a in iptc.artwork) _row(a.toJson())],
      ),
      (
        title: 'Image creators',
        rows: [for (final e in iptc.imageCreators) _row(e.toJson())],
      ),
      (
        title: 'Copyright owners',
        rows: [for (final e in iptc.copyrightOwners) _row(e.toJson())],
      ),
      (
        title: 'Licensors',
        rows: [for (final l in iptc.licensors) _row(l.toJson())],
      ),
      (
        title: 'Registry entries',
        rows: [for (final r in iptc.registryEntries) _row(r.toJson())],
      ),
    ].where((g) => g.rows.isNotEmpty).toList();
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            g.title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final row in g.rows)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// One IPTC label/value row that swaps to an inline editor on click.
class _IptcRow extends StatefulWidget {
  const _IptcRow({
    required this.field,
    required this.value,
    required this.startEditing,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final IptcField field;
  final String value;
  final bool startEditing;
  final Future<void> Function(String value)? onSave;
  final VoidCallback onCancel;

  @override
  State<_IptcRow> createState() => _IptcRowState();
}

class _IptcRowState extends State<_IptcRow> {
  late bool _editing = widget.startEditing;
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Commit on blur (click-away), like Photo Mechanic's inline fields.
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final value = _controller.text.trim();
    setState(() => _editing = false);
    if (value == widget.value) {
      widget.onCancel();
      return;
    }
    unawaited(widget.onSave?.call(value));
  }

  void _cancel() {
    _controller.text = widget.value;
    setState(() => _editing = false);
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return InkWell(
        onTap: widget.onSave == null
            ? null
            : () => setState(() => _editing = true),
        child: _Kv(widget.field.label, widget.value),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.field.label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _cancel,
              },
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value row; shows an em dash for a null/absent value.
class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value ?? '—',
            style: TextStyle(
              color: value == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The IPTC section header: the section label with an inline Edit button that
/// opens the editor for the current target(s). The button is hidden when no
/// [onEdit] is wired (pure widget tests).
class _IptcHeader extends StatelessWidget {
  const _IptcHeader({required this.onEdit});

  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      children: [
        const Expanded(child: DialogSection('IPTC')),
        if (onEdit != null)
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: const Text('Edit'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    ),
  );
}

class _MarksRow extends StatelessWidget {
  const _MarksRow({
    required this.rating,
    required this.color,
    required this.flag,
  });

  final int rating;
  final ColorLabel color;
  final PickFlag flag;

  @override
  Widget build(BuildContext context) {
    final hasNothing =
        rating <= 0 && color == ColorLabel.none && flag == PickFlag.none;
    if (hasNothing) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 3),
        child: Text(
          'No marks',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          if (rating > 0) ...[
            RatingStars(rating: rating, size: 16),
            const SizedBox(width: AppSpacing.md),
          ],
          if (color != ColorLabel.none) ...[
            ColorDot(label: color, size: 13),
            const SizedBox(width: AppSpacing.xs),
            Text(
              _name(color),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          if (flag != PickFlag.none) ...[
            FlagBadge(flag: flag, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Text(
              flag == PickFlag.pick ? 'Pick' : 'Reject',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _name(ColorLabel c) {
    final n = c.name;
    return '${n[0].toUpperCase()}${n.substring(1)}';
  }
}

class _Keywords extends StatelessWidget {
  const _Keywords({required this.keywords});

  final List<String> keywords;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: [
      for (final k in keywords)
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            k,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
        ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Text(
        'No photo selected',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    ),
  );
}
