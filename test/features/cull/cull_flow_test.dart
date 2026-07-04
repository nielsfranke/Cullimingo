import 'dart:io';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  test(
    'open folder -> rate/flag/colour -> persisted in the read model',
    () async {
      final tmp = await Directory.systemTemp.createTemp('cull_flow');
      addTearDown(() => tmp.delete(recursive: true));
      for (final name in ['a.jpg', 'b.jpg']) {
        File(
          p.join(tmp.path, name),
        ).writeAsBytesSync(img.encodeJpg(img.Image(width: 4, height: 4)));
      }

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final importId = await container
          .read(libraryRepositoryProvider)
          .importFolder(tmp.path);
      container
          .read(workspaceProvider.notifier)
          .openImport(importId: importId, sourcePath: '/shoot', label: 'shoot');

      final photos = await db.watchPhotosForImport(importId).first;
      expect(photos, hasLength(2));

      final id = photos.first.id;
      final controller = container.read(cullControllerProvider.notifier);
      await controller.setRating(id, 4);
      await controller.setFlag(id, PickFlag.pick);
      await controller.setColor(id, ColorLabel.blue);

      // Re-read from the database: the marks persisted.
      final after = (await db.watchPhotosForImport(importId).first).firstWhere(
        (ph) => ph.id == id,
      );
      expect(after.rating, 4);
      expect(after.flag, PickFlag.pick);
      expect(after.colorLabel, ColorLabel.blue);
    },
  );
}
