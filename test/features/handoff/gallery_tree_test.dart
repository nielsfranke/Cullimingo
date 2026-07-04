import 'package:cullimingo/features/handoff/domain/cs_models.dart';
import 'package:cullimingo/features/handoff/domain/gallery_tree.dart';
import 'package:flutter_test/flutter_test.dart';

CsGallery _g(String id, {List<CsGallery> children = const []}) => CsGallery(
  id: id,
  name: id,
  shareToken: 't$id',
  children: children,
);

void main() {
  group('flattenGalleryTree', () {
    test('depth-first order with indent depth', () {
      final tree = [
        _g(
          'a',
          children: [
            _g('a1'),
            _g('a2', children: [_g('a2x')]),
          ],
        ),
        _g('b'),
      ];
      final rows = flattenGalleryTree(tree);
      expect(
        rows.map((r) => '${r.gallery.id}@${r.depth}').toList(),
        ['a@0', 'a1@1', 'a2@1', 'a2x@2', 'b@0'],
      );
    });

    test('empty tree → empty list', () {
      expect(flattenGalleryTree(const []), isEmpty);
    });

    test('hasChildren is set on parents', () {
      final rows = flattenGalleryTree([
        _g('a', children: [_g('a1')]),
        _g('b'),
      ]);
      expect(rows[0].hasChildren, isTrue); // a
      expect(rows[1].hasChildren, isFalse); // a1
      expect(rows[2].hasChildren, isFalse); // b
    });
  });

  group('visibleGalleryRows', () {
    final tree = [
      _g(
        'a',
        children: [
          _g('a1'),
          _g('a2', children: [_g('a2x')]),
        ],
      ),
      _g('b'),
    ];

    test('nothing collapsed → same as flatten', () {
      expect(
        visibleGalleryRows(tree, {}).map((r) => r.gallery.id),
        ['a', 'a1', 'a2', 'a2x', 'b'],
      );
    });

    test('collapsing a node hides its descendants but keeps it', () {
      expect(
        visibleGalleryRows(tree, {'a2'}).map((r) => r.gallery.id),
        ['a', 'a1', 'a2', 'b'],
      );
      expect(
        visibleGalleryRows(tree, {'a'}).map((r) => r.gallery.id),
        ['a', 'b'],
      );
    });
  });

  group('searchGalleryRows', () {
    final tree = [
      _g('Wedding', children: [_g('Wedding Ceremony'), _g('Portraits')]),
      _g('Birthday'),
    ];

    test('blank query → all rows', () {
      expect(searchGalleryRows(tree, '  ').length, 4);
    });

    test('case-insensitive substring match across all depths', () {
      expect(
        searchGalleryRows(tree, 'wedd').map((r) => r.gallery.id),
        ['Wedding', 'Wedding Ceremony'],
      );
      expect(
        searchGalleryRows(tree, 'a').map((r) => r.gallery.id),
        ['Portraits', 'Birthday'],
      );
    });
  });

  group('CsGallery.fromJson', () {
    test('parses nested children and counts', () {
      final g = CsGallery.fromJson({
        'id': 'p',
        'name': 'Parent',
        'share_token': 'tp',
        'parent_id': null,
        'image_count': 3,
        'cover_image_url': '/branding/p.jpg',
        'children': [
          {
            'id': 'c',
            'name': 'Child',
            'share_token': 'tc',
            'parent_id': 'p',
            'image_count': 5,
          },
        ],
      });
      expect(g.imageCount, 3);
      expect(g.coverImageUrl, '/branding/p.jpg');
      expect(g.children.single.id, 'c');
      expect(g.children.single.imageCount, 5);
    });
  });

  group('resolveCoverUrl', () {
    test('prefixes a server-relative path', () {
      expect(
        resolveCoverUrl('https://cs.example.com/', '/branding/x.jpg'),
        'https://cs.example.com/branding/x.jpg',
      );
    });
    test('keeps an absolute url', () {
      expect(
        resolveCoverUrl('https://cs.example.com', 'https://cdn/x.jpg'),
        'https://cdn/x.jpg',
      );
    });
    test('null/empty → null', () {
      expect(resolveCoverUrl('https://cs.example.com', null), isNull);
      expect(resolveCoverUrl('https://cs.example.com', '  '), isNull);
    });
  });
}
