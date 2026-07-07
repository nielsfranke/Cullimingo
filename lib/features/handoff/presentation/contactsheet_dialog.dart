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
  /// Creates a request. Either [galleryId] (existing) or [newGalleryNames]
  /// (create a new chain) identifies the destination.
  const ContactSheetRequest({
    required this.baseUrl,
    required this.token,
    required this.sources,
    required this.preset,
    this.galleryId,
    this.newGalleryNames = const [],
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

  /// Existing gallery to upload into, or null to create new gallery/-ies.
  final String? galleryId;

  /// Names of the new galleries to create, from root to leaf; the upload goes
  /// into the last. Created sequentially on send, each nested under the
  /// previous (the first under [parentId]). Empty when [galleryId] is set.
  final List<String> newGalleryNames;

  /// Parent (existing) gallery id the new chain is rooted under, or null = top
  /// level. Only meaningful when [newGalleryNames] is non-empty.
  final String? parentId;
}

/// Shows the ContactSheet dialog for [sources] (send) — it can also pull marks
/// from an existing gallery. Returns the chosen [ContactSheetAction], or null
/// on cancel.
Future<ContactSheetAction?> showContactSheetDialog(
  BuildContext context, {
  required List<ExportSource> sources,
  bool initialPullMode = false,
}) {
  return showDialog<ContactSheetAction>(
    context: context,
    builder: (_) =>
        _ContactSheetDialog(sources: sources, initialPullMode: initialPullMode),
  );
}

const List<({String label, int value})> _sizeChoices = [
  (label: '1024 px', value: 1024),
  (label: '2048 px', value: 2048),
  (label: '3072 px', value: 3072),
];

class _ContactSheetDialog extends ConsumerStatefulWidget {
  const _ContactSheetDialog({
    required this.sources,
    this.initialPullMode = false,
  });

  final List<ExportSource> sources;

  /// Open straight into Pull (fetch marks) rather than Send (upload).
  final bool initialPullMode;

  @override
  ConsumerState<_ContactSheetDialog> createState() =>
      _ContactSheetDialogState();
}

class _ContactSheetDialogState extends ConsumerState<_ContactSheetDialog> {
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _token = TextEditingController();
  // Name for a new top-level gallery before the tree is loaded (no picker yet).
  final TextEditingController _fallbackName = TextEditingController();

  int _sizeValue = 2048;
  int _quality = 85;

  // false = send (upload), true = pull (fetch client marks). Seeded from the
  // caller so a right-click "Pull marks…" opens straight into pull mode.
  late bool _pullMode = widget.initialPullMode;

  // Pull side: also import collections as saved selections.
  bool _importCollections = true;

  // Existing-gallery picker: null until loaded; _selected = chosen existing
  // gallery (its id), or null to create a new one by name.
  List<CsGallery>? _galleries;
  String? _selectedGalleryId;

  // A NEW-gallery chain (root→leaf) to create on send, rooted under
  // _newRootParentId (null = top level). Non-empty while creating new; the
  // upload goes into the deepest one. Ignored while an existing gallery is
  // chosen (_selectedGalleryId != null).
  List<String> _newNames = [''];
  String? _newRootParentId;
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
    _fallbackName.dispose();
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

  bool get _canSend {
    if (!_canConnect) return false;
    // No tree loaded yet → the fallback top-level name field.
    if (_galleries == null) return _fallbackName.text.trim().isNotEmpty;
    // An existing gallery is chosen, or every level of the new chain is named.
    if (_selectedGalleryId != null) return true;
    return _newNames.isNotEmpty && _newNames.every((n) => n.trim().isNotEmpty);
  }

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
        // Carry a name typed into the pre-load fallback field into the inline
        // top-level row, so switching to the tree view doesn't lose it.
        _newNames = [_fallbackName.text];
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
      // New-gallery chain: from the fallback field (no tree) or the inline
      // picker chain (tree loaded). Empty when an existing gallery is chosen.
      final creatingNew = _selectedGalleryId == null;
      final newNames = !creatingNew
          ? const <String>[]
          : (_galleries == null
                ? [_fallbackName.text.trim()]
                : [for (final n in _newNames) n.trim()]);
      action = ContactSheetSend(
        ContactSheetRequest(
          baseUrl: baseUrl,
          token: token,
          sources: widget.sources,
          preset: ExportPreset(longEdge: _sizeValue, quality: _quality),
          galleryId: _selectedGalleryId,
          newGalleryNames: newNames,
          parentId: creatingNew && _galleries != null ? _newRootParentId : null,
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
          newRootParentId: _newRootParentId,
          newNames: _newNames,
          allowNew: !_pullMode,
          onSelectExisting: (id) => setState(() => _selectedGalleryId = id),
          onStartNewUnder: (parentId) => setState(() {
            _selectedGalleryId = null;
            _newRootParentId = parentId;
            _newNames = ['']; // fresh single-level chain
          }),
          onAddNestedLevel: () =>
              setState(() => _newNames = [..._newNames, '']),
          onRemoveLevel: () => setState(() {
            if (_newNames.length > 1) {
              _newNames = _newNames.sublist(0, _newNames.length - 1);
            } else {
              // Removing the only new level cancels new-creation: fall back to
              // the parent gallery (upload straight into it) if there is one.
              _selectedGalleryId = _newRootParentId;
              _newNames = const [];
            }
          }),
          onNameChanged: (i, v) => setState(() => _newNames[i] = v),
        ),
      ] else if (!_pullMode) ...[
        // Galleries not loaded yet — a plain top-level name field so you can
        // send to a new gallery without browsing the tree first. Load existing
        // to nest it under another gallery inline.
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _fallbackName,
          decoration: dialogInputDecoration('New gallery name'),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          onChanged: (_) => setState(() {}),
        ),
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
/// mode it leads with an inline "New gallery" row you type the name into, and
/// every existing gallery carries a "+" that starts an inline sub-gallery under
/// it (created on Send).
class _GalleryPicker extends StatefulWidget {
  const _GalleryPicker({
    required this.tree,
    required this.baseUrl,
    required this.selectedId,
    required this.newRootParentId,
    required this.newNames,
    required this.allowNew,
    required this.onSelectExisting,
    required this.onStartNewUnder,
    required this.onAddNestedLevel,
    required this.onRemoveLevel,
    required this.onNameChanged,
  });

  final List<CsGallery> tree;
  final String baseUrl;

  /// The chosen existing gallery, or null while creating a new chain.
  final String? selectedId;

  /// Existing gallery the new chain is rooted under (null = top level); only
  /// meaningful when [selectedId] is null.
  final String? newRootParentId;

  /// The new-gallery chain names, root→leaf. Non-empty while creating new.
  final List<String> newNames;
  final bool allowNew;

  /// Picks an existing gallery as the destination.
  final ValueChanged<String> onSelectExisting;

  /// Starts a fresh new chain under `parentId` (null = top level).
  final ValueChanged<String?> onStartNewUnder;

  /// Adds a deeper level to the current new chain (the leaf's "+").
  final VoidCallback onAddNestedLevel;

  /// Removes the deepest new level (the leaf's "×"); cancels when it is the
  /// last remaining level.
  final VoidCallback onRemoveLevel;

  /// Fires as a chain level's name changes (by index).
  final void Function(int index, String value) onNameChanged;

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

  /// The inline chain of new-gallery name rows (root→leaf), starting at
  /// [startDepth]; only the leaf carries the "+" (add level) and "×" (remove).
  List<Widget> _chainRows(int startDepth) => [
    for (var i = 0; i < widget.newNames.length; i++)
      _NewGalleryRow(
        key: ValueKey('new-${widget.newRootParentId ?? "top"}-$i'),
        depth: startDepth + i,
        initialText: widget.newNames[i],
        autofocus: i == widget.newNames.length - 1,
        onChanged: (v) => widget.onNameChanged(i, v),
        onAddChild: i == widget.newNames.length - 1
            ? widget.onAddNestedLevel
            : null,
        onRemove: i == widget.newNames.length - 1 ? widget.onRemoveLevel : null,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    // Creating a NEW chain (vs. an existing gallery chosen).
    final creatingNew =
        widget.allowNew &&
        widget.selectedId == null &&
        widget.newNames.isNotEmpty;
    // Rooted at top level: the chain leads the list inline.
    final creatingTopLevel = creatingNew && widget.newRootParentId == null;
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
                    // Lead "New gallery" row: an inline name field while it's
                    // the chosen destination, else a tappable row that selects
                    // it. Hidden while searching (search filters existing).
                    if (widget.allowNew && !searching)
                      if (creatingTopLevel)
                        ..._chainRows(0)
                      else
                        _PickerRow(
                          depth: 0,
                          label: 'New gallery…',
                          leading: const _CoverBox(
                            child: Icon(Icons.add, size: 18),
                          ),
                          selected: false,
                          onTap: () => widget.onStartNewUnder(null),
                        ),
                    for (final row in rows) ...[
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
                        onTap: () => widget.onSelectExisting(row.gallery.id),
                        // "+" starts an inline sub-gallery chain here.
                        onAddChild: widget.allowNew && !searching
                            ? () {
                                setState(
                                  () => _collapsed.remove(row.gallery.id),
                                );
                                widget.onStartNewUnder(row.gallery.id);
                              }
                            : null,
                      ),
                      // The inline sub-gallery name chain, nested under its
                      // chosen parent.
                      if (creatingNew &&
                          widget.newRootParentId == row.gallery.id)
                        ..._chainRows(row.depth + 1),
                    ],
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
    this.onAddChild,
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

  /// Starts a new sub-gallery under this row ("+"); null = not offered.
  final VoidCallback? onAddChild;

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
          if (onAddChild != null) ...[
            const SizedBox(width: AppSpacing.xs),
            _RowIconButton(
              icon: Icons.add,
              tooltip: 'New sub-gallery',
              onTap: onAddChild!,
            ),
          ],
        ],
      ),
    ),
  );
}

