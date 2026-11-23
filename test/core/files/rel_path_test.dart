import 'package:cullimingo/core/files/rel_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('joins a template path with the platform separator throughout', () {
    expect(
      joinRelPath(p.join('out', 'shoot'), '2026/2026-11-23/a.jpg'),
      p.join('out', 'shoot', '2026', '2026-11-23', 'a.jpg'),
    );
  });

  test('a flat name and stray slashes join cleanly', () {
    expect(joinRelPath('out', 'a.jpg'), p.join('out', 'a.jpg'));
    expect(joinRelPath('out', '2026//a.jpg'), p.join('out', '2026', 'a.jpg'));
  });
}
