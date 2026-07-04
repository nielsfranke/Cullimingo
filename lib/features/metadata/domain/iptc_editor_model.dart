import 'package:cullimingo/features/metadata/domain/iptc_core.dart';

/// The editor's starting state for one field across a batch: the value to
/// prefill and whether the targets disagreed on it.
class IptcFieldInit {
  /// Creates a field's initial editor state.
  const IptcFieldInit({required this.value, required this.mixed});

  /// The value to prefill — the shared value, or empty when [mixed].
  final String value;

  /// True when the targets held different values for this field, so the editor
  /// shows an empty "Mixed" field that only overwrites if the user types.
  final bool mixed;
}

/// Computes the editor's starting state for every [IptcField] across [targets].
///
/// This is what makes one editor serve single *and* batch edits (Photo Mechanic
/// splits them into two dialogs): when all targets agree on a field it is
/// prefilled; when they disagree it starts empty and flagged mixed (see
/// [IptcFieldInit.mixed]) so leaving it alone preserves each photo's own value.
Map<IptcField, IptcFieldInit> iptcEditorInit(List<IptcCore> targets) {
  final result = <IptcField, IptcFieldInit>{};
  for (final field in IptcField.values) {
    if (targets.isEmpty) {
      result[field] = const IptcFieldInit(value: '', mixed: false);
      continue;
    }
    final first = targets.first.valueFor(field);
    final allSame = targets.every((t) => t.valueFor(field) == first);
    result[field] = IptcFieldInit(value: allSame ? first : '', mixed: !allSame);
  }
  return result;
}

/// The fields the user actually changed: those whose [current] text differs
/// from the initial value. Only these are written to every target, so untouched
/// fields keep each photo's existing value — the whole point of the batch UX.
Map<IptcField, String> iptcEditorChanges(
  Map<IptcField, IptcFieldInit> init,
  Map<IptcField, String> current,
) {
  final changes = <IptcField, String>{};
  for (final field in IptcField.values) {
    final initial = init[field]?.value ?? '';
    final now = current[field] ?? '';
    if (now != initial) changes[field] = now;
  }
  return changes;
}
