import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:cullimingo/features/handoff/data/contactsheet_client.dart';
import 'package:cullimingo/features/handoff/data/cs_credentials.dart';
import 'package:cullimingo/features/handoff/domain/cs_models.dart';
import 'package:cullimingo/features/handoff/domain/gallery_tree.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the ContactSheet dialog resolved to: a [ContactSheetSend] (upload) or a
/// [ContactSheetPull] (fetch client marks). The page runs it non-modally (§7b).
sealed class ContactSheetAction {
  const ContactSheetAction();
}

/// Upload the selection to a gallery.
class ContactSheetSend extends ContactSheetAction {
  /// Wraps the send [request].
  const ContactSheetSend(this.request);

  /// The resolved send request.
  final ContactSheetRequest request;
}

/// Pull client ratings/colours from an existing gallery.
class ContactSheetPull extends ContactSheetAction {
  /// Wraps the pull [request].
  const ContactSheetPull(this.request);

  /// The resolved pull request.
  final ContactSheetPullRequest request;
}

/// A confirmed "pull marks" request for an existing gallery.
class ContactSheetPullRequest {
  /// Creates a pull request.
  const ContactSheetPullRequest({
    required this.baseUrl,
    required this.token,
    required this.shareToken,
    required this.galleryName,
    required this.importCollections,
  });

  /// ContactSheet base URL.
  final String baseUrl;

  /// Bearer token (for listing; the pull itself uses the share token).
  final String token;

  /// The gallery's public share token (gates the review-state endpoint).
  final String shareToken;

  /// Gallery name, for the summary message.
  final String galleryName;

  /// Also pull the gallery's collections and save each as a named selection.
  final bool importCollections;
}

/// A confirmed "send to ContactSheet" request, returned by
/// [showContactSheetDialog]. The page runs it non-modally (§7b).
class ContactSheetRequest {
  /// Creates a request. Exactly one of [galleryId] / [galleryName] is set.
  const ContactSheetRequest({
    required this.baseUrl,
    required this.token,
    required this.sources,
    required this.preset,
    this.galleryId,
    this.galleryName,
    this.parentId,
  });

  /// ContactSheet base URL.
  final String baseUrl;

  /// Bearer token.
  final String token;

  /// Photos to render + upload.
  final List<ExportSource> sources;

  /// Render settings (JPEG, keep names).
  final ExportPreset preset;

  /// Existing gallery to upload into, or null to create a new one.
  final String? galleryId;

  /// Name for a new gallery, or null when [galleryId] is set.
  final String? galleryName;

  /// Parent gallery id for a new gallery (sub-gallery), or null = top level.
  /// Only meaningful when [galleryName] is set.
  final String? parentId;
}

/// Shows the ContactSheet dialog for [sources] (send) — it can also pull marks
/// from an existing gallery. Returns the chosen [ContactSheetAction], or null
/// on cancel.
Future<ContactSheetAction?> showContactSheetDialog(
  BuildContext context, {
  required List<ExportSource> sources,
}) {
  return showDialog<ContactSheetAction>(
    context: context,
    builder: (_) => _ContactSheetDialog(sources: sources),
  );
}

const List<({String label, int value})> _sizeChoices = [
  (label: '1024 px', value: 1024),
  (label: '2048 px', value: 2048),
  (label: '3072 px', value: 3072),
];

class _ContactSheetDialog extends ConsumerStatefulWidget {
  const _ContactSheetDialog({required this.sources});

  final List<ExportSource> sources;

  @override
  ConsumerState<_ContactSheetDialog> createState() =>
      _ContactSheetDialogState();
}

class _ContactSheetDialogState extends ConsumerState<_ContactSheetDialog> {
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _galleryName = TextEditingController();

  int _sizeValue = 2048;
  int _quality = 85;

  // false = send (upload), true = pull (fetch client marks).
  bool _pullMode = false;

  // Pull side: also import collections as saved selections.
  bool _importCollections = true;

  // Existing-gallery picker: null until loaded; _selected = chosen existing
  // gallery (its id), or null to create a new one by name.
  List<CsGallery>? _galleries;
  String? _selectedGalleryId;

