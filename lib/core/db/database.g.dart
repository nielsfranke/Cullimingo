// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ImportsTable extends Imports with TableInfo<$ImportsTable, Import> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destPathMeta = const VerificationMeta(
    'destPath',
  );
  @override
  late final GeneratedColumn<String> destPath = GeneratedColumn<String>(
    'dest_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _cardLabelMeta = const VerificationMeta(
    'cardLabel',
  );
  @override
  late final GeneratedColumn<String> cardLabel = GeneratedColumn<String>(
    'card_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourcePath,
    destPath,
    createdAt,
    cardLabel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imports';
  @override
  VerificationContext validateIntegrity(
    Insertable<Import> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('dest_path')) {
      context.handle(
        _destPathMeta,
        destPath.isAcceptableOrUnknown(data['dest_path']!, _destPathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('card_label')) {
      context.handle(
        _cardLabelMeta,
        cardLabel.isAcceptableOrUnknown(data['card_label']!, _cardLabelMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Import map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Import(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      )!,
      destPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dest_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      cardLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_label'],
      ),
    );
  }

  @override
  $ImportsTable createAlias(String alias) {
    return $ImportsTable(attachedDatabase, alias);
  }
}

class Import extends DataClass implements Insertable<Import> {
  /// Primary key.
  final int id;

  /// Folder that was scanned / copied from.
  final String sourcePath;

  /// Destination root (ingest only; null for a plain open-folder).
  final String? destPath;

  /// When this import row was created.
  final DateTime createdAt;

  /// Optional human label (e.g. card name).
  final String? cardLabel;
  const Import({
    required this.id,
    required this.sourcePath,
    this.destPath,
    required this.createdAt,
    this.cardLabel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_path'] = Variable<String>(sourcePath);
    if (!nullToAbsent || destPath != null) {
      map['dest_path'] = Variable<String>(destPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || cardLabel != null) {
      map['card_label'] = Variable<String>(cardLabel);
    }
    return map;
  }

  ImportsCompanion toCompanion(bool nullToAbsent) {
    return ImportsCompanion(
      id: Value(id),
      sourcePath: Value(sourcePath),
      destPath: destPath == null && nullToAbsent
          ? const Value.absent()
          : Value(destPath),
      createdAt: Value(createdAt),
      cardLabel: cardLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(cardLabel),
    );
  }

  factory Import.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Import(
      id: serializer.fromJson<int>(json['id']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      destPath: serializer.fromJson<String?>(json['destPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      cardLabel: serializer.fromJson<String?>(json['cardLabel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'destPath': serializer.toJson<String?>(destPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'cardLabel': serializer.toJson<String?>(cardLabel),
    };
  }

  Import copyWith({
    int? id,
    String? sourcePath,
    Value<String?> destPath = const Value.absent(),
    DateTime? createdAt,
    Value<String?> cardLabel = const Value.absent(),
  }) => Import(
    id: id ?? this.id,
    sourcePath: sourcePath ?? this.sourcePath,
    destPath: destPath.present ? destPath.value : this.destPath,
    createdAt: createdAt ?? this.createdAt,
    cardLabel: cardLabel.present ? cardLabel.value : this.cardLabel,
  );
  Import copyWithCompanion(ImportsCompanion data) {
    return Import(
      id: data.id.present ? data.id.value : this.id,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      destPath: data.destPath.present ? data.destPath.value : this.destPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      cardLabel: data.cardLabel.present ? data.cardLabel.value : this.cardLabel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Import(')
          ..write('id: $id, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('destPath: $destPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('cardLabel: $cardLabel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sourcePath, destPath, createdAt, cardLabel);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Import &&
          other.id == this.id &&
          other.sourcePath == this.sourcePath &&
          other.destPath == this.destPath &&
          other.createdAt == this.createdAt &&
          other.cardLabel == this.cardLabel);
}

class ImportsCompanion extends UpdateCompanion<Import> {
  final Value<int> id;
  final Value<String> sourcePath;
  final Value<String?> destPath;
  final Value<DateTime> createdAt;
  final Value<String?> cardLabel;
  const ImportsCompanion({
    this.id = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.destPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.cardLabel = const Value.absent(),
  });
  ImportsCompanion.insert({
    this.id = const Value.absent(),
    required String sourcePath,
    this.destPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.cardLabel = const Value.absent(),
  }) : sourcePath = Value(sourcePath);
  static Insertable<Import> custom({
    Expression<int>? id,
    Expression<String>? sourcePath,
    Expression<String>? destPath,
    Expression<DateTime>? createdAt,
    Expression<String>? cardLabel,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourcePath != null) 'source_path': sourcePath,
      if (destPath != null) 'dest_path': destPath,
      if (createdAt != null) 'created_at': createdAt,
      if (cardLabel != null) 'card_label': cardLabel,
    });
  }

  ImportsCompanion copyWith({
    Value<int>? id,
    Value<String>? sourcePath,
    Value<String?>? destPath,
    Value<DateTime>? createdAt,
    Value<String?>? cardLabel,
  }) {
    return ImportsCompanion(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      destPath: destPath ?? this.destPath,
      createdAt: createdAt ?? this.createdAt,
      cardLabel: cardLabel ?? this.cardLabel,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (destPath.present) {
      map['dest_path'] = Variable<String>(destPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (cardLabel.present) {
      map['card_label'] = Variable<String>(cardLabel.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportsCompanion(')
          ..write('id: $id, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('destPath: $destPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('cardLabel: $cardLabel')
          ..write(')'))
        .toString();
  }
}

class $PhotosTable extends Photos with TableInfo<$PhotosTable, Photo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _importIdMeta = const VerificationMeta(
    'importId',
  );
  @override
  late final GeneratedColumn<int> importId = GeneratedColumn<int>(
    'import_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES imports (id)',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mtimeMeta = const VerificationMeta('mtime');
  @override
  late final GeneratedColumn<DateTime> mtime = GeneratedColumn<DateTime>(
    'mtime',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cameraMeta = const VerificationMeta('camera');
  @override
  late final GeneratedColumn<String> camera = GeneratedColumn<String>(
    'camera',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lensMeta = const VerificationMeta('lens');
  @override
  late final GeneratedColumn<String> lens = GeneratedColumn<String>(
    'lens',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orientationMeta = const VerificationMeta(
    'orientation',
  );
  @override
  late final GeneratedColumn<int> orientation = GeneratedColumn<int>(
    'orientation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _userRotationMeta = const VerificationMeta(
    'userRotation',
  );
  @override
  late final GeneratedColumn<int> userRotation = GeneratedColumn<int>(
    'user_rotation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _hasCropMeta = const VerificationMeta(
    'hasCrop',
  );
  @override
  late final GeneratedColumn<bool> hasCrop = GeneratedColumn<bool>(
    'has_crop',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_crop" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _cropLeftMeta = const VerificationMeta(
    'cropLeft',
  );
  @override
  late final GeneratedColumn<double> cropLeft = GeneratedColumn<double>(
    'crop_left',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropTopMeta = const VerificationMeta(
    'cropTop',
  );
  @override
  late final GeneratedColumn<double> cropTop = GeneratedColumn<double>(
    'crop_top',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropRightMeta = const VerificationMeta(
    'cropRight',
  );
  @override
  late final GeneratedColumn<double> cropRight = GeneratedColumn<double>(
    'crop_right',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropBottomMeta = const VerificationMeta(
    'cropBottom',
  );
  @override
  late final GeneratedColumn<double> cropBottom = GeneratedColumn<double>(
    'crop_bottom',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropAngleMeta = const VerificationMeta(
    'cropAngle',
  );
  @override
  late final GeneratedColumn<double> cropAngle = GeneratedColumn<double>(
    'crop_angle',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PickFlag, int> flag =
      GeneratedColumn<int>(
        'flag',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      ).withConverter<PickFlag>($PhotosTable.$converterflag);
  @override
  late final GeneratedColumnWithTypeConverter<ColorLabel, int> colorLabel =
      GeneratedColumn<int>(
        'color_label',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      ).withConverter<ColorLabel>($PhotosTable.$convertercolorLabel);
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> keywords =
      GeneratedColumn<String>(
        'keywords',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      ).withConverter<List<String>>($PhotosTable.$converterkeywords);
  @override
  late final GeneratedColumnWithTypeConverter<IptcCore, String> iptc =
      GeneratedColumn<String>(
        'iptc',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      ).withConverter<IptcCore>($PhotosTable.$converteriptc);
  static const VerificationMeta _hasXmpMeta = const VerificationMeta('hasXmp');
  @override
  late final GeneratedColumn<bool> hasXmp = GeneratedColumn<bool>(
    'has_xmp',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_xmp" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _xmpMtimeMeta = const VerificationMeta(
    'xmpMtime',
  );
  @override
  late final GeneratedColumn<DateTime> xmpMtime = GeneratedColumn<DateTime>(
    'xmp_mtime',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _marksMtimeMeta = const VerificationMeta(
    'marksMtime',
  );
  @override
  late final GeneratedColumn<DateTime> marksMtime = GeneratedColumn<DateTime>(
    'marks_mtime',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _xmpConflictMeta = const VerificationMeta(
    'xmpConflict',
  );
  @override
  late final GeneratedColumn<bool> xmpConflict = GeneratedColumn<bool>(
    'xmp_conflict',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("xmp_conflict" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _previewCachedMeta = const VerificationMeta(
    'previewCached',
  );
  @override
  late final GeneratedColumn<bool> previewCached = GeneratedColumn<bool>(
    'preview_cached',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("preview_cached" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isRawMeta = const VerificationMeta('isRaw');
  @override
  late final GeneratedColumn<bool> isRaw = GeneratedColumn<bool>(
    'is_raw',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_raw" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _exposureBiasMeta = const VerificationMeta(
    'exposureBias',
  );
  @override
  late final GeneratedColumn<double> exposureBias = GeneratedColumn<double>(
    'exposure_bias',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exposureTimeMeta = const VerificationMeta(
    'exposureTime',
  );
  @override
  late final GeneratedColumn<double> exposureTime = GeneratedColumn<double>(
    'exposure_time',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    importId,
    path,
    contentHash,
    mtime,
    capturedAt,
    camera,
    lens,
    width,
    height,
    latitude,
    longitude,
    orientation,
    userRotation,
    hasCrop,
    cropLeft,
    cropTop,
    cropRight,
    cropBottom,
    cropAngle,
    rating,
    flag,
    colorLabel,
    keywords,
    iptc,
    hasXmp,
    xmpMtime,
    marksMtime,
    xmpConflict,
    previewCached,
    isRaw,
    exposureBias,
    exposureTime,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<Photo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('import_id')) {
      context.handle(
        _importIdMeta,
        importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    }
    if (data.containsKey('mtime')) {
      context.handle(
        _mtimeMeta,
        mtime.isAcceptableOrUnknown(data['mtime']!, _mtimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mtimeMeta);
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    }
    if (data.containsKey('camera')) {
      context.handle(
        _cameraMeta,
        camera.isAcceptableOrUnknown(data['camera']!, _cameraMeta),
      );
    }
    if (data.containsKey('lens')) {
      context.handle(
        _lensMeta,
        lens.isAcceptableOrUnknown(data['lens']!, _lensMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('orientation')) {
      context.handle(
        _orientationMeta,
        orientation.isAcceptableOrUnknown(
          data['orientation']!,
          _orientationMeta,
        ),
      );
    }
    if (data.containsKey('user_rotation')) {
      context.handle(
        _userRotationMeta,
        userRotation.isAcceptableOrUnknown(
          data['user_rotation']!,
          _userRotationMeta,
        ),
      );
    }
    if (data.containsKey('has_crop')) {
      context.handle(
        _hasCropMeta,
        hasCrop.isAcceptableOrUnknown(data['has_crop']!, _hasCropMeta),
      );
    }
    if (data.containsKey('crop_left')) {
      context.handle(
        _cropLeftMeta,
        cropLeft.isAcceptableOrUnknown(data['crop_left']!, _cropLeftMeta),
      );
    }
    if (data.containsKey('crop_top')) {
      context.handle(
        _cropTopMeta,
        cropTop.isAcceptableOrUnknown(data['crop_top']!, _cropTopMeta),
      );
    }
    if (data.containsKey('crop_right')) {
      context.handle(
        _cropRightMeta,
        cropRight.isAcceptableOrUnknown(data['crop_right']!, _cropRightMeta),
      );
    }
    if (data.containsKey('crop_bottom')) {
      context.handle(
        _cropBottomMeta,
        cropBottom.isAcceptableOrUnknown(data['crop_bottom']!, _cropBottomMeta),
      );
    }
    if (data.containsKey('crop_angle')) {
      context.handle(
        _cropAngleMeta,
        cropAngle.isAcceptableOrUnknown(data['crop_angle']!, _cropAngleMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('has_xmp')) {
      context.handle(
        _hasXmpMeta,
        hasXmp.isAcceptableOrUnknown(data['has_xmp']!, _hasXmpMeta),
      );
    }
    if (data.containsKey('xmp_mtime')) {
      context.handle(
        _xmpMtimeMeta,
        xmpMtime.isAcceptableOrUnknown(data['xmp_mtime']!, _xmpMtimeMeta),
      );
    }
    if (data.containsKey('marks_mtime')) {
      context.handle(
        _marksMtimeMeta,
        marksMtime.isAcceptableOrUnknown(data['marks_mtime']!, _marksMtimeMeta),
      );
    }
    if (data.containsKey('xmp_conflict')) {
      context.handle(
        _xmpConflictMeta,
        xmpConflict.isAcceptableOrUnknown(
          data['xmp_conflict']!,
          _xmpConflictMeta,
        ),
      );
    }
    if (data.containsKey('preview_cached')) {
      context.handle(
        _previewCachedMeta,
        previewCached.isAcceptableOrUnknown(
          data['preview_cached']!,
          _previewCachedMeta,
        ),
      );
    }
    if (data.containsKey('is_raw')) {
      context.handle(
        _isRawMeta,
        isRaw.isAcceptableOrUnknown(data['is_raw']!, _isRawMeta),
      );
    }
    if (data.containsKey('exposure_bias')) {
      context.handle(
        _exposureBiasMeta,
        exposureBias.isAcceptableOrUnknown(
          data['exposure_bias']!,
          _exposureBiasMeta,
        ),
      );
    }
    if (data.containsKey('exposure_time')) {
      context.handle(
        _exposureTimeMeta,
        exposureTime.isAcceptableOrUnknown(
          data['exposure_time']!,
          _exposureTimeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Photo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Photo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      importId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}import_id'],
      ),
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      mtime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}mtime'],
      )!,
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      ),
      camera: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}camera'],
      ),
      lens: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lens'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      orientation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orientation'],
      )!,
      userRotation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_rotation'],
      )!,
      hasCrop: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_crop'],
      )!,
      cropLeft: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}crop_left'],
      ),
      cropTop: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}crop_top'],
      ),
      cropRight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}crop_right'],
      ),
      cropBottom: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}crop_bottom'],
      ),
      cropAngle: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}crop_angle'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      )!,
      flag: $PhotosTable.$converterflag.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}flag'],
        )!,
      ),
      colorLabel: $PhotosTable.$convertercolorLabel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}color_label'],
        )!,
      ),
      keywords: $PhotosTable.$converterkeywords.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}keywords'],
        )!,
      ),
      iptc: $PhotosTable.$converteriptc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}iptc'],
        )!,
      ),
      hasXmp: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_xmp'],
      )!,
      xmpMtime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}xmp_mtime'],
      ),
      marksMtime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}marks_mtime'],
      ),
      xmpConflict: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}xmp_conflict'],
      )!,
      previewCached: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}preview_cached'],
      )!,
      isRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_raw'],
      )!,
      exposureBias: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}exposure_bias'],
      ),
      exposureTime: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}exposure_time'],
      ),
    );
  }

  @override
  $PhotosTable createAlias(String alias) {
    return $PhotosTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PickFlag, int, int> $converterflag =
      const EnumIndexConverter<PickFlag>(PickFlag.values);
  static JsonTypeConverter2<ColorLabel, int, int> $convertercolorLabel =
      const EnumIndexConverter<ColorLabel>(ColorLabel.values);
  static TypeConverter<List<String>, String> $converterkeywords =
      const KeywordsConverter();
  static TypeConverter<IptcCore, String> $converteriptc =
      const IptcCoreConverter();
}

