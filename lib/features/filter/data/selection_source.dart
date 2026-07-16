import 'package:cullimingo/core/files/filename_match.dart';

/// A named list of filenames to turn into a selection (`BUILD_PLAN.md` §5).
class SelectionList {
  /// Creates a selection list.
  const SelectionList({required this.name, required this.filenames});

  /// Human label (e.g. the CSV file's name, or a ContactSheet gallery).
  final String name;

  /// The raw filenames referenced by the source (not yet matched to photos).
  final List<String> filenames;
}

/// A source of a [SelectionList]. Picdrop/CSV is the first implementation;
/// ContactSheet (§7b) becomes a second, API-backed source.
// ignore: one_member_abstracts — deliberate seam with multiple implementations.
abstract interface class SelectionSource {
  /// Loads the selection list.
  Future<SelectionList> load();
}

/// Parses a Picdrop export / generic CSV or text file into a [SelectionList].
/// Delegates the heavy lifting to [parseNameTokens], which handles columns,
/// headers, quoting, leading paths *and* bare names without an extension
/// (Photo-Mechanic paste, ContactSheet "exclude extensions" export).
class CsvSelectionSource implements SelectionSource {
  /// Creates a source over already-read [content], labelled [name].
  const CsvSelectionSource({required this.name, required this.content});

  /// Selection label (usually the file's basename).
  final String name;

  /// Raw file text.
  final String content;

  @override
  Future<SelectionList> load() async =>
      SelectionList(name: name, filenames: parseNameTokens(content));
}