  // Parent for a NEW gallery (sub-gallery), or null = top level.
  String? _newParentId;
  bool _loading = false;
  String? _error;

  // A configured server shows as a compact summary row; Change expands the
  // URL/token fields again. Starts expanded until _restore() knows better.
  bool _editServer = true;

  // The gallery used last time, to preselect once the tree loads. Consumed on
  // first use so a manual Reload never overrides a deliberate "New gallery…".
  String? _lastGalleryId;

  CsGallery? get _selectedGallery {
    final id = _selectedGalleryId;
    if (id == null) return null;
    // Search the whole tree, not just top-level, so a chosen sub-gallery is
    // found.
    for (final row in flattenGalleryTree(_galleries ?? const <CsGallery>[])) {
      if (row.gallery.id == id) return row.gallery;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  /// Restores the stored connection and the last-used dialog settings, then —
  /// when the server is already configured — collapses the server row and
  /// loads the galleries right away, so a returning user only picks a gallery
  /// and hits Send.
  Future<void> _restore() async {
    final creds = await loadCsCredentials(ref.read(secretStoreProvider));
    final last = (await AppSettings.load()).lastContactSheet;
    if (!mounted) return;
    setState(() {
      _baseUrl.text = creds.baseUrl;
      _token.text = creds.token;
      _editServer = !_canConnect;
      if (last != null) {
        final size = (last['size'] as num?)?.toInt();
        if (_sizeChoices.any((c) => c.value == size)) _sizeValue = size!;
        final quality = (last['quality'] as num?)?.toInt();
        if (quality != null) _quality = quality.clamp(50, 100);
        _importCollections =
            last['importCollections'] as bool? ?? _importCollections;
        _lastGalleryId = last['galleryId'] as String?;
      }
    });
    if (_canConnect) await _loadGalleries();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _token.dispose();
    _galleryName.dispose();
    super.dispose();
  }

  bool get _canConnect =>
      _baseUrl.text.trim().isNotEmpty && _token.text.trim().isNotEmpty;

  /// The configured server, shortened to its host for the collapsed row —
  /// falling back to the raw text when it isn't a parseable URL.
  String _serverSummary() {
    final url = _baseUrl.text.trim();
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? url : host;
  }

  bool get _canSend =>
      _canConnect &&
      (_selectedGalleryId != null || _galleryName.text.trim().isNotEmpty);

  // Pull needs an existing (already-reviewed) gallery, so its share token.
  bool get _canPull => _canConnect && _selectedGallery != null;

  bool get _canSubmit => _pullMode ? _canPull : _canSend;

  Future<void> _loadGalleries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = ContactSheetClient(
      baseUrl: _baseUrl.text.trim(),
      token: _token.text.trim(),
    );
    try {
      final galleries = await client.listGalleries();
      if (!mounted) return;
      setState(() {
        _galleries = galleries;
        // Preselect last time's gallery — once. If it's gone (or the user
        // already picked something), the choice stays as-is.
        final last = _lastGalleryId;
        _lastGalleryId = null;
        if (last != null &&
            _selectedGalleryId == null &&
            flattenGalleryTree(galleries).any((r) => r.gallery.id == last)) {
          _selectedGalleryId = last;
        }
      });
    } on ContactSheetException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submit() {
    final baseUrl = _baseUrl.text.trim();
    final token = _token.text.trim();
    final secrets = ref.read(secretStoreProvider);
    // One sequential chain, not two racing ones — the writes serialize anyway.
    unawaited(() async {
      await saveCsCredentials(secrets, baseUrl: baseUrl, token: token);
      final settings = await AppSettings.load();
      await settings.setLastContactSheet({
        'size': _sizeValue,
        'quality': _quality,
        'importCollections': _importCollections,
        if (_selectedGalleryId != null) 'galleryId': _selectedGalleryId,
      });
    }());
    final ContactSheetAction action;
    if (_pullMode) {
      final gallery = _selectedGallery!;
      action = ContactSheetPull(
        ContactSheetPullRequest(
          baseUrl: baseUrl,
          token: token,
          shareToken: gallery.shareToken,
          galleryName: gallery.name,
          importCollections: _importCollections,
        ),
      );
    } else {
      action = ContactSheetSend(
        ContactSheetRequest(
          baseUrl: baseUrl,
          token: token,
          sources: widget.sources,
          preset: ExportPreset(longEdge: _sizeValue, quality: _quality),
          galleryId: _selectedGalleryId,
          galleryName: _selectedGalleryId == null
              ? _galleryName.text.trim()
              : null,
          parentId: _selectedGalleryId == null ? _newParentId : null,
        ),
      );
    }
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.sources.length;
    return AlertDialog(
      title: const Text('ContactSheet'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: _form()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(_pullMode ? 'Pull marks' : 'Send $count'),
        ),
      ],
    );
  }

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Send')),
          ButtonSegment(value: true, label: Text('Pull marks')),
        ],
        selected: {_pullMode},
        onSelectionChanged: (s) => setState(() => _pullMode = s.first),
      ),
      const SizedBox(height: AppSpacing.md),
      const DialogSection('Server'),
      if (!_editServer && _canConnect)
        // Configured — one calm line instead of URL + token fields.
        Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 16,
              color: AppColors.labelGreen,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                _serverSummary(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _editServer = true),
              child: const Text('Change'),
            ),
          ],
        )
      else ...[
        TextField(
          controller: _baseUrl,
          decoration: dialogInputDecoration('https://contactsheet.example.com'),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _token,
          obscureText: true,
          decoration: dialogInputDecoration('Access token (cs_pat_…)'),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          onChanged: (_) => setState(() {}),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      const DialogSection('Gallery'),
      Row(
        children: [
          Expanded(
            child: Text(
              _galleries == null
                  ? (_pullMode
                        ? 'Load the gallery the client reviewed.'
                        : 'Create a new gallery, or load existing ones.')
                  : '${flattenGalleryTree(_galleries!).length} galleries',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: _canConnect && !_loading ? _loadGalleries : null,
            child: Text(
              _loading
                  ? 'Loading…'
                  : (_galleries == null ? 'Load existing' : 'Reload'),
            ),
          ),
        ],
      ),
      if (_galleries != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _GalleryPicker(
          tree: _galleries!,
          baseUrl: _baseUrl.text.trim(),
          selectedId: _selectedGalleryId,
          allowNew: !_pullMode,
          onSelect: (id) => setState(() => _selectedGalleryId = id),
        ),
      ],
      if (!_pullMode && _selectedGalleryId == null) ...[
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _galleryName,
          decoration: dialogInputDecoration('New gallery name'),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          onChanged: (_) => setState(() {}),
        ),
        if (_galleries != null) ...[
          const SizedBox(height: AppSpacing.sm),
          DialogField(
            label: 'Parent',
            child: DialogDropdown<String?>(
              value: _newParentId,
              onChanged: (v) => setState(() => _newParentId = v),
              items: [
                const DropdownMenuItem(child: Text('Top level')),
                for (final row in flattenGalleryTree(_galleries!))
                  DropdownMenuItem(
                    value: row.gallery.id,
                    child: Text(
                      '${'   ' * row.depth}${row.gallery.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          _error!,
          style: const TextStyle(color: AppColors.labelYellow, fontSize: 12),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      if (_pullMode) ...[
        const DialogSection('Pull'),
        const Text(
          'Fetches client ratings + colours and applies them to the matching '
          'photos by filename (selecting the ones the client marked).',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: AppSpacing.xs),
        DialogCheckbox(
          value: _importCollections,
          onChanged: (v) => setState(() => _importCollections = v ?? false),
          label: 'Import collections as saved selections',
        ),
      ] else ...[
        const DialogSection('Size & quality'),
        DialogField(
          label: 'Long edge',
          child: DialogDropdown<int>(
            value: _sizeValue,
            onChanged: (v) => setState(() => _sizeValue = v!),
            items: [
              for (final s in _sizeChoices)
                DropdownMenuItem(value: s.value, child: Text(s.label)),
            ],
          ),
        ),
        DialogField(
          label: 'Quality',
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: _quality.toDouble(),
                  min: 50,
                  max: 100,
                  divisions: 50,
                  label: '$_quality',
                  onChanged: (v) => setState(() => _quality = v.round()),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$_quality',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Renders JPEGs (in-camera look) and uploads them to the gallery.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    ],
  );
}

/// A hierarchical gallery list with cover thumbnails, image counts and indented
/// sub-galleries — so the structure is visible and sub-galleries aren't lost.
/// Parents are collapsible (chevron) and a search box filters by name. In send
/// mode it leads with a "New gallery…" row (selection id `null`).
class _GalleryPicker extends StatefulWidget {
  const _GalleryPicker({
    required this.tree,
    required this.baseUrl,
    required this.selectedId,
    required this.allowNew,
    required this.onSelect,
  });

  final List<CsGallery> tree;
  final String baseUrl;
  final String? selectedId;
  final bool allowNew;
  final ValueChanged<String?> onSelect;

  @override
  State<_GalleryPicker> createState() => _GalleryPickerState();
}

class _GalleryPickerState extends State<_GalleryPicker> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _collapsed = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Start tidy: every parent collapsed, so only top-level galleries show and
    // the tree expands one level at a time.
    for (final row in flattenGalleryTree(widget.tree)) {
      if (row.hasChildren) _collapsed.add(row.gallery.id);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleCollapse(String id) => setState(() {
    if (!_collapsed.remove(id)) _collapsed.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final rows = searching
        ? searchGalleryRows(widget.tree, _query)
        : visibleGalleryRows(widget.tree, _collapsed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: dialogInputDecoration('Search galleries…').copyWith(
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
          ),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'No galleries match.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  children: [
                    if (widget.allowNew && !searching)
                      _PickerRow(
                        depth: 0,
                        label: 'New gallery…',
                        leading: const _CoverBox(
                          child: Icon(Icons.add, size: 18),
                        ),
                        selected: widget.selectedId == null,
                        onTap: () => widget.onSelect(null),
                      ),
                    for (final row in rows)
                      _PickerRow(
                        depth: row.depth,
                        label: row.gallery.name,
                        count: row.gallery.imageCount,
                        leading: _Cover(
                          url: resolveCoverUrl(
                            widget.baseUrl,
                            row.gallery.coverImageUrl,
                          ),
                        ),
                        collapsed: _collapsed.contains(row.gallery.id),
                        onToggleCollapse: row.hasChildren && !searching
                            ? () => _toggleCollapse(row.gallery.id)
                            : null,
                        selected: widget.selectedId == row.gallery.id,
                        onTap: () => widget.onSelect(row.gallery.id),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.depth,
    required this.label,
    required this.leading,
    required this.selected,
    required this.onTap,
    this.count,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  final int depth;
  final String label;
  final Widget leading;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool collapsed;

  /// Collapse toggle for a parent gallery; null = leaf (no chevron).
  final VoidCallback? onToggleCollapse;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      color: selected ? AppColors.accent.withValues(alpha: 0.18) : null,
      padding: const EdgeInsets.symmetric(
        vertical: 5,
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(width: depth * 18.0),
          SizedBox(
            width: 20,
            child: onToggleCollapse == null
                ? null
                : InkWell(
                    onTap: onToggleCollapse,
                    child: Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
          leading,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.accent : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A fixed-size rounded box used for cover thumbnails / picker leading icons.
class _CoverBox extends StatelessWidget {
  const _CoverBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: IconTheme.merge(
      data: const IconThemeData(color: AppColors.textSecondary),
      child: child,
    ),
  );
}

/// A gallery cover thumbnail loaded from [url] (public CDN/thumb), falling back
/// to a placeholder box while loading or on error.
class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = _CoverBox(child: Icon(Icons.photo_outlined, size: 18));
    final src = url;
    if (src == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.network(
        src,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        cacheWidth: 72,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