class Photo extends DataClass implements Insertable<Photo> {
  /// Primary key.
  final int id;

  /// Owning import.
  final int? importId;

  /// Absolute path to the image file (RAW or JPEG).
  final String path;

  /// Fast content hash for cache keys / ingest verification (filled lazily).
  final String? contentHash;

  /// File modification time — part of the cache key.
  final DateTime mtime;

  /// EXIF DateTimeOriginal, when known. Drives capture-time sort.
  final DateTime? capturedAt;

  /// Camera model from EXIF.
  final String? camera;

  /// Lens model from EXIF.
  final String? lens;

  /// Pixel width of the full image, when known.
  final int? width;

  /// Pixel height of the full image, when known.
  final int? height;

  /// GPS latitude in decimal degrees (south negative), from EXIF.
  final double? latitude;

  /// GPS longitude in decimal degrees (west negative), from EXIF.
  final double? longitude;

  /// EXIF orientation (1–8) as read from the file; 1 = normal. The baseline the
  /// preview is already rendered at. See [userRotation] for the user's edit.
  final int orientation;

  /// Extra clockwise quarter-turns (0–3) the user applied on top of the file's
  /// [orientation]. Applied at the widget layer + on export; written through to
  /// the XMP sidecar (and, for JPEG, the embedded EXIF) for interop.
  final int userRotation;

  /// Whether the source carries a non-destructive Lightroom/Camera-Raw crop
  /// (`crs:HasCrop`). Read-only, surfaced in the inspector + loupe.
  final bool hasCrop;

  /// The crop rectangle edges + straighten angle from `crs:` (fractions 0–1 of
  /// the frame; angle in degrees). Null when [hasCrop] is false.
  final double? cropLeft;

  /// See [cropLeft].
  final double? cropTop;

  /// See [cropLeft].
  final double? cropRight;

  /// See [cropLeft].
  final double? cropBottom;

  /// See [cropLeft].
  final double? cropAngle;

  /// Star rating 0–5.
  final int rating;

  /// Pick/reject flag, stored as [PickFlag] index.
  final PickFlag flag;

  /// Colour label, stored as [ColorLabel] index.
  final ColorLabel colorLabel;

  /// Keywords (`dc:subject` bag), stored as a JSON array (Phase 4).
  final List<String> keywords;

  /// Descriptive IPTC Core fields (caption, creator, credit, location…),
  /// stored as a compact JSON object (Phase 9 Layer 1 / Phase 4b).
  final IptcCore iptc;

  /// True if a `.xmp` sidecar exists for this file (Phase 4).
  final bool hasXmp;

  /// Filesystem mtime of the XMP sidecar the last time Cullimingo read or wrote
  /// it. Null = never synced. Used to detect external edits (Phase 4 sync).
  final DateTime? xmpMtime;

  /// When the cull marks were last changed *inside* Cullimingo. Compared with
  /// [xmpMtime] for last-writer-wins and conflict detection (Phase 4 sync).
  final DateTime? marksMtime;

  /// True when a sidecar was edited externally while Cullimingo also had local
  /// changes since the last sync — surfaced to the user (Phase 4 sync).
  final bool xmpConflict;

  /// True once a disk-cached preview has been written (Phase 2).
  final bool previewCached;