/// An inline row (in [_GalleryPicker]) for naming a new gallery — one per level
/// of the new chain (lead row at top level, or nested under a parent). Owns its
/// own controller (seeded from [initialText]) so it survives the picker's
/// rebuilds; the leaf gets a "+" (nest a deeper new gallery) and a "×" (remove
/// this level). Styled like a selected [_PickerRow], with a folder icon.
class _NewGalleryRow extends StatefulWidget {
  const _NewGalleryRow({
    required this.depth,
    required this.initialText,
    required this.autofocus,
    required this.onChanged,
    this.onAddChild,
    this.onRemove,
    super.key,
  });

  final int depth;
  final String initialText;
  final bool autofocus;
  final ValueChanged<String> onChanged;

  /// Nest a deeper new gallery under this one (leaf only); null = not offered.
  final VoidCallback? onAddChild;

  /// Remove this (deepest) level (leaf only); null = not offered.
  final VoidCallback? onRemove;

  @override
  State<_NewGalleryRow> createState() => _NewGalleryRowState();
}

class _NewGalleryRowState extends State<_NewGalleryRow> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.accent.withValues(alpha: 0.18),
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: AppSpacing.sm),
    child: Row(
      children: [
        SizedBox(width: widget.depth * 18.0),
        // Align with the chevron column of the other rows.
        const SizedBox(width: 20),
        const _CoverBox(
          child: Icon(Icons.create_new_folder_outlined, size: 18),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: _c,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'New gallery name…',
              hintStyle: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (widget.onAddChild != null)
          _RowIconButton(
            icon: Icons.add,
            tooltip: 'Nested sub-gallery',
            onTap: widget.onAddChild!,
          ),
        if (widget.onRemove != null)
          _RowIconButton(
            icon: Icons.close,
            tooltip: 'Remove',
            onTap: widget.onRemove!,
          ),
      ],
    ),
  );
}

/// A compact icon tap-target for the picker rows ("+"/"×"), sized to sit inline
/// without the bulk of a full [IconButton].
class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
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
