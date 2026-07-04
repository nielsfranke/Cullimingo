import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opens the on-disk SQLite database in the app support directory. The file I/O
/// happens on a background isolate via [NativeDatabase.createInBackground], so
/// the UI isolate is never blocked (`BUILD_PLAN.md` rule §0.6).
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'cullimingo.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