  /// True for RAW files (embedded-preview path); false for plain JPEG/PNG.
  final bool isRaw;

  /// Exposure compensation in EV (`EXIF ExposureBiasValue`), when the file
  /// exposes it. Feeds exposure-bracket detection. Null when the tag is absent
  /// or unreadable (e.g. Fuji `.RAF`, which falls back to [exposureTime]).
  final double? exposureBias;

  /// Shutter speed in seconds (`EXIF ExposureTime` / LibRaw `shutter`). Bracket
  /// detection uses it both as the varying signal (when [exposureBias] is
  /// absent) and to size the shutter-aware time-gap tolerance. Sentinel: NULL =
  /// not yet EXIF-scanned, 0.0 = scanned but the tag was absent (0 s is never a
  /// real shutter speed), which is what lets the legacy backfill run once.
  final double? exposureTime;
  const Photo({
    required this.id,
    this.importId,
    required this.path,
    this.contentHash,
    required this.mtime,
    this.capturedAt,
    this.camera,
    this.lens,
    this.width,
    this.height,
    this.latitude,
    this.longitude,
    required this.orientation,
    required this.userRotation,
    required this.hasCrop,
    this.cropLeft,
    this.cropTop,
    this.cropRight,
    this.cropBottom,
    this.cropAngle,
    required this.rating,
    required this.flag,
    required this.colorLabel,
    required this.keywords,
    required this.iptc,
    required this.hasXmp,
    this.xmpMtime,
    this.marksMtime,
    required this.xmpConflict,
    required this.previewCached,
    required this.isRaw,
    this.exposureBias,
    this.exposureTime,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || importId != null) {
      map['import_id'] = Variable<int>(importId);
    }
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    map['mtime'] = Variable<DateTime>(mtime);
    if (!nullToAbsent || capturedAt != null) {
      map['captured_at'] = Variable<DateTime>(capturedAt);
    }
    if (!nullToAbsent || camera != null) {
      map['camera'] = Variable<String>(camera);
    }
    if (!nullToAbsent || lens != null) {
      map['lens'] = Variable<String>(lens);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    map['orientation'] = Variable<int>(orientation);
    map['user_rotation'] = Variable<int>(userRotation);
    map['has_crop'] = Variable<bool>(hasCrop);
    if (!nullToAbsent || cropLeft != null) {
      map['crop_left'] = Variable<double>(cropLeft);
    }
    if (!nullToAbsent || cropTop != null) {
      map['crop_top'] = Variable<double>(cropTop);
    }
    if (!nullToAbsent || cropRight != null) {
      map['crop_right'] = Variable<double>(cropRight);
    }
    if (!nullToAbsent || cropBottom != null) {
      map['crop_bottom'] = Variable<double>(cropBottom);
    }
    if (!nullToAbsent || cropAngle != null) {
      map['crop_angle'] = Variable<double>(cropAngle);
    }
    map['rating'] = Variable<int>(rating);
    {
      map['flag'] = Variable<int>($PhotosTable.$converterflag.toSql(flag));
    }
    {
      map['color_label'] = Variable<int>(
        $PhotosTable.$convertercolorLabel.toSql(colorLabel),
      );
    }
    {
      map['keywords'] = Variable<String>(
        $PhotosTable.$converterkeywords.toSql(keywords),
      );
    }
    {
      map['iptc'] = Variable<String>($PhotosTable.$converteriptc.toSql(iptc));
    }
    map['has_xmp'] = Variable<bool>(hasXmp);
    if (!nullToAbsent || xmpMtime != null) {
      map['xmp_mtime'] = Variable<DateTime>(xmpMtime);
    }
    if (!nullToAbsent || marksMtime != null) {
      map['marks_mtime'] = Variable<DateTime>(marksMtime);
    }
    map['xmp_conflict'] = Variable<bool>(xmpConflict);
    map['preview_cached'] = Variable<bool>(previewCached);
    map['is_raw'] = Variable<bool>(isRaw);
    if (!nullToAbsent || exposureBias != null) {
      map['exposure_bias'] = Variable<double>(exposureBias);
    }
    if (!nullToAbsent || exposureTime != null) {
      map['exposure_time'] = Variable<double>(exposureTime);
    }
    return map;
  }

  PhotosCompanion toCompanion(bool nullToAbsent) {
    return PhotosCompanion(
      id: Value(id),
      importId: importId == null && nullToAbsent
          ? const Value.absent()
          : Value(importId),
      path: Value(path),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      mtime: Value(mtime),
      capturedAt: capturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(capturedAt),
      camera: camera == null && nullToAbsent
          ? const Value.absent()
          : Value(camera),
      lens: lens == null && nullToAbsent ? const Value.absent() : Value(lens),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      orientation: Value(orientation),
      userRotation: Value(userRotation),
      hasCrop: Value(hasCrop),
      cropLeft: cropLeft == null && nullToAbsent
          ? const Value.absent()
          : Value(cropLeft),
      cropTop: cropTop == null && nullToAbsent
          ? const Value.absent()
          : Value(cropTop),
      cropRight: cropRight == null && nullToAbsent
          ? const Value.absent()
          : Value(cropRight),
      cropBottom: cropBottom == null && nullToAbsent
          ? const Value.absent()
          : Value(cropBottom),
      cropAngle: cropAngle == null && nullToAbsent
          ? const Value.absent()
          : Value(cropAngle),
      rating: Value(rating),
      flag: Value(flag),
      colorLabel: Value(colorLabel),
      keywords: Value(keywords),
      iptc: Value(iptc),
      hasXmp: Value(hasXmp),
      xmpMtime: xmpMtime == null && nullToAbsent
          ? const Value.absent()
          : Value(xmpMtime),
      marksMtime: marksMtime == null && nullToAbsent
          ? const Value.absent()
          : Value(marksMtime),
      xmpConflict: Value(xmpConflict),
      previewCached: Value(previewCached),
      isRaw: Value(isRaw),
      exposureBias: exposureBias == null && nullToAbsent
          ? const Value.absent()
          : Value(exposureBias),
      exposureTime: exposureTime == null && nullToAbsent
          ? const Value.absent()
          : Value(exposureTime),
    );
  }

  factory Photo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Photo(
      id: serializer.fromJson<int>(json['id']),
      importId: serializer.fromJson<int?>(json['importId']),
      path: serializer.fromJson<String>(json['path']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      mtime: serializer.fromJson<DateTime>(json['mtime']),
      capturedAt: serializer.fromJson<DateTime?>(json['capturedAt']),
      camera: serializer.fromJson<String?>(json['camera']),
      lens: serializer.fromJson<String?>(json['lens']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      orientation: serializer.fromJson<int>(json['orientation']),
      userRotation: serializer.fromJson<int>(json['userRotation']),
      hasCrop: serializer.fromJson<bool>(json['hasCrop']),
      cropLeft: serializer.fromJson<double?>(json['cropLeft']),
      cropTop: serializer.fromJson<double?>(json['cropTop']),
      cropRight: serializer.fromJson<double?>(json['cropRight']),
      cropBottom: serializer.fromJson<double?>(json['cropBottom']),
      cropAngle: serializer.fromJson<double?>(json['cropAngle']),
      rating: serializer.fromJson<int>(json['rating']),
      flag: $PhotosTable.$converterflag.fromJson(
        serializer.fromJson<int>(json['flag']),
      ),
      colorLabel: $PhotosTable.$convertercolorLabel.fromJson(
        serializer.fromJson<int>(json['colorLabel']),
      ),
      keywords: serializer.fromJson<List<String>>(json['keywords']),
      iptc: serializer.fromJson<IptcCore>(json['iptc']),
      hasXmp: serializer.fromJson<bool>(json['hasXmp']),
      xmpMtime: serializer.fromJson<DateTime?>(json['xmpMtime']),
      marksMtime: serializer.fromJson<DateTime?>(json['marksMtime']),
      xmpConflict: serializer.fromJson<bool>(json['xmpConflict']),
      previewCached: serializer.fromJson<bool>(json['previewCached']),
      isRaw: serializer.fromJson<bool>(json['isRaw']),
      exposureBias: serializer.fromJson<double?>(json['exposureBias']),
      exposureTime: serializer.fromJson<double?>(json['exposureTime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'importId': serializer.toJson<int?>(importId),
      'path': serializer.toJson<String>(path),
      'contentHash': serializer.toJson<String?>(contentHash),
      'mtime': serializer.toJson<DateTime>(mtime),
      'capturedAt': serializer.toJson<DateTime?>(capturedAt),
      'camera': serializer.toJson<String?>(camera),
      'lens': serializer.toJson<String?>(lens),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'orientation': serializer.toJson<int>(orientation),
      'userRotation': serializer.toJson<int>(userRotation),
      'hasCrop': serializer.toJson<bool>(hasCrop),
      'cropLeft': serializer.toJson<double?>(cropLeft),
      'cropTop': serializer.toJson<double?>(cropTop),
      'cropRight': serializer.toJson<double?>(cropRight),
      'cropBottom': serializer.toJson<double?>(cropBottom),
      'cropAngle': serializer.toJson<double?>(cropAngle),
      'rating': serializer.toJson<int>(rating),
      'flag': serializer.toJson<int>($PhotosTable.$converterflag.toJson(flag)),
      'colorLabel': serializer.toJson<int>(
        $PhotosTable.$convertercolorLabel.toJson(colorLabel),
      ),
      'keywords': serializer.toJson<List<String>>(keywords),
      'iptc': serializer.toJson<IptcCore>(iptc),
      'hasXmp': serializer.toJson<bool>(hasXmp),
      'xmpMtime': serializer.toJson<DateTime?>(xmpMtime),
      'marksMtime': serializer.toJson<DateTime?>(marksMtime),
      'xmpConflict': serializer.toJson<bool>(xmpConflict),
      'previewCached': serializer.toJson<bool>(previewCached),
      'isRaw': serializer.toJson<bool>(isRaw),
      'exposureBias': serializer.toJson<double?>(exposureBias),
      'exposureTime': serializer.toJson<double?>(exposureTime),
    };
  }

  Photo copyWith({
    int? id,
    Value<int?> importId = const Value.absent(),
    String? path,
    Value<String?> contentHash = const Value.absent(),
    DateTime? mtime,
    Value<DateTime?> capturedAt = const Value.absent(),
    Value<String?> camera = const Value.absent(),
    Value<String?> lens = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    int? orientation,
    int? userRotation,
    bool? hasCrop,
    Value<double?> cropLeft = const Value.absent(),
    Value<double?> cropTop = const Value.absent(),
    Value<double?> cropRight = const Value.absent(),
    Value<double?> cropBottom = const Value.absent(),
    Value<double?> cropAngle = const Value.absent(),
    int? rating,
    PickFlag? flag,
    ColorLabel? colorLabel,
    List<String>? keywords,
    IptcCore? iptc,
    bool? hasXmp,
    Value<DateTime?> xmpMtime = const Value.absent(),
    Value<DateTime?> marksMtime = const Value.absent(),
    bool? xmpConflict,
    bool? previewCached,
    bool? isRaw,
    Value<double?> exposureBias = const Value.absent(),
    Value<double?> exposureTime = const Value.absent(),
  }) => Photo(
    id: id ?? this.id,
    importId: importId.present ? importId.value : this.importId,
    path: path ?? this.path,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    mtime: mtime ?? this.mtime,
    capturedAt: capturedAt.present ? capturedAt.value : this.capturedAt,
    camera: camera.present ? camera.value : this.camera,
    lens: lens.present ? lens.value : this.lens,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    orientation: orientation ?? this.orientation,
    userRotation: userRotation ?? this.userRotation,
    hasCrop: hasCrop ?? this.hasCrop,
    cropLeft: cropLeft.present ? cropLeft.value : this.cropLeft,
    cropTop: cropTop.present ? cropTop.value : this.cropTop,
    cropRight: cropRight.present ? cropRight.value : this.cropRight,
    cropBottom: cropBottom.present ? cropBottom.value : this.cropBottom,
    cropAngle: cropAngle.present ? cropAngle.value : this.cropAngle,
    rating: rating ?? this.rating,
    flag: flag ?? this.flag,
    colorLabel: colorLabel ?? this.colorLabel,
    keywords: keywords ?? this.keywords,
    iptc: iptc ?? this.iptc,
    hasXmp: hasXmp ?? this.hasXmp,
    xmpMtime: xmpMtime.present ? xmpMtime.value : this.xmpMtime,
    marksMtime: marksMtime.present ? marksMtime.value : this.marksMtime,
    xmpConflict: xmpConflict ?? this.xmpConflict,
    previewCached: previewCached ?? this.previewCached,
    isRaw: isRaw ?? this.isRaw,
    exposureBias: exposureBias.present ? exposureBias.value : this.exposureBias,
    exposureTime: exposureTime.present ? exposureTime.value : this.exposureTime,
  );
  Photo copyWithCompanion(PhotosCompanion data) {
    return Photo(
      id: data.id.present ? data.id.value : this.id,
      importId: data.importId.present ? data.importId.value : this.importId,
      path: data.path.present ? data.path.value : this.path,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      mtime: data.mtime.present ? data.mtime.value : this.mtime,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      camera: data.camera.present ? data.camera.value : this.camera,
      lens: data.lens.present ? data.lens.value : this.lens,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      orientation: data.orientation.present
          ? data.orientation.value
          : this.orientation,
      userRotation: data.userRotation.present
          ? data.userRotation.value
          : this.userRotation,
      hasCrop: data.hasCrop.present ? data.hasCrop.value : this.hasCrop,
      cropLeft: data.cropLeft.present ? data.cropLeft.value : this.cropLeft,
      cropTop: data.cropTop.present ? data.cropTop.value : this.cropTop,
      cropRight: data.cropRight.present ? data.cropRight.value : this.cropRight,
      cropBottom: data.cropBottom.present
          ? data.cropBottom.value
          : this.cropBottom,
      cropAngle: data.cropAngle.present ? data.cropAngle.value : this.cropAngle,
      rating: data.rating.present ? data.rating.value : this.rating,
      flag: data.flag.present ? data.flag.value : this.flag,
      colorLabel: data.colorLabel.present
          ? data.colorLabel.value
          : this.colorLabel,
      keywords: data.keywords.present ? data.keywords.value : this.keywords,
      iptc: data.iptc.present ? data.iptc.value : this.iptc,
      hasXmp: data.hasXmp.present ? data.hasXmp.value : this.hasXmp,
      xmpMtime: data.xmpMtime.present ? data.xmpMtime.value : this.xmpMtime,
      marksMtime: data.marksMtime.present
          ? data.marksMtime.value
          : this.marksMtime,
      xmpConflict: data.xmpConflict.present
          ? data.xmpConflict.value
          : this.xmpConflict,
      previewCached: data.previewCached.present
          ? data.previewCached.value
          : this.previewCached,
      isRaw: data.isRaw.present ? data.isRaw.value : this.isRaw,
      exposureBias: data.exposureBias.present
          ? data.exposureBias.value
          : this.exposureBias,
      exposureTime: data.exposureTime.present
          ? data.exposureTime.value
          : this.exposureTime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Photo(')
          ..write('id: $id, ')
          ..write('importId: $importId, ')
          ..write('path: $path, ')
          ..write('contentHash: $contentHash, ')
          ..write('mtime: $mtime, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('camera: $camera, ')
          ..write('lens: $lens, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('orientation: $orientation, ')
          ..write('userRotation: $userRotation, ')
          ..write('hasCrop: $hasCrop, ')
          ..write('cropLeft: $cropLeft, ')
          ..write('cropTop: $cropTop, ')
          ..write('cropRight: $cropRight, ')
          ..write('cropBottom: $cropBottom, ')
          ..write('cropAngle: $cropAngle, ')
          ..write('rating: $rating, ')
          ..write('flag: $flag, ')
          ..write('colorLabel: $colorLabel, ')
          ..write('keywords: $keywords, ')
          ..write('iptc: $iptc, ')
          ..write('hasXmp: $hasXmp, ')
          ..write('xmpMtime: $xmpMtime, ')
          ..write('marksMtime: $marksMtime, ')
          ..write('xmpConflict: $xmpConflict, ')
          ..write('previewCached: $previewCached, ')
          ..write('isRaw: $isRaw, ')
          ..write('exposureBias: $exposureBias, ')
          ..write('exposureTime: $exposureTime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    importId,
    path,
    contentHash,
    mtime,
    capturedAt,
    camera,
    lens,
    width,
    height,
    latitude,
    longitude,
    orientation,
    userRotation,
    hasCrop,
    cropLeft,
    cropTop,
    cropRight,
    cropBottom,
    cropAngle,
    rating,
    flag,
    colorLabel,
    keywords,
    iptc,
    hasXmp,
    xmpMtime,
    marksMtime,
    xmpConflict,
    previewCached,
    isRaw,
    exposureBias,
    exposureTime,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Photo &&
          other.id == this.id &&
          other.importId == this.importId &&
          other.path == this.path &&
          other.contentHash == this.contentHash &&
          other.mtime == this.mtime &&
          other.capturedAt == this.capturedAt &&
          other.camera == this.camera &&
          other.lens == this.lens &&
          other.width == this.width &&
          other.height == this.height &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.orientation == this.orientation &&
          other.userRotation == this.userRotation &&
          other.hasCrop == this.hasCrop &&
          other.cropLeft == this.cropLeft &&
          other.cropTop == this.cropTop &&
          other.cropRight == this.cropRight &&
          other.cropBottom == this.cropBottom &&
          other.cropAngle == this.cropAngle &&
          other.rating == this.rating &&
          other.flag == this.flag &&
          other.colorLabel == this.colorLabel &&
          other.keywords == this.keywords &&
          other.iptc == this.iptc &&
          other.hasXmp == this.hasXmp &&
          other.xmpMtime == this.xmpMtime &&
          other.marksMtime == this.marksMtime &&
          other.xmpConflict == this.xmpConflict &&
          other.previewCached == this.previewCached &&
          other.isRaw == this.isRaw &&
          other.exposureBias == this.exposureBias &&
          other.exposureTime == this.exposureTime);
}

class PhotosCompanion extends UpdateCompanion<Photo> {
  final Value<int> id;
  final Value<int?> importId;
  final Value<String> path;
  final Value<String?> contentHash;
  final Value<DateTime> mtime;
  final Value<DateTime?> capturedAt;
  final Value<String?> camera;
  final Value<String?> lens;
  final Value<int?> width;
  final Value<int?> height;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<int> orientation;
  final Value<int> userRotation;
  final Value<bool> hasCrop;
  final Value<double?> cropLeft;
  final Value<double?> cropTop;
  final Value<double?> cropRight;
  final Value<double?> cropBottom;
  final Value<double?> cropAngle;
  final Value<int> rating;
  final Value<PickFlag> flag;
  final Value<ColorLabel> colorLabel;
  final Value<List<String>> keywords;
  final Value<IptcCore> iptc;
  final Value<bool> hasXmp;
  final Value<DateTime?> xmpMtime;
  final Value<DateTime?> marksMtime;
  final Value<bool> xmpConflict;
  final Value<bool> previewCached;
  final Value<bool> isRaw;
  final Value<double?> exposureBias;
  final Value<double?> exposureTime;
  const PhotosCompanion({
    this.id = const Value.absent(),
    this.importId = const Value.absent(),
    this.path = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.mtime = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.camera = const Value.absent(),
    this.lens = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.orientation = const Value.absent(),
    this.userRotation = const Value.absent(),
    this.hasCrop = const Value.absent(),
    this.cropLeft = const Value.absent(),
    this.cropTop = const Value.absent(),
    this.cropRight = const Value.absent(),
    this.cropBottom = const Value.absent(),
    this.cropAngle = const Value.absent(),
    this.rating = const Value.absent(),
    this.flag = const Value.absent(),
    this.colorLabel = const Value.absent(),
    this.keywords = const Value.absent(),
    this.iptc = const Value.absent(),
    this.hasXmp = const Value.absent(),
    this.xmpMtime = const Value.absent(),
    this.marksMtime = const Value.absent(),
    this.xmpConflict = const Value.absent(),
    this.previewCached = const Value.absent(),
    this.isRaw = const Value.absent(),
    this.exposureBias = const Value.absent(),
    this.exposureTime = const Value.absent(),
  });
  PhotosCompanion.insert({
    this.id = const Value.absent(),
    this.importId = const Value.absent(),
    required String path,
    this.contentHash = const Value.absent(),
    required DateTime mtime,
    this.capturedAt = const Value.absent(),
    this.camera = const Value.absent(),
    this.lens = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.orientation = const Value.absent(),
    this.userRotation = const Value.absent(),
    this.hasCrop = const Value.absent(),
    this.cropLeft = const Value.absent(),
    this.cropTop = const Value.absent(),
    this.cropRight = const Value.absent(),
    this.cropBottom = const Value.absent(),
    this.cropAngle = const Value.absent(),
    this.rating = const Value.absent(),
    this.flag = const Value.absent(),
    this.colorLabel = const Value.absent(),
    this.keywords = const Value.absent(),
    this.iptc = const Value.absent(),
    this.hasXmp = const Value.absent(),
    this.xmpMtime = const Value.absent(),
    this.marksMtime = const Value.absent(),
    this.xmpConflict = const Value.absent(),
    this.previewCached = const Value.absent(),
    this.isRaw = const Value.absent(),
    this.exposureBias = const Value.absent(),
    this.exposureTime = const Value.absent(),
  }) : path = Value(path),
       mtime = Value(mtime);
  static Insertable<Photo> custom({
    Expression<int>? id,
    Expression<int>? importId,
    Expression<String>? path,
    Expression<String>? contentHash,
    Expression<DateTime>? mtime,
    Expression<DateTime>? capturedAt,
    Expression<String>? camera,
    Expression<String>? lens,
    Expression<int>? width,
    Expression<int>? height,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? orientation,
    Expression<int>? userRotation,
    Expression<bool>? hasCrop,
    Expression<double>? cropLeft,
    Expression<double>? cropTop,
    Expression<double>? cropRight,
    Expression<double>? cropBottom,
    Expression<double>? cropAngle,
    Expression<int>? rating,
    Expression<int>? flag,
    Expression<int>? colorLabel,
    Expression<String>? keywords,
    Expression<String>? iptc,
    Expression<bool>? hasXmp,
    Expression<DateTime>? xmpMtime,
    Expression<DateTime>? marksMtime,
    Expression<bool>? xmpConflict,
    Expression<bool>? previewCached,
    Expression<bool>? isRaw,
    Expression<double>? exposureBias,
    Expression<double>? exposureTime,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (importId != null) 'import_id': importId,
      if (path != null) 'path': path,
      if (contentHash != null) 'content_hash': contentHash,
      if (mtime != null) 'mtime': mtime,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (camera != null) 'camera': camera,
      if (lens != null) 'lens': lens,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (orientation != null) 'orientation': orientation,
      if (userRotation != null) 'user_rotation': userRotation,
      if (hasCrop != null) 'has_crop': hasCrop,
      if (cropLeft != null) 'crop_left': cropLeft,
      if (cropTop != null) 'crop_top': cropTop,
      if (cropRight != null) 'crop_right': cropRight,
      if (cropBottom != null) 'crop_bottom': cropBottom,
      if (cropAngle != null) 'crop_angle': cropAngle,
      if (rating != null) 'rating': rating,
      if (flag != null) 'flag': flag,
      if (colorLabel != null) 'color_label': colorLabel,
      if (keywords != null) 'keywords': keywords,
      if (iptc != null) 'iptc': iptc,
      if (hasXmp != null) 'has_xmp': hasXmp,
      if (xmpMtime != null) 'xmp_mtime': xmpMtime,
      if (marksMtime != null) 'marks_mtime': marksMtime,
      if (xmpConflict != null) 'xmp_conflict': xmpConflict,
      if (previewCached != null) 'preview_cached': previewCached,
      if (isRaw != null) 'is_raw': isRaw,
      if (exposureBias != null) 'exposure_bias': exposureBias,
      if (exposureTime != null) 'exposure_time': exposureTime,
    });
  }

  PhotosCompanion copyWith({
    Value<int>? id,
    Value<int?>? importId,
    Value<String>? path,
    Value<String?>? contentHash,
    Value<DateTime>? mtime,
    Value<DateTime?>? capturedAt,
    Value<String?>? camera,
    Value<String?>? lens,
    Value<int?>? width,
    Value<int?>? height,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<int>? orientation,
    Value<int>? userRotation,
    Value<bool>? hasCrop,
    Value<double?>? cropLeft,
    Value<double?>? cropTop,
    Value<double?>? cropRight,
    Value<double?>? cropBottom,
    Value<double?>? cropAngle,
    Value<int>? rating,
    Value<PickFlag>? flag,
    Value<ColorLabel>? colorLabel,
    Value<List<String>>? keywords,
    Value<IptcCore>? iptc,
    Value<bool>? hasXmp,
    Value<DateTime?>? xmpMtime,
    Value<DateTime?>? marksMtime,
    Value<bool>? xmpConflict,
    Value<bool>? previewCached,
    Value<bool>? isRaw,
    Value<double?>? exposureBias,
    Value<double?>? exposureTime,
  }) {
    return PhotosCompanion(
      id: id ?? this.id,
      importId: importId ?? this.importId,
      path: path ?? this.path,
      contentHash: contentHash ?? this.contentHash,
      mtime: mtime ?? this.mtime,
      capturedAt: capturedAt ?? this.capturedAt,
      camera: camera ?? this.camera,
      lens: lens ?? this.lens,
      width: width ?? this.width,
      height: height ?? this.height,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      orientation: orientation ?? this.orientation,
      userRotation: userRotation ?? this.userRotation,
      hasCrop: hasCrop ?? this.hasCrop,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropRight: cropRight ?? this.cropRight,
      cropBottom: cropBottom ?? this.cropBottom,
      cropAngle: cropAngle ?? this.cropAngle,
      rating: rating ?? this.rating,
      flag: flag ?? this.flag,
      colorLabel: colorLabel ?? this.colorLabel,
      keywords: keywords ?? this.keywords,
      iptc: iptc ?? this.iptc,
      hasXmp: hasXmp ?? this.hasXmp,
      xmpMtime: xmpMtime ?? this.xmpMtime,
      marksMtime: marksMtime ?? this.marksMtime,
      xmpConflict: xmpConflict ?? this.xmpConflict,
      previewCached: previewCached ?? this.previewCached,
      isRaw: isRaw ?? this.isRaw,
      exposureBias: exposureBias ?? this.exposureBias,
      exposureTime: exposureTime ?? this.exposureTime,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (importId.present) {
      map['import_id'] = Variable<int>(importId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (mtime.present) {
      map['mtime'] = Variable<DateTime>(mtime.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (camera.present) {
      map['camera'] = Variable<String>(camera.value);
    }
    if (lens.present) {
      map['lens'] = Variable<String>(lens.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (orientation.present) {
      map['orientation'] = Variable<int>(orientation.value);
    }
    if (userRotation.present) {
      map['user_rotation'] = Variable<int>(userRotation.value);
    }
    if (hasCrop.present) {
      map['has_crop'] = Variable<bool>(hasCrop.value);
    }
    if (cropLeft.present) {
      map['crop_left'] = Variable<double>(cropLeft.value);
    }
    if (cropTop.present) {
      map['crop_top'] = Variable<double>(cropTop.value);
    }
    if (cropRight.present) {
      map['crop_right'] = Variable<double>(cropRight.value);
    }
    if (cropBottom.present) {
      map['crop_bottom'] = Variable<double>(cropBottom.value);
    }
    if (cropAngle.present) {
      map['crop_angle'] = Variable<double>(cropAngle.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (flag.present) {
      map['flag'] = Variable<int>(
        $PhotosTable.$converterflag.toSql(flag.value),
      );
    }
    if (colorLabel.present) {
      map['color_label'] = Variable<int>(
        $PhotosTable.$convertercolorLabel.toSql(colorLabel.value),
      );
    }
    if (keywords.present) {
      map['keywords'] = Variable<String>(
        $PhotosTable.$converterkeywords.toSql(keywords.value),
      );
    }
    if (iptc.present) {
      map['iptc'] = Variable<String>(
        $PhotosTable.$converteriptc.toSql(iptc.value),
      );
    }
    if (hasXmp.present) {
      map['has_xmp'] = Variable<bool>(hasXmp.value);
    }
    if (xmpMtime.present) {
      map['xmp_mtime'] = Variable<DateTime>(xmpMtime.value);
    }
    if (marksMtime.present) {
      map['marks_mtime'] = Variable<DateTime>(marksMtime.value);
    }
    if (xmpConflict.present) {
      map['xmp_conflict'] = Variable<bool>(xmpConflict.value);
    }
    if (previewCached.present) {
      map['preview_cached'] = Variable<bool>(previewCached.value);
    }
    if (isRaw.present) {
      map['is_raw'] = Variable<bool>(isRaw.value);
    }
    if (exposureBias.present) {
      map['exposure_bias'] = Variable<double>(exposureBias.value);
    }
    if (exposureTime.present) {
      map['exposure_time'] = Variable<double>(exposureTime.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotosCompanion(')
          ..write('id: $id, ')
          ..write('importId: $importId, ')
          ..write('path: $path, ')
          ..write('contentHash: $contentHash, ')
          ..write('mtime: $mtime, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('camera: $camera, ')
          ..write('lens: $lens, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('orientation: $orientation, ')
          ..write('userRotation: $userRotation, ')
          ..write('hasCrop: $hasCrop, ')
          ..write('cropLeft: $cropLeft, ')
          ..write('cropTop: $cropTop, ')
          ..write('cropRight: $cropRight, ')
          ..write('cropBottom: $cropBottom, ')
          ..write('cropAngle: $cropAngle, ')
          ..write('rating: $rating, ')
          ..write('flag: $flag, ')
          ..write('colorLabel: $colorLabel, ')
          ..write('keywords: $keywords, ')
          ..write('iptc: $iptc, ')
          ..write('hasXmp: $hasXmp, ')
          ..write('xmpMtime: $xmpMtime, ')
          ..write('marksMtime: $marksMtime, ')
          ..write('xmpConflict: $xmpConflict, ')
          ..write('previewCached: $previewCached, ')
          ..write('isRaw: $isRaw, ')
          ..write('exposureBias: $exposureBias, ')
          ..write('exposureTime: $exposureTime')
          ..write(')'))
        .toString();
  }
}

class $SavedSelectionsTable extends SavedSelections
    with TableInfo<$SavedSelectionsTable, SavedSelection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedSelectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _importIdMeta = const VerificationMeta(
    'importId',
  );
  @override
  late final GeneratedColumn<int> importId = GeneratedColumn<int>(
    'import_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES imports (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<int>, String> photoIds =
      GeneratedColumn<String>(
        'photo_ids',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      ).withConverter<List<int>>($SavedSelectionsTable.$converterphotoIds);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    importId,
    name,
    photoIds,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_selections';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedSelection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('import_id')) {
      context.handle(
        _importIdMeta,
        importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta),
      );
    } else if (isInserting) {
      context.missing(_importIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {importId, name},
  ];
  @override
  SavedSelection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedSelection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      importId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}import_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      photoIds: $SavedSelectionsTable.$converterphotoIds.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}photo_ids'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SavedSelectionsTable createAlias(String alias) {
    return $SavedSelectionsTable(attachedDatabase, alias);
  }

  static TypeConverter<List<int>, String> $converterphotoIds =
      const IntListConverter();
}

class SavedSelection extends DataClass implements Insertable<SavedSelection> {
  /// Primary key.
  final int id;

  /// Owning import (selections are per-shoot).
  final int importId;

  /// Human label for the selection.
  final String name;

  /// The selected photo ids, stored as a JSON array.
  final List<int> photoIds;

  /// When this selection was created or last replaced.
  final DateTime createdAt;
  const SavedSelection({
    required this.id,
    required this.importId,
    required this.name,
    required this.photoIds,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['import_id'] = Variable<int>(importId);
    map['name'] = Variable<String>(name);
    {
      map['photo_ids'] = Variable<String>(
        $SavedSelectionsTable.$converterphotoIds.toSql(photoIds),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SavedSelectionsCompanion toCompanion(bool nullToAbsent) {
    return SavedSelectionsCompanion(
      id: Value(id),
      importId: Value(importId),
      name: Value(name),
      photoIds: Value(photoIds),
      createdAt: Value(createdAt),
    );
  }

  factory SavedSelection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedSelection(
      id: serializer.fromJson<int>(json['id']),
      importId: serializer.fromJson<int>(json['importId']),
      name: serializer.fromJson<String>(json['name']),
      photoIds: serializer.fromJson<List<int>>(json['photoIds']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'importId': serializer.toJson<int>(importId),
      'name': serializer.toJson<String>(name),
      'photoIds': serializer.toJson<List<int>>(photoIds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SavedSelection copyWith({
    int? id,
    int? importId,
    String? name,
    List<int>? photoIds,
    DateTime? createdAt,
  }) => SavedSelection(
    id: id ?? this.id,
    importId: importId ?? this.importId,
    name: name ?? this.name,
    photoIds: photoIds ?? this.photoIds,
    createdAt: createdAt ?? this.createdAt,
  );
  SavedSelection copyWithCompanion(SavedSelectionsCompanion data) {
    return SavedSelection(
      id: data.id.present ? data.id.value : this.id,
      importId: data.importId.present ? data.importId.value : this.importId,
      name: data.name.present ? data.name.value : this.name,
      photoIds: data.photoIds.present ? data.photoIds.value : this.photoIds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedSelection(')
          ..write('id: $id, ')
          ..write('importId: $importId, ')
          ..write('name: $name, ')
          ..write('photoIds: $photoIds, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, importId, name, photoIds, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedSelection &&
          other.id == this.id &&
          other.importId == this.importId &&
          other.name == this.name &&
          other.photoIds == this.photoIds &&
          other.createdAt == this.createdAt);
}

class SavedSelectionsCompanion extends UpdateCompanion<SavedSelection> {
  final Value<int> id;
  final Value<int> importId;
  final Value<String> name;
  final Value<List<int>> photoIds;
  final Value<DateTime> createdAt;
  const SavedSelectionsCompanion({
    this.id = const Value.absent(),
    this.importId = const Value.absent(),
    this.name = const Value.absent(),
    this.photoIds = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SavedSelectionsCompanion.insert({
    this.id = const Value.absent(),
    required int importId,
    required String name,
    this.photoIds = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : importId = Value(importId),
       name = Value(name);
  static Insertable<SavedSelection> custom({
    Expression<int>? id,
    Expression<int>? importId,
    Expression<String>? name,
    Expression<String>? photoIds,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (importId != null) 'import_id': importId,
      if (name != null) 'name': name,
      if (photoIds != null) 'photo_ids': photoIds,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SavedSelectionsCompanion copyWith({
    Value<int>? id,
    Value<int>? importId,
    Value<String>? name,
    Value<List<int>>? photoIds,
    Value<DateTime>? createdAt,
  }) {
    return SavedSelectionsCompanion(
      id: id ?? this.id,
      importId: importId ?? this.importId,
      name: name ?? this.name,
      photoIds: photoIds ?? this.photoIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (importId.present) {
      map['import_id'] = Variable<int>(importId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (photoIds.present) {
      map['photo_ids'] = Variable<String>(
        $SavedSelectionsTable.$converterphotoIds.toSql(photoIds.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedSelectionsCompanion(')
          ..write('id: $id, ')
          ..write('importId: $importId, ')
          ..write('name: $name, ')
          ..write('photoIds: $photoIds, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ImportsTable imports = $ImportsTable(this);
  late final $PhotosTable photos = $PhotosTable(this);
  late final $SavedSelectionsTable savedSelections = $SavedSelectionsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    imports,
    photos,
    savedSelections,
  ];
}

typedef $$ImportsTableCreateCompanionBuilder =
    ImportsCompanion Function({
      Value<int> id,
      required String sourcePath,
      Value<String?> destPath,
      Value<DateTime> createdAt,
      Value<String?> cardLabel,
    });
typedef $$ImportsTableUpdateCompanionBuilder =
    ImportsCompanion Function({
      Value<int> id,
      Value<String> sourcePath,
      Value<String?> destPath,
      Value<DateTime> createdAt,
      Value<String?> cardLabel,
    });

final class $$ImportsTableReferences
    extends BaseReferences<_$AppDatabase, $ImportsTable, Import> {
  $$ImportsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PhotosTable, List<Photo>> _photosRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.photos,
    aliasName: 'imports__id__photos__import_id',
  );

  $$PhotosTableProcessedTableManager get photosRefs {
    final manager = $$PhotosTableTableManager(
      $_db,
      $_db.photos,
    ).filter((f) => f.importId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_photosRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SavedSelectionsTable, List<SavedSelection>>
  _savedSelectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.savedSelections,
    aliasName: 'imports__id__saved_selections__import_id',
  );

  $$SavedSelectionsTableProcessedTableManager get savedSelectionsRefs {
    final manager = $$SavedSelectionsTableTableManager(
      $_db,
      $_db.savedSelections,
    ).filter((f) => f.importId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _savedSelectionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ImportsTableFilterComposer
    extends Composer<_$AppDatabase, $ImportsTable> {
  $$ImportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destPath => $composableBuilder(
    column: $table.destPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardLabel => $composableBuilder(
    column: $table.cardLabel,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> photosRefs(
    Expression<bool> Function($$PhotosTableFilterComposer f) f,
  ) {
    final $$PhotosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.photos,
      getReferencedColumn: (t) => t.importId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhotosTableFilterComposer(
            $db: $db,
            $table: $db.photos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> savedSelectionsRefs(
    Expression<bool> Function($$SavedSelectionsTableFilterComposer f) f,
  ) {
    final $$SavedSelectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.savedSelections,
      getReferencedColumn: (t) => t.importId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedSelectionsTableFilterComposer(
            $db: $db,
            $table: $db.savedSelections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ImportsTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportsTable> {
  $$ImportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destPath => $composableBuilder(
    column: $table.destPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardLabel => $composableBuilder(
    column: $table.cardLabel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportsTable> {
  $$ImportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destPath =>
      $composableBuilder(column: $table.destPath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get cardLabel =>
      $composableBuilder(column: $table.cardLabel, builder: (column) => column);

  Expression<T> photosRefs<T extends Object>(
    Expression<T> Function($$PhotosTableAnnotationComposer a) f,
  ) {
    final $$PhotosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.photos,
      getReferencedColumn: (t) => t.importId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhotosTableAnnotationComposer(
            $db: $db,
            $table: $db.photos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> savedSelectionsRefs<T extends Object>(
    Expression<T> Function($$SavedSelectionsTableAnnotationComposer a) f,
  ) {
    final $$SavedSelectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.savedSelections,
      getReferencedColumn: (t) => t.importId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SavedSelectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.savedSelections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ImportsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportsTable,
          Import,
          $$ImportsTableFilterComposer,
          $$ImportsTableOrderingComposer,
          $$ImportsTableAnnotationComposer,
          $$ImportsTableCreateCompanionBuilder,
          $$ImportsTableUpdateCompanionBuilder,
          (Import, $$ImportsTableReferences),
          Import,
          PrefetchHooks Function({bool photosRefs, bool savedSelectionsRefs})
        > {
  $$ImportsTableTableManager(_$AppDatabase db, $ImportsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<String?> destPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> cardLabel = const Value.absent(),
              }) => ImportsCompanion(
                id: id,
                sourcePath: sourcePath,
                destPath: destPath,
                createdAt: createdAt,
                cardLabel: cardLabel,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sourcePath,
                Value<String?> destPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> cardLabel = const Value.absent(),
              }) => ImportsCompanion.insert(
                id: id,
                sourcePath: sourcePath,
                destPath: destPath,
                createdAt: createdAt,
                cardLabel: cardLabel,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ImportsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({photosRefs = false, savedSelectionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (photosRefs) db.photos,
                    if (savedSelectionsRefs) db.savedSelections,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (photosRefs)
                        await $_getPrefetchedData<Import, $ImportsTable, Photo>(
                          currentTable: table,
                          referencedTable: $$ImportsTableReferences
                              ._photosRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ImportsTableReferences(
                                db,
                                table,
                                p0,
                              ).photosRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.importId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (savedSelectionsRefs)
                        await $_getPrefetchedData<
                          Import,
                          $ImportsTable,
                          SavedSelection
                        >(
                          currentTable: table,
                          referencedTable: $$ImportsTableReferences
                              ._savedSelectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ImportsTableReferences(
                                db,
                                table,
                                p0,
                              ).savedSelectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.importId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ImportsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportsTable,
      Import,
      $$ImportsTableFilterComposer,
      $$ImportsTableOrderingComposer,
      $$ImportsTableAnnotationComposer,
      $$ImportsTableCreateCompanionBuilder,
      $$ImportsTableUpdateCompanionBuilder,
      (Import, $$ImportsTableReferences),
      Import,
      PrefetchHooks Function({bool photosRefs, bool savedSelectionsRefs})
    >;
typedef $$PhotosTableCreateCompanionBuilder =
    PhotosCompanion Function({
      Value<int> id,
      Value<int?> importId,
      required String path,
      Value<String?> contentHash,
      required DateTime mtime,
      Value<DateTime?> capturedAt,
      Value<String?> camera,
      Value<String?> lens,
      Value<int?> width,
      Value<int?> height,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int> orientation,
      Value<int> userRotation,
      Value<bool> hasCrop,
      Value<double?> cropLeft,
      Value<double?> cropTop,
      Value<double?> cropRight,
      Value<double?> cropBottom,
      Value<double?> cropAngle,
      Value<int> rating,
      Value<PickFlag> flag,
      Value<ColorLabel> colorLabel,
      Value<List<String>> keywords,
      Value<IptcCore> iptc,
      Value<bool> hasXmp,
      Value<DateTime?> xmpMtime,
      Value<DateTime?> marksMtime,
      Value<bool> xmpConflict,
      Value<bool> previewCached,
      Value<bool> isRaw,
      Value<double?> exposureBias,
      Value<double?> exposureTime,
    });
typedef $$PhotosTableUpdateCompanionBuilder =
    PhotosCompanion Function({
      Value<int> id,
      Value<int?> importId,
      Value<String> path,
      Value<String?> contentHash,
      Value<DateTime> mtime,
      Value<DateTime?> capturedAt,
      Value<String?> camera,
      Value<String?> lens,
      Value<int?> width,
      Value<int?> height,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int> orientation,
      Value<int> userRotation,
      Value<bool> hasCrop,
      Value<double?> cropLeft,
      Value<double?> cropTop,
      Value<double?> cropRight,
      Value<double?> cropBottom,
      Value<double?> cropAngle,
      Value<int> rating,
      Value<PickFlag> flag,
      Value<ColorLabel> colorLabel,
      Value<List<String>> keywords,
      Value<IptcCore> iptc,
      Value<bool> hasXmp,
      Value<DateTime?> xmpMtime,
      Value<DateTime?> marksMtime,
      Value<bool> xmpConflict,
      Value<bool> previewCached,
      Value<bool> isRaw,
      Value<double?> exposureBias,
      Value<double?> exposureTime,
    });

final class $$PhotosTableReferences
    extends BaseReferences<_$AppDatabase, $PhotosTable, Photo> {
  $$PhotosTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ImportsTable _importIdTable(_$AppDatabase db) =>
      db.imports.createAlias('photos__import_id__imports__id');

  $$ImportsTableProcessedTableManager? get importId {
    final $_column = $_itemColumn<int>('import_id');
    if ($_column == null) return null;
    final manager = $$ImportsTableTableManager(
      $_db,
      $_db.imports,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PhotosTableFilterComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get camera => $composableBuilder(
    column: $table.camera,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lens => $composableBuilder(
    column: $table.lens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userRotation => $composableBuilder(
    column: $table.userRotation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasCrop => $composableBuilder(
    column: $table.hasCrop,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cropLeft => $composableBuilder(
    column: $table.cropLeft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cropTop => $composableBuilder(
    column: $table.cropTop,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cropRight => $composableBuilder(
    column: $table.cropRight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cropBottom => $composableBuilder(
    column: $table.cropBottom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cropAngle => $composableBuilder(
    column: $table.cropAngle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PickFlag, PickFlag, int> get flag =>
      $composableBuilder(
        column: $table.flag,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<ColorLabel, ColorLabel, int> get colorLabel =>
      $composableBuilder(
        column: $table.colorLabel,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get keywords => $composableBuilder(
    column: $table.keywords,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<IptcCore, IptcCore, String> get iptc =>
      $composableBuilder(
        column: $table.iptc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get hasXmp => $composableBuilder(
    column: $table.hasXmp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get xmpMtime => $composableBuilder(
    column: $table.xmpMtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get marksMtime => $composableBuilder(
    column: $table.marksMtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get xmpConflict => $composableBuilder(
    column: $table.xmpConflict,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get previewCached => $composableBuilder(
    column: $table.previewCached,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRaw => $composableBuilder(
    column: $table.isRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get exposureBias => $composableBuilder(
    column: $table.exposureBias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get exposureTime => $composableBuilder(
    column: $table.exposureTime,
    builder: (column) => ColumnFilters(column),
  );

  $$ImportsTableFilterComposer get importId {
    final $$ImportsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.imports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportsTableFilterComposer(
            $db: $db,
            $table: $db.imports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get camera => $composableBuilder(
    column: $table.camera,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lens => $composableBuilder(
    column: $table.lens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userRotation => $composableBuilder(
    column: $table.userRotation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasCrop => $composableBuilder(
    column: $table.hasCrop,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cropLeft => $composableBuilder(
    column: $table.cropLeft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cropTop => $composableBuilder(
    column: $table.cropTop,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cropRight => $composableBuilder(
    column: $table.cropRight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cropBottom => $composableBuilder(
    column: $table.cropBottom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cropAngle => $composableBuilder(
    column: $table.cropAngle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flag => $composableBuilder(
    column: $table.flag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorLabel => $composableBuilder(
    column: $table.colorLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keywords => $composableBuilder(
    column: $table.keywords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iptc => $composableBuilder(
    column: $table.iptc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasXmp => $composableBuilder(
    column: $table.hasXmp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get xmpMtime => $composableBuilder(
    column: $table.xmpMtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get marksMtime => $composableBuilder(
    column: $table.marksMtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get xmpConflict => $composableBuilder(
    column: $table.xmpConflict,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get previewCached => $composableBuilder(
    column: $table.previewCached,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRaw => $composableBuilder(
    column: $table.isRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get exposureBias => $composableBuilder(
    column: $table.exposureBias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get exposureTime => $composableBuilder(
    column: $table.exposureTime,
    builder: (column) => ColumnOrderings(column),
  );

  $$ImportsTableOrderingComposer get importId {
    final $$ImportsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.imports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportsTableOrderingComposer(
            $db: $db,
            $table: $db.imports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get mtime =>
      $composableBuilder(column: $table.mtime, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get camera =>
      $composableBuilder(column: $table.camera, builder: (column) => column);

  GeneratedColumn<String> get lens =>
      $composableBuilder(column: $table.lens, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get userRotation => $composableBuilder(
    column: $table.userRotation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasCrop =>
      $composableBuilder(column: $table.hasCrop, builder: (column) => column);

  GeneratedColumn<double> get cropLeft =>
      $composableBuilder(column: $table.cropLeft, builder: (column) => column);

  GeneratedColumn<double> get cropTop =>
      $composableBuilder(column: $table.cropTop, builder: (column) => column);

  GeneratedColumn<double> get cropRight =>
      $composableBuilder(column: $table.cropRight, builder: (column) => column);

  GeneratedColumn<double> get cropBottom => $composableBuilder(
    column: $table.cropBottom,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cropAngle =>
      $composableBuilder(column: $table.cropAngle, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PickFlag, int> get flag =>
      $composableBuilder(column: $table.flag, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ColorLabel, int> get colorLabel =>
      $composableBuilder(
        column: $table.colorLabel,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<List<String>, String> get keywords =>
      $composableBuilder(column: $table.keywords, builder: (column) => column);

  GeneratedColumnWithTypeConverter<IptcCore, String> get iptc =>
      $composableBuilder(column: $table.iptc, builder: (column) => column);

  GeneratedColumn<bool> get hasXmp =>
      $composableBuilder(column: $table.hasXmp, builder: (column) => column);

  GeneratedColumn<DateTime> get xmpMtime =>
      $composableBuilder(column: $table.xmpMtime, builder: (column) => column);

  GeneratedColumn<DateTime> get marksMtime => $composableBuilder(
    column: $table.marksMtime,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get xmpConflict => $composableBuilder(
    column: $table.xmpConflict,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get previewCached => $composableBuilder(
    column: $table.previewCached,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRaw =>
      $composableBuilder(column: $table.isRaw, builder: (column) => column);

  GeneratedColumn<double> get exposureBias => $composableBuilder(
    column: $table.exposureBias,
    builder: (column) => column,
  );

  GeneratedColumn<double> get exposureTime => $composableBuilder(
    column: $table.exposureTime,
    builder: (column) => column,
  );

  $$ImportsTableAnnotationComposer get importId {
    final $$ImportsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.imports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportsTableAnnotationComposer(
            $db: $db,
            $table: $db.imports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PhotosTable,
          Photo,
          $$PhotosTableFilterComposer,
          $$PhotosTableOrderingComposer,
          $$PhotosTableAnnotationComposer,
          $$PhotosTableCreateCompanionBuilder,
          $$PhotosTableUpdateCompanionBuilder,
          (Photo, $$PhotosTableReferences),
          Photo,
          PrefetchHooks Function({bool importId})
        > {
  $$PhotosTableTableManager(_$AppDatabase db, $PhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> importId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<DateTime> mtime = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<String?> camera = const Value.absent(),
                Value<String?> lens = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int> orientation = const Value.absent(),
                Value<int> userRotation = const Value.absent(),
                Value<bool> hasCrop = const Value.absent(),
                Value<double?> cropLeft = const Value.absent(),
                Value<double?> cropTop = const Value.absent(),
                Value<double?> cropRight = const Value.absent(),
                Value<double?> cropBottom = const Value.absent(),
                Value<double?> cropAngle = const Value.absent(),
                Value<int> rating = const Value.absent(),
                Value<PickFlag> flag = const Value.absent(),
                Value<ColorLabel> colorLabel = const Value.absent(),
                Value<List<String>> keywords = const Value.absent(),
                Value<IptcCore> iptc = const Value.absent(),
                Value<bool> hasXmp = const Value.absent(),
                Value<DateTime?> xmpMtime = const Value.absent(),
                Value<DateTime?> marksMtime = const Value.absent(),
                Value<bool> xmpConflict = const Value.absent(),
                Value<bool> previewCached = const Value.absent(),
                Value<bool> isRaw = const Value.absent(),
                Value<double?> exposureBias = const Value.absent(),
                Value<double?> exposureTime = const Value.absent(),
              }) => PhotosCompanion(
                id: id,
                importId: importId,
                path: path,
                contentHash: contentHash,
                mtime: mtime,
                capturedAt: capturedAt,
                camera: camera,
                lens: lens,
                width: width,
                height: height,
                latitude: latitude,
                longitude: longitude,
                orientation: orientation,
                userRotation: userRotation,
                hasCrop: hasCrop,
                cropLeft: cropLeft,
                cropTop: cropTop,
                cropRight: cropRight,
                cropBottom: cropBottom,
                cropAngle: cropAngle,
                rating: rating,
                flag: flag,
                colorLabel: colorLabel,
                keywords: keywords,
                iptc: iptc,
                hasXmp: hasXmp,
                xmpMtime: xmpMtime,
                marksMtime: marksMtime,
                xmpConflict: xmpConflict,
                previewCached: previewCached,
                isRaw: isRaw,
                exposureBias: exposureBias,
                exposureTime: exposureTime,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> importId = const Value.absent(),
                required String path,
                Value<String?> contentHash = const Value.absent(),
                required DateTime mtime,
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<String?> camera = const Value.absent(),
                Value<String?> lens = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int> orientation = const Value.absent(),
                Value<int> userRotation = const Value.absent(),
                Value<bool> hasCrop = const Value.absent(),
                Value<double?> cropLeft = const Value.absent(),
                Value<double?> cropTop = const Value.absent(),
                Value<double?> cropRight = const Value.absent(),
                Value<double?> cropBottom = const Value.absent(),
                Value<double?> cropAngle = const Value.absent(),
                Value<int> rating = const Value.absent(),
                Value<PickFlag> flag = const Value.absent(),
                Value<ColorLabel> colorLabel = const Value.absent(),
                Value<List<String>> keywords = const Value.absent(),
                Value<IptcCore> iptc = const Value.absent(),
                Value<bool> hasXmp = const Value.absent(),
                Value<DateTime?> xmpMtime = const Value.absent(),
                Value<DateTime?> marksMtime = const Value.absent(),
                Value<bool> xmpConflict = const Value.absent(),
                Value<bool> previewCached = const Value.absent(),
                Value<bool> isRaw = const Value.absent(),
                Value<double?> exposureBias = const Value.absent(),
                Value<double?> exposureTime = const Value.absent(),
              }) => PhotosCompanion.insert(
                id: id,
                importId: importId,
                path: path,
                contentHash: contentHash,
                mtime: mtime,
                capturedAt: capturedAt,
                camera: camera,
                lens: lens,
                width: width,
                height: height,
                latitude: latitude,
                longitude: longitude,
                orientation: orientation,
                userRotation: userRotation,
                hasCrop: hasCrop,
                cropLeft: cropLeft,
                cropTop: cropTop,
                cropRight: cropRight,
                cropBottom: cropBottom,
                cropAngle: cropAngle,
                rating: rating,
                flag: flag,
                colorLabel: colorLabel,
                keywords: keywords,
                iptc: iptc,
                hasXmp: hasXmp,
                xmpMtime: xmpMtime,
                marksMtime: marksMtime,
                xmpConflict: xmpConflict,
                previewCached: previewCached,
                isRaw: isRaw,
                exposureBias: exposureBias,
                exposureTime: exposureTime,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PhotosTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({importId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (importId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.importId,
                                referencedTable: $$PhotosTableReferences
                                    ._importIdTable(db),
                                referencedColumn: $$PhotosTableReferences
                                    ._importIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PhotosTable,
      Photo,
      $$PhotosTableFilterComposer,
      $$PhotosTableOrderingComposer,
      $$PhotosTableAnnotationComposer,
      $$PhotosTableCreateCompanionBuilder,
      $$PhotosTableUpdateCompanionBuilder,
      (Photo, $$PhotosTableReferences),
      Photo,
      PrefetchHooks Function({bool importId})
    >;
typedef $$SavedSelectionsTableCreateCompanionBuilder =
    SavedSelectionsCompanion Function({
      Value<int> id,
      required int importId,
      required String name,
      Value<List<int>> photoIds,
      Value<DateTime> createdAt,
    });
typedef $$SavedSelectionsTableUpdateCompanionBuilder =
    SavedSelectionsCompanion Function({
      Value<int> id,
      Value<int> importId,
      Value<String> name,
      Value<List<int>> photoIds,
      Value<DateTime> createdAt,
    });

final class $$SavedSelectionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $SavedSelectionsTable, SavedSelection> {
  $$SavedSelectionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ImportsTable _importIdTable(_$AppDatabase db) =>
      db.imports.createAlias('saved_selections__import_id__imports__id');

  $$ImportsTableProcessedTableManager get importId {
    final $_column = $_itemColumn<int>('import_id')!;

    final manager = $$ImportsTableTableManager(
      $_db,
      $_db.imports,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SavedSelectionsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedSelectionsTable> {
  $$SavedSelectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<int>, List<int>, String> get photoIds =>
      $composableBuilder(
        column: $table.photoIds,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ImportsTableFilterComposer get importId {
    final $$ImportsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.imports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportsTableFilterComposer(
            $db: $db,
            $table: $db.imports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedSelectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedSelectionsTable> {
  $$SavedSelectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoIds => $composableBuilder(
    column: $table.photoIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ImportsTableOrderingComposer get importId {
    final $$ImportsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.imports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportsTableOrderingComposer(
            $db: $db,
            $table: $db.imports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedSelectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedSelectionsTable> {
  $$SavedSelectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<int>, String> get photoIds =>
      $composableBuilder(column: $table.photoIds, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ImportsTableAnnotationComposer get importId {
    final $$ImportsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.imports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportsTableAnnotationComposer(
            $db: $db,
            $table: $db.imports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SavedSelectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedSelectionsTable,
          SavedSelection,
          $$SavedSelectionsTableFilterComposer,
          $$SavedSelectionsTableOrderingComposer,
          $$SavedSelectionsTableAnnotationComposer,
          $$SavedSelectionsTableCreateCompanionBuilder,
          $$SavedSelectionsTableUpdateCompanionBuilder,
          (SavedSelection, $$SavedSelectionsTableReferences),
          SavedSelection,
          PrefetchHooks Function({bool importId})
        > {
  $$SavedSelectionsTableTableManager(
    _$AppDatabase db,
    $SavedSelectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedSelectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedSelectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedSelectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> importId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<List<int>> photoIds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SavedSelectionsCompanion(
                id: id,
                importId: importId,
                name: name,
                photoIds: photoIds,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int importId,
                required String name,
                Value<List<int>> photoIds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SavedSelectionsCompanion.insert(
                id: id,
                importId: importId,
                name: name,
                photoIds: photoIds,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SavedSelectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({importId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (importId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.importId,
                                referencedTable:
                                    $$SavedSelectionsTableReferences
                                        ._importIdTable(db),
                                referencedColumn:
                                    $$SavedSelectionsTableReferences
                                        ._importIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SavedSelectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedSelectionsTable,
      SavedSelection,
      $$SavedSelectionsTableFilterComposer,
      $$SavedSelectionsTableOrderingComposer,
      $$SavedSelectionsTableAnnotationComposer,
      $$SavedSelectionsTableCreateCompanionBuilder,
      $$SavedSelectionsTableUpdateCompanionBuilder,
      (SavedSelection, $$SavedSelectionsTableReferences),
      SavedSelection,
      PrefetchHooks Function({bool importId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ImportsTableTableManager get imports =>
      $$ImportsTableTableManager(_db, _db.imports);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db, _db.photos);
  $$SavedSelectionsTableTableManager get savedSelections =>
      $$SavedSelectionsTableTableManager(_db, _db.savedSelections);
}
