import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/template_expansion.dart';
import 'package:cullimingo/features/metadata/domain/template_snapshots.dart';
import 'package:cullimingo/features/metadata/domain/template_variables.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Outcome of an "apply metadata template" run, so the UI can show a notice.
enum ApplyTemplateResult {
  /// No template has been set up (Settings → Metadata template).
  noTemplate,

  /// A template exists but nothing was selected to stamp.
  noTargets,

  /// The template was stamped onto the photos (see the outcome's count).
  applied,
}

/// The result plus how many photos it touched.
typedef ApplyTemplateOutcome = ({ApplyTemplateResult result, int count});

/// Loads the saved metadata template and stamps it onto the current cull
/// targets (the Space-selection if any, else the focused photo), writing each
/// photo's new IPTC + keywords through to its sidecar. Pure orchestration over
/// the providers so the caller only has to surface the outcome.
Future<ApplyTemplateOutcome> applySavedTemplateToSelection(
  WidgetRef ref,
) async {
  final settings = await AppSettings.load();
  final template = loadTemplateSnapshots(settings).active;
  if (template.isEmpty) {
    return (result: ApplyTemplateResult.noTemplate, count: 0);
  }

  final codes = loadCodeReplacements(settings);
  final photos = ref.read(filteredPhotosProvider);
  final byId = {for (final p in photos) p.id: p};
  final targets = ref.read(cullControllerProvider).markTargets;
  final controller = ref.read(cullControllerProvider.notifier);

  var count = 0;
  for (final id in targets) {
    final photo = byId[id];
    if (photo == null) continue;
    await _stamp(controller, photo, template, codes, count + 1);
    count++;
  }
  if (count == 0) return (result: ApplyTemplateResult.noTargets, count: 0);
  return (result: ApplyTemplateResult.applied, count: count);
}

/// Stamps the saved template onto *every* photo in [importId] — the
/// apply-on-ingest path — but only when that setting is on and a non-empty
/// template exists. Returns how many photos were stamped (0 when disabled or
/// no template). Runs after the import's sidecars are applied, so the template
/// merges over any marks the copied files already carried.
Future<int> applyIngestTemplateToImport(WidgetRef ref, int importId) async {
  final settings = await AppSettings.load();
  if (!settings.applyTemplateOnIngest) return 0;
  final template = loadTemplateSnapshots(settings).active;
  if (template.isEmpty) return 0;

  final codes = loadCodeReplacements(settings);
  final db = ref.read(appDatabaseProvider);
  final photos = await db.watchPhotosForImport(importId).first;
  final controller = ref.read(cullControllerProvider.notifier);
  for (var i = 0; i < photos.length; i++) {
    await _stamp(controller, photos[i], template, codes, i + 1);
  }
  return photos.length;
}

/// The persisted template snapshots — from the `metadataTemplates` key when
/// present, else migrated from the legacy single-template key, else empty.
TemplateSnapshots loadTemplateSnapshots(AppSettings settings) {
  final raw = settings.metadataTemplates;
  if (raw != null) return TemplateSnapshots.fromJson(raw);
  final legacy = settings.metadataTemplate;
  if (legacy != null) return TemplateSnapshots.fromLegacy(legacy);
  return const TemplateSnapshots();
}

/// The persisted code-replacement table, or an empty one when never set. Also
/// used by the IPTC editor for its live `=code=` expansion.
CodeReplacements loadCodeReplacements(AppSettings settings) {
  final raw = settings.codeReplacements;
  return raw == null
      ? const CodeReplacements()
      : CodeReplacements.fromJson(raw);
}

/// Expands [template] for one [photo] (its variables + the shared [codes]) at
/// position [sequence], then applies it and writes IPTC + keywords through.
Future<void> _stamp(
  CullController controller,
  Photo photo,
  IptcTemplate template,
  CodeReplacements codes,
  int sequence,
) async {
  final vars = templateVariables(
    path: photo.path,
    capturedAt: photo.capturedAt,
    camera: photo.camera,
    lens: photo.lens,
    sequence: sequence,
  );
  final expanded = expandTemplate(template, vars: vars, codes: codes);
  final out = applyTemplate(photo.iptc, photo.keywords, expanded);
  await controller.setIptcAndKeywords(photo.id, out.iptc, out.keywords);
}
