import 'package:path/path.dart' as p;

/// [relPath] — a destination-relative path as the naming templates build it,
/// always with `/` separators — joined under [root] with this platform's
/// separator. `p.join(root, relPath)` would keep the `/`s inside [relPath],
/// so Windows paths (and every message showing them) came out mixed:
/// `C:\Photos\import-out/2019/2019-11-29/…`.
String joinRelPath(String root, String relPath) =>
    p.joinAll([root, ...relPath.split('/').where((s) => s.isNotEmpty)]);
