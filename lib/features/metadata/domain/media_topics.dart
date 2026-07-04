import 'dart:convert';
import 'dart:io';

/// One IPTC Media Topic: the `medtop:` QCode, its English name and (for
/// context in suggestion lists) its parent topic's name.
class MediaTopic {
  /// Creates a topic.
  const MediaTopic({
    required this.qcode,
    required this.label,
    this.parent = '',
  });

  /// The controlled-vocabulary code (`medtop:20001065`).
  final String qcode;

  /// English preferred label ("soccer").
  final String label;

  /// The broader topic's label ("competition discipline"), or '' for a
  /// top-level topic.
  final String parent;
}

/// The bundled IPTC Media Topics vocabulary (`assets/iptc/mediatopics.tsv.gz`,
/// built by `tool/build_media_topics.sh`, CC-BY 4.0) — the controlled
/// vocabulary behind the Subject-codes field (`BUILD_PLAN.md` Phase 9
/// backlog). ~1100 active topics; retired ones are dropped at build time.
///
/// Construct via [MediaTopics.fromGzippedTsv] *inside an isolate* like the
/// gazetteer, then [search] is cheap enough for per-keystroke calls.
class MediaTopics {
  /// Creates a vocabulary over [topics].
  const MediaTopics(this.topics);

  /// Parses the gzipped TSV produced by the build script
  /// (`qcode\tlabel\tparent label` per line).
  factory MediaTopics.fromGzippedTsv(List<int> gzBytes) {
    final lines = const LineSplitter().convert(
      utf8.decode(gzip.decode(gzBytes)),
    );
    final topics = <MediaTopic>[];
    for (final line in lines) {
      final parts = line.split('\t');
      if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) continue;
      topics.add(
        MediaTopic(
          qcode: parts[0],
          label: parts[1],
          parent: parts.length > 2 ? parts[2] : '',
        ),
      );
    }
    return MediaTopics(topics);
  }

  /// All topics, in vocabulary order.
  final List<MediaTopic> topics;

  /// The label for [qcode], or null when it isn't in the vocabulary.
  String? labelFor(String qcode) {
    for (final topic in topics) {
      if (topic.qcode == qcode) return topic.label;
    }
    return null;
  }

  /// Case-insensitive topic search for the autocomplete: label prefix first,
  /// then word-prefix, then substring (also matching the code itself), up to
  /// [limit] results. A blank query matches nothing.
  List<MediaTopic> search(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final prefix = <MediaTopic>[];
    final wordPrefix = <MediaTopic>[];
    final substring = <MediaTopic>[];
    for (final topic in topics) {
      final label = topic.label.toLowerCase();
      if (label.startsWith(q)) {
        prefix.add(topic);
      } else if (label.split(RegExp('[ ,/-]+')).any((w) => w.startsWith(q))) {
        wordPrefix.add(topic);
      } else if (label.contains(q) || topic.qcode.contains(q)) {
        substring.add(topic);
      }
      if (prefix.length >= limit) break;
    }
    return [...prefix, ...wordPrefix, ...substring].take(limit).toList();
  }
}
