import 'dart:io';

import 'package:cullimingo/features/metadata/domain/media_topics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const topics = MediaTopics([
    MediaTopic(qcode: 'medtop:15000000', label: 'sport'),
    MediaTopic(
      qcode: 'medtop:20001065',
      label: 'soccer',
      parent: 'competition discipline',
    ),
    MediaTopic(
      qcode: 'medtop:20000822',
      label: 'social networking',
      parent: 'internet',
    ),
    MediaTopic(
      qcode: 'medtop:04000000',
      label: 'economy, business and finance',
    ),
  ]);

  group('search', () {
    test('label prefix ranks before word prefix and substring', () {
      final hits = topics.search('so');
      expect(hits.first.label, 'soccer');
      expect(hits.map((t) => t.label), contains('social networking'));
    });

    test('matches words inside multi-word labels', () {
      expect(topics.search('business').single.qcode, 'medtop:04000000');
    });

    test('matches the code itself and caps at limit', () {
      expect(topics.search('20001065').single.label, 'soccer');
      expect(topics.search('o', limit: 2).length, 2);
    });

    test('blank query matches nothing', () {
      expect(topics.search('  '), isEmpty);
    });
  });

  test('labelFor resolves known codes only', () {
    expect(topics.labelFor('medtop:20001065'), 'soccer');
    expect(topics.labelFor('medtop:99999999'), isNull);
  });

  test('parses the real bundled asset', () {
    final bytes = File('assets/iptc/mediatopics.tsv.gz').readAsBytesSync();
    final vocab = MediaTopics.fromGzippedTsv(bytes);
    expect(vocab.topics.length, greaterThan(1000));
    // A stable, well-known topic resolves.
    expect(vocab.search('soccer'), isNotEmpty);
    expect(vocab.topics.first.qcode, startsWith('medtop:'));
  });
}
