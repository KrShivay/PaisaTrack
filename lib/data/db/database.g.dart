// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $BaselinesTable extends Baselines
    with TableInfo<$BaselinesTable, Baseline> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BaselinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _meanMeta = const VerificationMeta('mean');
  @override
  late final GeneratedColumn<double> mean = GeneratedColumn<double>(
      'mean', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _stdMeta = const VerificationMeta('std');
  @override
  late final GeneratedColumn<double> std = GeneratedColumn<double>(
      'std', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _nMeta = const VerificationMeta('n');
  @override
  late final GeneratedColumn<int> n = GeneratedColumn<int>(
      'n', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, mean, std, n, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'baselines';
  @override
  VerificationContext validateIntegrity(Insertable<Baseline> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('mean')) {
      context.handle(
          _meanMeta, mean.isAcceptableOrUnknown(data['mean']!, _meanMeta));
    } else if (isInserting) {
      context.missing(_meanMeta);
    }
    if (data.containsKey('std')) {
      context.handle(
          _stdMeta, std.isAcceptableOrUnknown(data['std']!, _stdMeta));
    } else if (isInserting) {
      context.missing(_stdMeta);
    }
    if (data.containsKey('n')) {
      context.handle(_nMeta, n.isAcceptableOrUnknown(data['n']!, _nMeta));
    } else if (isInserting) {
      context.missing(_nMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Baseline map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Baseline(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      mean: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}mean'])!,
      std: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}std'])!,
      n: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}n'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $BaselinesTable createAlias(String alias) {
    return $BaselinesTable(attachedDatabase, alias);
  }
}

class Baseline extends DataClass implements Insertable<Baseline> {
  final String key;
  final double mean;
  final double std;
  final int n;
  final DateTime updatedAt;
  const Baseline(
      {required this.key,
      required this.mean,
      required this.std,
      required this.n,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['mean'] = Variable<double>(mean);
    map['std'] = Variable<double>(std);
    map['n'] = Variable<int>(n);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BaselinesCompanion toCompanion(bool nullToAbsent) {
    return BaselinesCompanion(
      key: Value(key),
      mean: Value(mean),
      std: Value(std),
      n: Value(n),
      updatedAt: Value(updatedAt),
    );
  }

  factory Baseline.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Baseline(
      key: serializer.fromJson<String>(json['key']),
      mean: serializer.fromJson<double>(json['mean']),
      std: serializer.fromJson<double>(json['std']),
      n: serializer.fromJson<int>(json['n']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'mean': serializer.toJson<double>(mean),
      'std': serializer.toJson<double>(std),
      'n': serializer.toJson<int>(n),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Baseline copyWith(
          {String? key,
          double? mean,
          double? std,
          int? n,
          DateTime? updatedAt}) =>
      Baseline(
        key: key ?? this.key,
        mean: mean ?? this.mean,
        std: std ?? this.std,
        n: n ?? this.n,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Baseline(')
          ..write('key: $key, ')
          ..write('mean: $mean, ')
          ..write('std: $std, ')
          ..write('n: $n, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, mean, std, n, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Baseline &&
          other.key == this.key &&
          other.mean == this.mean &&
          other.std == this.std &&
          other.n == this.n &&
          other.updatedAt == this.updatedAt);
}

class BaselinesCompanion extends UpdateCompanion<Baseline> {
  final Value<String> key;
  final Value<double> mean;
  final Value<double> std;
  final Value<int> n;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BaselinesCompanion({
    this.key = const Value.absent(),
    this.mean = const Value.absent(),
    this.std = const Value.absent(),
    this.n = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BaselinesCompanion.insert({
    required String key,
    required double mean,
    required double std,
    required int n,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        mean = Value(mean),
        std = Value(std),
        n = Value(n),
        updatedAt = Value(updatedAt);
  static Insertable<Baseline> custom({
    Expression<String>? key,
    Expression<double>? mean,
    Expression<double>? std,
    Expression<int>? n,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (mean != null) 'mean': mean,
      if (std != null) 'std': std,
      if (n != null) 'n': n,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BaselinesCompanion copyWith(
      {Value<String>? key,
      Value<double>? mean,
      Value<double>? std,
      Value<int>? n,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return BaselinesCompanion(
      key: key ?? this.key,
      mean: mean ?? this.mean,
      std: std ?? this.std,
      n: n ?? this.n,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (mean.present) {
      map['mean'] = Variable<double>(mean.value);
    }
    if (std.present) {
      map['std'] = Variable<double>(std.value);
    }
    if (n.present) {
      map['n'] = Variable<int>(n.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BaselinesCompanion(')
          ..write('key: $key, ')
          ..write('mean: $mean, ')
          ..write('std: $std, ')
          ..write('n: $n, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES categories (id)'));
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
      'icon', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isSpendingMeta =
      const VerificationMeta('isSpending');
  @override
  late final GeneratedColumn<bool> isSpending = GeneratedColumn<bool>(
      'is_spending', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_spending" IN (0, 1))'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _isUserCreatedMeta =
      const VerificationMeta('isUserCreated');
  @override
  late final GeneratedColumn<bool> isUserCreated = GeneratedColumn<bool>(
      'is_user_created', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_user_created" IN (0, 1))'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, parentId, icon, isSpending, sortOrder, isUserCreated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(Insertable<Category> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('icon')) {
      context.handle(
          _iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('is_spending')) {
      context.handle(
          _isSpendingMeta,
          isSpending.isAcceptableOrUnknown(
              data['is_spending']!, _isSpendingMeta));
    } else if (isInserting) {
      context.missing(_isSpendingMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('is_user_created')) {
      context.handle(
          _isUserCreatedMeta,
          isUserCreated.isAcceptableOrUnknown(
              data['is_user_created']!, _isUserCreatedMeta));
    } else if (isInserting) {
      context.missing(_isUserCreatedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      icon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon'])!,
      isSpending: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_spending'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      isUserCreated: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_user_created'])!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String name;
  final String? parentId;
  final String icon;
  final bool isSpending;
  final int sortOrder;
  final bool isUserCreated;
  const Category(
      {required this.id,
      required this.name,
      this.parentId,
      required this.icon,
      required this.isSpending,
      required this.sortOrder,
      required this.isUserCreated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['icon'] = Variable<String>(icon);
    map['is_spending'] = Variable<bool>(isSpending);
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_user_created'] = Variable<bool>(isUserCreated);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      icon: Value(icon),
      isSpending: Value(isSpending),
      sortOrder: Value(sortOrder),
      isUserCreated: Value(isUserCreated),
    );
  }

  factory Category.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      icon: serializer.fromJson<String>(json['icon']),
      isSpending: serializer.fromJson<bool>(json['isSpending']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isUserCreated: serializer.fromJson<bool>(json['isUserCreated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'parentId': serializer.toJson<String?>(parentId),
      'icon': serializer.toJson<String>(icon),
      'isSpending': serializer.toJson<bool>(isSpending),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isUserCreated': serializer.toJson<bool>(isUserCreated),
    };
  }

  Category copyWith(
          {String? id,
          String? name,
          Value<String?> parentId = const Value.absent(),
          String? icon,
          bool? isSpending,
          int? sortOrder,
          bool? isUserCreated}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        parentId: parentId.present ? parentId.value : this.parentId,
        icon: icon ?? this.icon,
        isSpending: isSpending ?? this.isSpending,
        sortOrder: sortOrder ?? this.sortOrder,
        isUserCreated: isUserCreated ?? this.isUserCreated,
      );
  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('isSpending: $isSpending, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isUserCreated: $isUserCreated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, parentId, icon, isSpending, sortOrder, isUserCreated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.parentId == this.parentId &&
          other.icon == this.icon &&
          other.isSpending == this.isSpending &&
          other.sortOrder == this.sortOrder &&
          other.isUserCreated == this.isUserCreated);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> parentId;
  final Value<String> icon;
  final Value<bool> isSpending;
  final Value<int> sortOrder;
  final Value<bool> isUserCreated;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.parentId = const Value.absent(),
    this.icon = const Value.absent(),
    this.isSpending = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isUserCreated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String name,
    this.parentId = const Value.absent(),
    required String icon,
    required bool isSpending,
    required int sortOrder,
    required bool isUserCreated,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        icon = Value(icon),
        isSpending = Value(isSpending),
        sortOrder = Value(sortOrder),
        isUserCreated = Value(isUserCreated);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? parentId,
    Expression<String>? icon,
    Expression<bool>? isSpending,
    Expression<int>? sortOrder,
    Expression<bool>? isUserCreated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
      if (icon != null) 'icon': icon,
      if (isSpending != null) 'is_spending': isSpending,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isUserCreated != null) 'is_user_created': isUserCreated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? parentId,
      Value<String>? icon,
      Value<bool>? isSpending,
      Value<int>? sortOrder,
      Value<bool>? isUserCreated,
      Value<int>? rowid}) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      icon: icon ?? this.icon,
      isSpending: isSpending ?? this.isSpending,
      sortOrder: sortOrder ?? this.sortOrder,
      isUserCreated: isUserCreated ?? this.isUserCreated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (isSpending.present) {
      map['is_spending'] = Variable<bool>(isSpending.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isUserCreated.present) {
      map['is_user_created'] = Variable<bool>(isUserCreated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('isSpending: $isSpending, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isUserCreated: $isUserCreated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MerchantsTable extends Merchants
    with TableInfo<$MerchantsTable, Merchant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MerchantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _canonicalNameMeta =
      const VerificationMeta('canonicalName');
  @override
  late final GeneratedColumn<String> canonicalName = GeneratedColumn<String>(
      'canonical_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryHintMeta =
      const VerificationMeta('categoryHint');
  @override
  late final GeneratedColumn<String> categoryHint = GeneratedColumn<String>(
      'category_hint', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _embeddingMeta =
      const VerificationMeta('embedding');
  @override
  late final GeneratedColumn<Uint8List> embedding = GeneratedColumn<Uint8List>(
      'embedding', aliasedName, true,
      type: DriftSqlType.blob, requiredDuringInsert: false);
  static const VerificationMeta _txnCountMeta =
      const VerificationMeta('txnCount');
  @override
  late final GeneratedColumn<int> txnCount = GeneratedColumn<int>(
      'txn_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _firstSeenMeta =
      const VerificationMeta('firstSeen');
  @override
  late final GeneratedColumn<DateTime> firstSeen = GeneratedColumn<DateTime>(
      'first_seen', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastSeenMeta =
      const VerificationMeta('lastSeen');
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
      'last_seen', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        canonicalName,
        categoryHint,
        embedding,
        txnCount,
        firstSeen,
        lastSeen
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'merchants';
  @override
  VerificationContext validateIntegrity(Insertable<Merchant> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('canonical_name')) {
      context.handle(
          _canonicalNameMeta,
          canonicalName.isAcceptableOrUnknown(
              data['canonical_name']!, _canonicalNameMeta));
    } else if (isInserting) {
      context.missing(_canonicalNameMeta);
    }
    if (data.containsKey('category_hint')) {
      context.handle(
          _categoryHintMeta,
          categoryHint.isAcceptableOrUnknown(
              data['category_hint']!, _categoryHintMeta));
    }
    if (data.containsKey('embedding')) {
      context.handle(_embeddingMeta,
          embedding.isAcceptableOrUnknown(data['embedding']!, _embeddingMeta));
    }
    if (data.containsKey('txn_count')) {
      context.handle(_txnCountMeta,
          txnCount.isAcceptableOrUnknown(data['txn_count']!, _txnCountMeta));
    }
    if (data.containsKey('first_seen')) {
      context.handle(_firstSeenMeta,
          firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta));
    } else if (isInserting) {
      context.missing(_firstSeenMeta);
    }
    if (data.containsKey('last_seen')) {
      context.handle(_lastSeenMeta,
          lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta));
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Merchant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Merchant(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      canonicalName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}canonical_name'])!,
      categoryHint: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_hint']),
      embedding: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}embedding']),
      txnCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}txn_count'])!,
      firstSeen: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}first_seen'])!,
      lastSeen: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_seen'])!,
    );
  }

  @override
  $MerchantsTable createAlias(String alias) {
    return $MerchantsTable(attachedDatabase, alias);
  }
}

class Merchant extends DataClass implements Insertable<Merchant> {
  final String id;
  final String canonicalName;
  final String? categoryHint;
  final Uint8List? embedding;
  final int txnCount;
  final DateTime firstSeen;
  final DateTime lastSeen;
  const Merchant(
      {required this.id,
      required this.canonicalName,
      this.categoryHint,
      this.embedding,
      required this.txnCount,
      required this.firstSeen,
      required this.lastSeen});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['canonical_name'] = Variable<String>(canonicalName);
    if (!nullToAbsent || categoryHint != null) {
      map['category_hint'] = Variable<String>(categoryHint);
    }
    if (!nullToAbsent || embedding != null) {
      map['embedding'] = Variable<Uint8List>(embedding);
    }
    map['txn_count'] = Variable<int>(txnCount);
    map['first_seen'] = Variable<DateTime>(firstSeen);
    map['last_seen'] = Variable<DateTime>(lastSeen);
    return map;
  }

  MerchantsCompanion toCompanion(bool nullToAbsent) {
    return MerchantsCompanion(
      id: Value(id),
      canonicalName: Value(canonicalName),
      categoryHint: categoryHint == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryHint),
      embedding: embedding == null && nullToAbsent
          ? const Value.absent()
          : Value(embedding),
      txnCount: Value(txnCount),
      firstSeen: Value(firstSeen),
      lastSeen: Value(lastSeen),
    );
  }

  factory Merchant.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Merchant(
      id: serializer.fromJson<String>(json['id']),
      canonicalName: serializer.fromJson<String>(json['canonicalName']),
      categoryHint: serializer.fromJson<String?>(json['categoryHint']),
      embedding: serializer.fromJson<Uint8List?>(json['embedding']),
      txnCount: serializer.fromJson<int>(json['txnCount']),
      firstSeen: serializer.fromJson<DateTime>(json['firstSeen']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'canonicalName': serializer.toJson<String>(canonicalName),
      'categoryHint': serializer.toJson<String?>(categoryHint),
      'embedding': serializer.toJson<Uint8List?>(embedding),
      'txnCount': serializer.toJson<int>(txnCount),
      'firstSeen': serializer.toJson<DateTime>(firstSeen),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
    };
  }

  Merchant copyWith(
          {String? id,
          String? canonicalName,
          Value<String?> categoryHint = const Value.absent(),
          Value<Uint8List?> embedding = const Value.absent(),
          int? txnCount,
          DateTime? firstSeen,
          DateTime? lastSeen}) =>
      Merchant(
        id: id ?? this.id,
        canonicalName: canonicalName ?? this.canonicalName,
        categoryHint:
            categoryHint.present ? categoryHint.value : this.categoryHint,
        embedding: embedding.present ? embedding.value : this.embedding,
        txnCount: txnCount ?? this.txnCount,
        firstSeen: firstSeen ?? this.firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
      );
  @override
  String toString() {
    return (StringBuffer('Merchant(')
          ..write('id: $id, ')
          ..write('canonicalName: $canonicalName, ')
          ..write('categoryHint: $categoryHint, ')
          ..write('embedding: $embedding, ')
          ..write('txnCount: $txnCount, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, canonicalName, categoryHint,
      $driftBlobEquality.hash(embedding), txnCount, firstSeen, lastSeen);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Merchant &&
          other.id == this.id &&
          other.canonicalName == this.canonicalName &&
          other.categoryHint == this.categoryHint &&
          $driftBlobEquality.equals(other.embedding, this.embedding) &&
          other.txnCount == this.txnCount &&
          other.firstSeen == this.firstSeen &&
          other.lastSeen == this.lastSeen);
}

class MerchantsCompanion extends UpdateCompanion<Merchant> {
  final Value<String> id;
  final Value<String> canonicalName;
  final Value<String?> categoryHint;
  final Value<Uint8List?> embedding;
  final Value<int> txnCount;
  final Value<DateTime> firstSeen;
  final Value<DateTime> lastSeen;
  final Value<int> rowid;
  const MerchantsCompanion({
    this.id = const Value.absent(),
    this.canonicalName = const Value.absent(),
    this.categoryHint = const Value.absent(),
    this.embedding = const Value.absent(),
    this.txnCount = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MerchantsCompanion.insert({
    required String id,
    required String canonicalName,
    this.categoryHint = const Value.absent(),
    this.embedding = const Value.absent(),
    this.txnCount = const Value.absent(),
    required DateTime firstSeen,
    required DateTime lastSeen,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        canonicalName = Value(canonicalName),
        firstSeen = Value(firstSeen),
        lastSeen = Value(lastSeen);
  static Insertable<Merchant> custom({
    Expression<String>? id,
    Expression<String>? canonicalName,
    Expression<String>? categoryHint,
    Expression<Uint8List>? embedding,
    Expression<int>? txnCount,
    Expression<DateTime>? firstSeen,
    Expression<DateTime>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (canonicalName != null) 'canonical_name': canonicalName,
      if (categoryHint != null) 'category_hint': categoryHint,
      if (embedding != null) 'embedding': embedding,
      if (txnCount != null) 'txn_count': txnCount,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MerchantsCompanion copyWith(
      {Value<String>? id,
      Value<String>? canonicalName,
      Value<String?>? categoryHint,
      Value<Uint8List?>? embedding,
      Value<int>? txnCount,
      Value<DateTime>? firstSeen,
      Value<DateTime>? lastSeen,
      Value<int>? rowid}) {
    return MerchantsCompanion(
      id: id ?? this.id,
      canonicalName: canonicalName ?? this.canonicalName,
      categoryHint: categoryHint ?? this.categoryHint,
      embedding: embedding ?? this.embedding,
      txnCount: txnCount ?? this.txnCount,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (canonicalName.present) {
      map['canonical_name'] = Variable<String>(canonicalName.value);
    }
    if (categoryHint.present) {
      map['category_hint'] = Variable<String>(categoryHint.value);
    }
    if (embedding.present) {
      map['embedding'] = Variable<Uint8List>(embedding.value);
    }
    if (txnCount.present) {
      map['txn_count'] = Variable<int>(txnCount.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<DateTime>(firstSeen.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MerchantsCompanion(')
          ..write('id: $id, ')
          ..write('canonicalName: $canonicalName, ')
          ..write('categoryHint: $categoryHint, ')
          ..write('embedding: $embedding, ')
          ..write('txnCount: $txnCount, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RawSmsTable extends RawSms with TableInfo<$RawSmsTable, RawSm> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RawSmsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
      'sender', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _receivedAtMeta =
      const VerificationMeta('receivedAt');
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
      'received_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _processedMeta =
      const VerificationMeta('processed');
  @override
  late final GeneratedColumn<bool> processed = GeneratedColumn<bool>(
      'processed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("processed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _purgeAfterMeta =
      const VerificationMeta('purgeAfter');
  @override
  late final GeneratedColumn<DateTime> purgeAfter = GeneratedColumn<DateTime>(
      'purge_after', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sender, body, receivedAt, processed, purgeAfter];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_sms';
  @override
  VerificationContext validateIntegrity(Insertable<RawSm> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(_senderMeta,
          sender.isAcceptableOrUnknown(data['sender']!, _senderMeta));
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
          _receivedAtMeta,
          receivedAt.isAcceptableOrUnknown(
              data['received_at']!, _receivedAtMeta));
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    if (data.containsKey('processed')) {
      context.handle(_processedMeta,
          processed.isAcceptableOrUnknown(data['processed']!, _processedMeta));
    }
    if (data.containsKey('purge_after')) {
      context.handle(
          _purgeAfterMeta,
          purgeAfter.isAcceptableOrUnknown(
              data['purge_after']!, _purgeAfterMeta));
    } else if (isInserting) {
      context.missing(_purgeAfterMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawSm map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawSm(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      sender: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body'])!,
      receivedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}received_at'])!,
      processed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}processed'])!,
      purgeAfter: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}purge_after'])!,
    );
  }

  @override
  $RawSmsTable createAlias(String alias) {
    return $RawSmsTable(attachedDatabase, alias);
  }
}

class RawSm extends DataClass implements Insertable<RawSm> {
  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final bool processed;
  final DateTime purgeAfter;
  const RawSm(
      {required this.id,
      required this.sender,
      required this.body,
      required this.receivedAt,
      required this.processed,
      required this.purgeAfter});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sender'] = Variable<String>(sender);
    map['body'] = Variable<String>(body);
    map['received_at'] = Variable<DateTime>(receivedAt);
    map['processed'] = Variable<bool>(processed);
    map['purge_after'] = Variable<DateTime>(purgeAfter);
    return map;
  }

  RawSmsCompanion toCompanion(bool nullToAbsent) {
    return RawSmsCompanion(
      id: Value(id),
      sender: Value(sender),
      body: Value(body),
      receivedAt: Value(receivedAt),
      processed: Value(processed),
      purgeAfter: Value(purgeAfter),
    );
  }

  factory RawSm.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawSm(
      id: serializer.fromJson<String>(json['id']),
      sender: serializer.fromJson<String>(json['sender']),
      body: serializer.fromJson<String>(json['body']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      processed: serializer.fromJson<bool>(json['processed']),
      purgeAfter: serializer.fromJson<DateTime>(json['purgeAfter']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sender': serializer.toJson<String>(sender),
      'body': serializer.toJson<String>(body),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'processed': serializer.toJson<bool>(processed),
      'purgeAfter': serializer.toJson<DateTime>(purgeAfter),
    };
  }

  RawSm copyWith(
          {String? id,
          String? sender,
          String? body,
          DateTime? receivedAt,
          bool? processed,
          DateTime? purgeAfter}) =>
      RawSm(
        id: id ?? this.id,
        sender: sender ?? this.sender,
        body: body ?? this.body,
        receivedAt: receivedAt ?? this.receivedAt,
        processed: processed ?? this.processed,
        purgeAfter: purgeAfter ?? this.purgeAfter,
      );
  @override
  String toString() {
    return (StringBuffer('RawSm(')
          ..write('id: $id, ')
          ..write('sender: $sender, ')
          ..write('body: $body, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('processed: $processed, ')
          ..write('purgeAfter: $purgeAfter')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sender, body, receivedAt, processed, purgeAfter);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawSm &&
          other.id == this.id &&
          other.sender == this.sender &&
          other.body == this.body &&
          other.receivedAt == this.receivedAt &&
          other.processed == this.processed &&
          other.purgeAfter == this.purgeAfter);
}

class RawSmsCompanion extends UpdateCompanion<RawSm> {
  final Value<String> id;
  final Value<String> sender;
  final Value<String> body;
  final Value<DateTime> receivedAt;
  final Value<bool> processed;
  final Value<DateTime> purgeAfter;
  final Value<int> rowid;
  const RawSmsCompanion({
    this.id = const Value.absent(),
    this.sender = const Value.absent(),
    this.body = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.processed = const Value.absent(),
    this.purgeAfter = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RawSmsCompanion.insert({
    required String id,
    required String sender,
    required String body,
    required DateTime receivedAt,
    this.processed = const Value.absent(),
    required DateTime purgeAfter,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        sender = Value(sender),
        body = Value(body),
        receivedAt = Value(receivedAt),
        purgeAfter = Value(purgeAfter);
  static Insertable<RawSm> custom({
    Expression<String>? id,
    Expression<String>? sender,
    Expression<String>? body,
    Expression<DateTime>? receivedAt,
    Expression<bool>? processed,
    Expression<DateTime>? purgeAfter,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sender != null) 'sender': sender,
      if (body != null) 'body': body,
      if (receivedAt != null) 'received_at': receivedAt,
      if (processed != null) 'processed': processed,
      if (purgeAfter != null) 'purge_after': purgeAfter,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RawSmsCompanion copyWith(
      {Value<String>? id,
      Value<String>? sender,
      Value<String>? body,
      Value<DateTime>? receivedAt,
      Value<bool>? processed,
      Value<DateTime>? purgeAfter,
      Value<int>? rowid}) {
    return RawSmsCompanion(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      body: body ?? this.body,
      receivedAt: receivedAt ?? this.receivedAt,
      processed: processed ?? this.processed,
      purgeAfter: purgeAfter ?? this.purgeAfter,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (processed.present) {
      map['processed'] = Variable<bool>(processed.value);
    }
    if (purgeAfter.present) {
      map['purge_after'] = Variable<DateTime>(purgeAfter.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawSmsCompanion(')
          ..write('id: $id, ')
          ..write('sender: $sender, ')
          ..write('body: $body, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('processed: $processed, ')
          ..write('purgeAfter: $purgeAfter, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<int> ts = GeneratedColumn<int>(
      'ts', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _channelMeta =
      const VerificationMeta('channel');
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
      'channel', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountHintMeta =
      const VerificationMeta('accountHint');
  @override
  late final GeneratedColumn<String> accountHint = GeneratedColumn<String>(
      'account_hint', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _merchantRawMeta =
      const VerificationMeta('merchantRaw');
  @override
  late final GeneratedColumn<String> merchantRaw = GeneratedColumn<String>(
      'merchant_raw', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _merchantIdMeta =
      const VerificationMeta('merchantId');
  @override
  late final GeneratedColumn<String> merchantId = GeneratedColumn<String>(
      'merchant_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES merchants (id)'));
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES categories (id)'));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _balanceAfterMeta =
      const VerificationMeta('balanceAfter');
  @override
  late final GeneratedColumn<double> balanceAfter = GeneratedColumn<double>(
      'balance_after', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
      'ref_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _parseSourceMeta =
      const VerificationMeta('parseSource');
  @override
  late final GeneratedColumn<String> parseSource = GeneratedColumn<String>(
      'parse_source', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _smsIdMeta = const VerificationMeta('smsId');
  @override
  late final GeneratedColumn<String> smsId = GeneratedColumn<String>(
      'sms_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES raw_sms (id)'));
  static const VerificationMeta _confidenceJsonMeta =
      const VerificationMeta('confidenceJson');
  @override
  late final GeneratedColumn<String> confidenceJson = GeneratedColumn<String>(
      'confidence_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isDeletedMeta =
      const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
      'is_deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _counterpartyVpaMeta =
      const VerificationMeta('counterpartyVpa');
  @override
  late final GeneratedColumn<String> counterpartyVpa = GeneratedColumn<String>(
      'counterparty_vpa', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _duplicateOfTxnIdMeta =
      const VerificationMeta('duplicateOfTxnId');
  @override
  late final GeneratedColumn<String> duplicateOfTxnId = GeneratedColumn<String>(
      'duplicate_of_txn_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES transactions (id)'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ts,
        amount,
        direction,
        channel,
        accountHint,
        merchantRaw,
        merchantId,
        categoryId,
        description,
        balanceAfter,
        refId,
        parseSource,
        smsId,
        confidenceJson,
        status,
        isDeleted,
        counterpartyVpa,
        duplicateOfTxnId,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(Insertable<Transaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(_channelMeta,
          channel.isAcceptableOrUnknown(data['channel']!, _channelMeta));
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('account_hint')) {
      context.handle(
          _accountHintMeta,
          accountHint.isAcceptableOrUnknown(
              data['account_hint']!, _accountHintMeta));
    }
    if (data.containsKey('merchant_raw')) {
      context.handle(
          _merchantRawMeta,
          merchantRaw.isAcceptableOrUnknown(
              data['merchant_raw']!, _merchantRawMeta));
    }
    if (data.containsKey('merchant_id')) {
      context.handle(
          _merchantIdMeta,
          merchantId.isAcceptableOrUnknown(
              data['merchant_id']!, _merchantIdMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('balance_after')) {
      context.handle(
          _balanceAfterMeta,
          balanceAfter.isAcceptableOrUnknown(
              data['balance_after']!, _balanceAfterMeta));
    }
    if (data.containsKey('ref_id')) {
      context.handle(
          _refIdMeta, refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta));
    }
    if (data.containsKey('parse_source')) {
      context.handle(
          _parseSourceMeta,
          parseSource.isAcceptableOrUnknown(
              data['parse_source']!, _parseSourceMeta));
    } else if (isInserting) {
      context.missing(_parseSourceMeta);
    }
    if (data.containsKey('sms_id')) {
      context.handle(
          _smsIdMeta, smsId.isAcceptableOrUnknown(data['sms_id']!, _smsIdMeta));
    }
    if (data.containsKey('confidence_json')) {
      context.handle(
          _confidenceJsonMeta,
          confidenceJson.isAcceptableOrUnknown(
              data['confidence_json']!, _confidenceJsonMeta));
    } else if (isInserting) {
      context.missing(_confidenceJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(_isDeletedMeta,
          isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta));
    }
    if (data.containsKey('counterparty_vpa')) {
      context.handle(
          _counterpartyVpaMeta,
          counterpartyVpa.isAcceptableOrUnknown(
              data['counterparty_vpa']!, _counterpartyVpaMeta));
    }
    if (data.containsKey('duplicate_of_txn_id')) {
      context.handle(
          _duplicateOfTxnIdMeta,
          duplicateOfTxnId.isAcceptableOrUnknown(
              data['duplicate_of_txn_id']!, _duplicateOfTxnIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ts'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      channel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}channel'])!,
      accountHint: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_hint']),
      merchantRaw: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merchant_raw']),
      merchantId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merchant_id']),
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      balanceAfter: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}balance_after']),
      refId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ref_id']),
      parseSource: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parse_source'])!,
      smsId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sms_id']),
      confidenceJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}confidence_json'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      isDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_deleted'])!,
      counterpartyVpa: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}counterparty_vpa']),
      duplicateOfTxnId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}duplicate_of_txn_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final String id;
  final int ts;
  final double amount;
  final String direction;
  final String channel;
  final String? accountHint;
  final String? merchantRaw;
  final String? merchantId;
  final String? categoryId;
  final String? description;
  final double? balanceAfter;
  final String? refId;
  final String parseSource;
  final String? smsId;
  final String confidenceJson;
  final String status;
  final bool isDeleted;
  final String? counterpartyVpa;
  final String? duplicateOfTxnId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Transaction(
      {required this.id,
      required this.ts,
      required this.amount,
      required this.direction,
      required this.channel,
      this.accountHint,
      this.merchantRaw,
      this.merchantId,
      this.categoryId,
      this.description,
      this.balanceAfter,
      this.refId,
      required this.parseSource,
      this.smsId,
      required this.confidenceJson,
      required this.status,
      required this.isDeleted,
      this.counterpartyVpa,
      this.duplicateOfTxnId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['ts'] = Variable<int>(ts);
    map['amount'] = Variable<double>(amount);
    map['direction'] = Variable<String>(direction);
    map['channel'] = Variable<String>(channel);
    if (!nullToAbsent || accountHint != null) {
      map['account_hint'] = Variable<String>(accountHint);
    }
    if (!nullToAbsent || merchantRaw != null) {
      map['merchant_raw'] = Variable<String>(merchantRaw);
    }
    if (!nullToAbsent || merchantId != null) {
      map['merchant_id'] = Variable<String>(merchantId);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || balanceAfter != null) {
      map['balance_after'] = Variable<double>(balanceAfter);
    }
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    map['parse_source'] = Variable<String>(parseSource);
    if (!nullToAbsent || smsId != null) {
      map['sms_id'] = Variable<String>(smsId);
    }
    map['confidence_json'] = Variable<String>(confidenceJson);
    map['status'] = Variable<String>(status);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || counterpartyVpa != null) {
      map['counterparty_vpa'] = Variable<String>(counterpartyVpa);
    }
    if (!nullToAbsent || duplicateOfTxnId != null) {
      map['duplicate_of_txn_id'] = Variable<String>(duplicateOfTxnId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      ts: Value(ts),
      amount: Value(amount),
      direction: Value(direction),
      channel: Value(channel),
      accountHint: accountHint == null && nullToAbsent
          ? const Value.absent()
          : Value(accountHint),
      merchantRaw: merchantRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(merchantRaw),
      merchantId: merchantId == null && nullToAbsent
          ? const Value.absent()
          : Value(merchantId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      balanceAfter: balanceAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(balanceAfter),
      refId:
          refId == null && nullToAbsent ? const Value.absent() : Value(refId),
      parseSource: Value(parseSource),
      smsId:
          smsId == null && nullToAbsent ? const Value.absent() : Value(smsId),
      confidenceJson: Value(confidenceJson),
      status: Value(status),
      isDeleted: Value(isDeleted),
      counterpartyVpa: counterpartyVpa == null && nullToAbsent
          ? const Value.absent()
          : Value(counterpartyVpa),
      duplicateOfTxnId: duplicateOfTxnId == null && nullToAbsent
          ? const Value.absent()
          : Value(duplicateOfTxnId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<String>(json['id']),
      ts: serializer.fromJson<int>(json['ts']),
      amount: serializer.fromJson<double>(json['amount']),
      direction: serializer.fromJson<String>(json['direction']),
      channel: serializer.fromJson<String>(json['channel']),
      accountHint: serializer.fromJson<String?>(json['accountHint']),
      merchantRaw: serializer.fromJson<String?>(json['merchantRaw']),
      merchantId: serializer.fromJson<String?>(json['merchantId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      description: serializer.fromJson<String?>(json['description']),
      balanceAfter: serializer.fromJson<double?>(json['balanceAfter']),
      refId: serializer.fromJson<String?>(json['refId']),
      parseSource: serializer.fromJson<String>(json['parseSource']),
      smsId: serializer.fromJson<String?>(json['smsId']),
      confidenceJson: serializer.fromJson<String>(json['confidenceJson']),
      status: serializer.fromJson<String>(json['status']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      counterpartyVpa: serializer.fromJson<String?>(json['counterpartyVpa']),
      duplicateOfTxnId: serializer.fromJson<String?>(json['duplicateOfTxnId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ts': serializer.toJson<int>(ts),
      'amount': serializer.toJson<double>(amount),
      'direction': serializer.toJson<String>(direction),
      'channel': serializer.toJson<String>(channel),
      'accountHint': serializer.toJson<String?>(accountHint),
      'merchantRaw': serializer.toJson<String?>(merchantRaw),
      'merchantId': serializer.toJson<String?>(merchantId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'description': serializer.toJson<String?>(description),
      'balanceAfter': serializer.toJson<double?>(balanceAfter),
      'refId': serializer.toJson<String?>(refId),
      'parseSource': serializer.toJson<String>(parseSource),
      'smsId': serializer.toJson<String?>(smsId),
      'confidenceJson': serializer.toJson<String>(confidenceJson),
      'status': serializer.toJson<String>(status),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'counterpartyVpa': serializer.toJson<String?>(counterpartyVpa),
      'duplicateOfTxnId': serializer.toJson<String?>(duplicateOfTxnId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Transaction copyWith(
          {String? id,
          int? ts,
          double? amount,
          String? direction,
          String? channel,
          Value<String?> accountHint = const Value.absent(),
          Value<String?> merchantRaw = const Value.absent(),
          Value<String?> merchantId = const Value.absent(),
          Value<String?> categoryId = const Value.absent(),
          Value<String?> description = const Value.absent(),
          Value<double?> balanceAfter = const Value.absent(),
          Value<String?> refId = const Value.absent(),
          String? parseSource,
          Value<String?> smsId = const Value.absent(),
          String? confidenceJson,
          String? status,
          bool? isDeleted,
          Value<String?> counterpartyVpa = const Value.absent(),
          Value<String?> duplicateOfTxnId = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Transaction(
        id: id ?? this.id,
        ts: ts ?? this.ts,
        amount: amount ?? this.amount,
        direction: direction ?? this.direction,
        channel: channel ?? this.channel,
        accountHint: accountHint.present ? accountHint.value : this.accountHint,
        merchantRaw: merchantRaw.present ? merchantRaw.value : this.merchantRaw,
        merchantId: merchantId.present ? merchantId.value : this.merchantId,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        description: description.present ? description.value : this.description,
        balanceAfter:
            balanceAfter.present ? balanceAfter.value : this.balanceAfter,
        refId: refId.present ? refId.value : this.refId,
        parseSource: parseSource ?? this.parseSource,
        smsId: smsId.present ? smsId.value : this.smsId,
        confidenceJson: confidenceJson ?? this.confidenceJson,
        status: status ?? this.status,
        isDeleted: isDeleted ?? this.isDeleted,
        counterpartyVpa: counterpartyVpa.present
            ? counterpartyVpa.value
            : this.counterpartyVpa,
        duplicateOfTxnId: duplicateOfTxnId.present
            ? duplicateOfTxnId.value
            : this.duplicateOfTxnId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('ts: $ts, ')
          ..write('amount: $amount, ')
          ..write('direction: $direction, ')
          ..write('channel: $channel, ')
          ..write('accountHint: $accountHint, ')
          ..write('merchantRaw: $merchantRaw, ')
          ..write('merchantId: $merchantId, ')
          ..write('categoryId: $categoryId, ')
          ..write('description: $description, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('refId: $refId, ')
          ..write('parseSource: $parseSource, ')
          ..write('smsId: $smsId, ')
          ..write('confidenceJson: $confidenceJson, ')
          ..write('status: $status, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('counterpartyVpa: $counterpartyVpa, ')
          ..write('duplicateOfTxnId: $duplicateOfTxnId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        ts,
        amount,
        direction,
        channel,
        accountHint,
        merchantRaw,
        merchantId,
        categoryId,
        description,
        balanceAfter,
        refId,
        parseSource,
        smsId,
        confidenceJson,
        status,
        isDeleted,
        counterpartyVpa,
        duplicateOfTxnId,
        createdAt,
        updatedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.ts == this.ts &&
          other.amount == this.amount &&
          other.direction == this.direction &&
          other.channel == this.channel &&
          other.accountHint == this.accountHint &&
          other.merchantRaw == this.merchantRaw &&
          other.merchantId == this.merchantId &&
          other.categoryId == this.categoryId &&
          other.description == this.description &&
          other.balanceAfter == this.balanceAfter &&
          other.refId == this.refId &&
          other.parseSource == this.parseSource &&
          other.smsId == this.smsId &&
          other.confidenceJson == this.confidenceJson &&
          other.status == this.status &&
          other.isDeleted == this.isDeleted &&
          other.counterpartyVpa == this.counterpartyVpa &&
          other.duplicateOfTxnId == this.duplicateOfTxnId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<String> id;
  final Value<int> ts;
  final Value<double> amount;
  final Value<String> direction;
  final Value<String> channel;
  final Value<String?> accountHint;
  final Value<String?> merchantRaw;
  final Value<String?> merchantId;
  final Value<String?> categoryId;
  final Value<String?> description;
  final Value<double?> balanceAfter;
  final Value<String?> refId;
  final Value<String> parseSource;
  final Value<String?> smsId;
  final Value<String> confidenceJson;
  final Value<String> status;
  final Value<bool> isDeleted;
  final Value<String?> counterpartyVpa;
  final Value<String?> duplicateOfTxnId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.ts = const Value.absent(),
    this.amount = const Value.absent(),
    this.direction = const Value.absent(),
    this.channel = const Value.absent(),
    this.accountHint = const Value.absent(),
    this.merchantRaw = const Value.absent(),
    this.merchantId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.description = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.refId = const Value.absent(),
    this.parseSource = const Value.absent(),
    this.smsId = const Value.absent(),
    this.confidenceJson = const Value.absent(),
    this.status = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.counterpartyVpa = const Value.absent(),
    this.duplicateOfTxnId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    required String id,
    required int ts,
    required double amount,
    required String direction,
    required String channel,
    this.accountHint = const Value.absent(),
    this.merchantRaw = const Value.absent(),
    this.merchantId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.description = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.refId = const Value.absent(),
    required String parseSource,
    this.smsId = const Value.absent(),
    required String confidenceJson,
    required String status,
    this.isDeleted = const Value.absent(),
    this.counterpartyVpa = const Value.absent(),
    this.duplicateOfTxnId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ts = Value(ts),
        amount = Value(amount),
        direction = Value(direction),
        channel = Value(channel),
        parseSource = Value(parseSource),
        confidenceJson = Value(confidenceJson),
        status = Value(status),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Transaction> custom({
    Expression<String>? id,
    Expression<int>? ts,
    Expression<double>? amount,
    Expression<String>? direction,
    Expression<String>? channel,
    Expression<String>? accountHint,
    Expression<String>? merchantRaw,
    Expression<String>? merchantId,
    Expression<String>? categoryId,
    Expression<String>? description,
    Expression<double>? balanceAfter,
    Expression<String>? refId,
    Expression<String>? parseSource,
    Expression<String>? smsId,
    Expression<String>? confidenceJson,
    Expression<String>? status,
    Expression<bool>? isDeleted,
    Expression<String>? counterpartyVpa,
    Expression<String>? duplicateOfTxnId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ts != null) 'ts': ts,
      if (amount != null) 'amount': amount,
      if (direction != null) 'direction': direction,
      if (channel != null) 'channel': channel,
      if (accountHint != null) 'account_hint': accountHint,
      if (merchantRaw != null) 'merchant_raw': merchantRaw,
      if (merchantId != null) 'merchant_id': merchantId,
      if (categoryId != null) 'category_id': categoryId,
      if (description != null) 'description': description,
      if (balanceAfter != null) 'balance_after': balanceAfter,
      if (refId != null) 'ref_id': refId,
      if (parseSource != null) 'parse_source': parseSource,
      if (smsId != null) 'sms_id': smsId,
      if (confidenceJson != null) 'confidence_json': confidenceJson,
      if (status != null) 'status': status,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (counterpartyVpa != null) 'counterparty_vpa': counterpartyVpa,
      if (duplicateOfTxnId != null) 'duplicate_of_txn_id': duplicateOfTxnId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith(
      {Value<String>? id,
      Value<int>? ts,
      Value<double>? amount,
      Value<String>? direction,
      Value<String>? channel,
      Value<String?>? accountHint,
      Value<String?>? merchantRaw,
      Value<String?>? merchantId,
      Value<String?>? categoryId,
      Value<String?>? description,
      Value<double?>? balanceAfter,
      Value<String?>? refId,
      Value<String>? parseSource,
      Value<String?>? smsId,
      Value<String>? confidenceJson,
      Value<String>? status,
      Value<bool>? isDeleted,
      Value<String?>? counterpartyVpa,
      Value<String?>? duplicateOfTxnId,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return TransactionsCompanion(
      id: id ?? this.id,
      ts: ts ?? this.ts,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      channel: channel ?? this.channel,
      accountHint: accountHint ?? this.accountHint,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantId: merchantId ?? this.merchantId,
      categoryId: categoryId ?? this.categoryId,
      description: description ?? this.description,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      refId: refId ?? this.refId,
      parseSource: parseSource ?? this.parseSource,
      smsId: smsId ?? this.smsId,
      confidenceJson: confidenceJson ?? this.confidenceJson,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
      counterpartyVpa: counterpartyVpa ?? this.counterpartyVpa,
      duplicateOfTxnId: duplicateOfTxnId ?? this.duplicateOfTxnId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ts.present) {
      map['ts'] = Variable<int>(ts.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (accountHint.present) {
      map['account_hint'] = Variable<String>(accountHint.value);
    }
    if (merchantRaw.present) {
      map['merchant_raw'] = Variable<String>(merchantRaw.value);
    }
    if (merchantId.present) {
      map['merchant_id'] = Variable<String>(merchantId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (balanceAfter.present) {
      map['balance_after'] = Variable<double>(balanceAfter.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (parseSource.present) {
      map['parse_source'] = Variable<String>(parseSource.value);
    }
    if (smsId.present) {
      map['sms_id'] = Variable<String>(smsId.value);
    }
    if (confidenceJson.present) {
      map['confidence_json'] = Variable<String>(confidenceJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (counterpartyVpa.present) {
      map['counterparty_vpa'] = Variable<String>(counterpartyVpa.value);
    }
    if (duplicateOfTxnId.present) {
      map['duplicate_of_txn_id'] = Variable<String>(duplicateOfTxnId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('ts: $ts, ')
          ..write('amount: $amount, ')
          ..write('direction: $direction, ')
          ..write('channel: $channel, ')
          ..write('accountHint: $accountHint, ')
          ..write('merchantRaw: $merchantRaw, ')
          ..write('merchantId: $merchantId, ')
          ..write('categoryId: $categoryId, ')
          ..write('description: $description, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('refId: $refId, ')
          ..write('parseSource: $parseSource, ')
          ..write('smsId: $smsId, ')
          ..write('confidenceJson: $confidenceJson, ')
          ..write('status: $status, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('counterpartyVpa: $counterpartyVpa, ')
          ..write('duplicateOfTxnId: $duplicateOfTxnId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FeedbackTable extends Feedback
    with TableInfo<$FeedbackTable, FeedbackData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeedbackTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _txnIdMeta = const VerificationMeta('txnId');
  @override
  late final GeneratedColumn<String> txnId = GeneratedColumn<String>(
      'txn_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES transactions (id)'));
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
      'field', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _oldValueMeta =
      const VerificationMeta('oldValue');
  @override
  late final GeneratedColumn<String> oldValue = GeneratedColumn<String>(
      'old_value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _newValueMeta =
      const VerificationMeta('newValue');
  @override
  late final GeneratedColumn<String> newValue = GeneratedColumn<String>(
      'new_value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _contextMeta =
      const VerificationMeta('context');
  @override
  late final GeneratedColumn<String> context = GeneratedColumn<String>(
      'context', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelConfidenceAtTimeMeta =
      const VerificationMeta('modelConfidenceAtTime');
  @override
  late final GeneratedColumn<double> modelConfidenceAtTime =
      GeneratedColumn<double>('model_confidence_at_time', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        txnId,
        field,
        oldValue,
        newValue,
        context,
        modelConfidenceAtTime,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feedback';
  @override
  VerificationContext validateIntegrity(Insertable<FeedbackData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('txn_id')) {
      context.handle(
          _txnIdMeta, txnId.isAcceptableOrUnknown(data['txn_id']!, _txnIdMeta));
    } else if (isInserting) {
      context.missing(_txnIdMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
          _fieldMeta, field.isAcceptableOrUnknown(data['field']!, _fieldMeta));
    } else if (isInserting) {
      context.missing(_fieldMeta);
    }
    if (data.containsKey('old_value')) {
      context.handle(_oldValueMeta,
          oldValue.isAcceptableOrUnknown(data['old_value']!, _oldValueMeta));
    }
    if (data.containsKey('new_value')) {
      context.handle(_newValueMeta,
          newValue.isAcceptableOrUnknown(data['new_value']!, _newValueMeta));
    }
    if (data.containsKey('context')) {
      context.handle(_contextMeta,
          this.context.isAcceptableOrUnknown(data['context']!, _contextMeta));
    } else if (isInserting) {
      context.missing(_contextMeta);
    }
    if (data.containsKey('model_confidence_at_time')) {
      context.handle(
          _modelConfidenceAtTimeMeta,
          modelConfidenceAtTime.isAcceptableOrUnknown(
              data['model_confidence_at_time']!, _modelConfidenceAtTimeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FeedbackData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FeedbackData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      txnId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}txn_id'])!,
      field: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}field'])!,
      oldValue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}old_value']),
      newValue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}new_value']),
      context: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}context'])!,
      modelConfidenceAtTime: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}model_confidence_at_time']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FeedbackTable createAlias(String alias) {
    return $FeedbackTable(attachedDatabase, alias);
  }
}

class FeedbackData extends DataClass implements Insertable<FeedbackData> {
  final String id;
  final String txnId;
  final String field;
  final String? oldValue;
  final String? newValue;
  final String context;
  final double? modelConfidenceAtTime;
  final DateTime createdAt;
  const FeedbackData(
      {required this.id,
      required this.txnId,
      required this.field,
      this.oldValue,
      this.newValue,
      required this.context,
      this.modelConfidenceAtTime,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['txn_id'] = Variable<String>(txnId);
    map['field'] = Variable<String>(field);
    if (!nullToAbsent || oldValue != null) {
      map['old_value'] = Variable<String>(oldValue);
    }
    if (!nullToAbsent || newValue != null) {
      map['new_value'] = Variable<String>(newValue);
    }
    map['context'] = Variable<String>(context);
    if (!nullToAbsent || modelConfidenceAtTime != null) {
      map['model_confidence_at_time'] = Variable<double>(modelConfidenceAtTime);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FeedbackCompanion toCompanion(bool nullToAbsent) {
    return FeedbackCompanion(
      id: Value(id),
      txnId: Value(txnId),
      field: Value(field),
      oldValue: oldValue == null && nullToAbsent
          ? const Value.absent()
          : Value(oldValue),
      newValue: newValue == null && nullToAbsent
          ? const Value.absent()
          : Value(newValue),
      context: Value(context),
      modelConfidenceAtTime: modelConfidenceAtTime == null && nullToAbsent
          ? const Value.absent()
          : Value(modelConfidenceAtTime),
      createdAt: Value(createdAt),
    );
  }

  factory FeedbackData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FeedbackData(
      id: serializer.fromJson<String>(json['id']),
      txnId: serializer.fromJson<String>(json['txnId']),
      field: serializer.fromJson<String>(json['field']),
      oldValue: serializer.fromJson<String?>(json['oldValue']),
      newValue: serializer.fromJson<String?>(json['newValue']),
      context: serializer.fromJson<String>(json['context']),
      modelConfidenceAtTime:
          serializer.fromJson<double?>(json['modelConfidenceAtTime']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'txnId': serializer.toJson<String>(txnId),
      'field': serializer.toJson<String>(field),
      'oldValue': serializer.toJson<String?>(oldValue),
      'newValue': serializer.toJson<String?>(newValue),
      'context': serializer.toJson<String>(context),
      'modelConfidenceAtTime':
          serializer.toJson<double?>(modelConfidenceAtTime),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FeedbackData copyWith(
          {String? id,
          String? txnId,
          String? field,
          Value<String?> oldValue = const Value.absent(),
          Value<String?> newValue = const Value.absent(),
          String? context,
          Value<double?> modelConfidenceAtTime = const Value.absent(),
          DateTime? createdAt}) =>
      FeedbackData(
        id: id ?? this.id,
        txnId: txnId ?? this.txnId,
        field: field ?? this.field,
        oldValue: oldValue.present ? oldValue.value : this.oldValue,
        newValue: newValue.present ? newValue.value : this.newValue,
        context: context ?? this.context,
        modelConfidenceAtTime: modelConfidenceAtTime.present
            ? modelConfidenceAtTime.value
            : this.modelConfidenceAtTime,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('FeedbackData(')
          ..write('id: $id, ')
          ..write('txnId: $txnId, ')
          ..write('field: $field, ')
          ..write('oldValue: $oldValue, ')
          ..write('newValue: $newValue, ')
          ..write('context: $context, ')
          ..write('modelConfidenceAtTime: $modelConfidenceAtTime, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, txnId, field, oldValue, newValue, context,
      modelConfidenceAtTime, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeedbackData &&
          other.id == this.id &&
          other.txnId == this.txnId &&
          other.field == this.field &&
          other.oldValue == this.oldValue &&
          other.newValue == this.newValue &&
          other.context == this.context &&
          other.modelConfidenceAtTime == this.modelConfidenceAtTime &&
          other.createdAt == this.createdAt);
}

class FeedbackCompanion extends UpdateCompanion<FeedbackData> {
  final Value<String> id;
  final Value<String> txnId;
  final Value<String> field;
  final Value<String?> oldValue;
  final Value<String?> newValue;
  final Value<String> context;
  final Value<double?> modelConfidenceAtTime;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FeedbackCompanion({
    this.id = const Value.absent(),
    this.txnId = const Value.absent(),
    this.field = const Value.absent(),
    this.oldValue = const Value.absent(),
    this.newValue = const Value.absent(),
    this.context = const Value.absent(),
    this.modelConfidenceAtTime = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FeedbackCompanion.insert({
    required String id,
    required String txnId,
    required String field,
    this.oldValue = const Value.absent(),
    this.newValue = const Value.absent(),
    required String context,
    this.modelConfidenceAtTime = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        txnId = Value(txnId),
        field = Value(field),
        context = Value(context),
        createdAt = Value(createdAt);
  static Insertable<FeedbackData> custom({
    Expression<String>? id,
    Expression<String>? txnId,
    Expression<String>? field,
    Expression<String>? oldValue,
    Expression<String>? newValue,
    Expression<String>? context,
    Expression<double>? modelConfidenceAtTime,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (txnId != null) 'txn_id': txnId,
      if (field != null) 'field': field,
      if (oldValue != null) 'old_value': oldValue,
      if (newValue != null) 'new_value': newValue,
      if (context != null) 'context': context,
      if (modelConfidenceAtTime != null)
        'model_confidence_at_time': modelConfidenceAtTime,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FeedbackCompanion copyWith(
      {Value<String>? id,
      Value<String>? txnId,
      Value<String>? field,
      Value<String?>? oldValue,
      Value<String?>? newValue,
      Value<String>? context,
      Value<double?>? modelConfidenceAtTime,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return FeedbackCompanion(
      id: id ?? this.id,
      txnId: txnId ?? this.txnId,
      field: field ?? this.field,
      oldValue: oldValue ?? this.oldValue,
      newValue: newValue ?? this.newValue,
      context: context ?? this.context,
      modelConfidenceAtTime:
          modelConfidenceAtTime ?? this.modelConfidenceAtTime,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (txnId.present) {
      map['txn_id'] = Variable<String>(txnId.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (oldValue.present) {
      map['old_value'] = Variable<String>(oldValue.value);
    }
    if (newValue.present) {
      map['new_value'] = Variable<String>(newValue.value);
    }
    if (context.present) {
      map['context'] = Variable<String>(context.value);
    }
    if (modelConfidenceAtTime.present) {
      map['model_confidence_at_time'] =
          Variable<double>(modelConfidenceAtTime.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeedbackCompanion(')
          ..write('id: $id, ')
          ..write('txnId: $txnId, ')
          ..write('field: $field, ')
          ..write('oldValue: $oldValue, ')
          ..write('newValue: $newValue, ')
          ..write('context: $context, ')
          ..write('modelConfidenceAtTime: $modelConfidenceAtTime, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InsightsTable extends Insights with TableInfo<$InsightsTable, Insight> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InsightsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
      'period', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dismissedMeta =
      const VerificationMeta('dismissed');
  @override
  late final GeneratedColumn<bool> dismissed = GeneratedColumn<bool>(
      'dismissed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("dismissed" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, period, kind, payloadJson, dismissed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'insights';
  @override
  VerificationContext validateIntegrity(Insertable<Insight> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('period')) {
      context.handle(_periodMeta,
          period.isAcceptableOrUnknown(data['period']!, _periodMeta));
    } else if (isInserting) {
      context.missing(_periodMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('dismissed')) {
      context.handle(_dismissedMeta,
          dismissed.isAcceptableOrUnknown(data['dismissed']!, _dismissedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Insight map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Insight(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      period: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}period'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      dismissed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}dismissed'])!,
    );
  }

  @override
  $InsightsTable createAlias(String alias) {
    return $InsightsTable(attachedDatabase, alias);
  }
}

class Insight extends DataClass implements Insertable<Insight> {
  final String id;
  final String period;
  final String kind;
  final String payloadJson;
  final bool dismissed;
  const Insight(
      {required this.id,
      required this.period,
      required this.kind,
      required this.payloadJson,
      required this.dismissed});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['period'] = Variable<String>(period);
    map['kind'] = Variable<String>(kind);
    map['payload_json'] = Variable<String>(payloadJson);
    map['dismissed'] = Variable<bool>(dismissed);
    return map;
  }

  InsightsCompanion toCompanion(bool nullToAbsent) {
    return InsightsCompanion(
      id: Value(id),
      period: Value(period),
      kind: Value(kind),
      payloadJson: Value(payloadJson),
      dismissed: Value(dismissed),
    );
  }

  factory Insight.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Insight(
      id: serializer.fromJson<String>(json['id']),
      period: serializer.fromJson<String>(json['period']),
      kind: serializer.fromJson<String>(json['kind']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      dismissed: serializer.fromJson<bool>(json['dismissed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'period': serializer.toJson<String>(period),
      'kind': serializer.toJson<String>(kind),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'dismissed': serializer.toJson<bool>(dismissed),
    };
  }

  Insight copyWith(
          {String? id,
          String? period,
          String? kind,
          String? payloadJson,
          bool? dismissed}) =>
      Insight(
        id: id ?? this.id,
        period: period ?? this.period,
        kind: kind ?? this.kind,
        payloadJson: payloadJson ?? this.payloadJson,
        dismissed: dismissed ?? this.dismissed,
      );
  @override
  String toString() {
    return (StringBuffer('Insight(')
          ..write('id: $id, ')
          ..write('period: $period, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('dismissed: $dismissed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, period, kind, payloadJson, dismissed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Insight &&
          other.id == this.id &&
          other.period == this.period &&
          other.kind == this.kind &&
          other.payloadJson == this.payloadJson &&
          other.dismissed == this.dismissed);
}

class InsightsCompanion extends UpdateCompanion<Insight> {
  final Value<String> id;
  final Value<String> period;
  final Value<String> kind;
  final Value<String> payloadJson;
  final Value<bool> dismissed;
  final Value<int> rowid;
  const InsightsCompanion({
    this.id = const Value.absent(),
    this.period = const Value.absent(),
    this.kind = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.dismissed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InsightsCompanion.insert({
    required String id,
    required String period,
    required String kind,
    required String payloadJson,
    this.dismissed = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        period = Value(period),
        kind = Value(kind),
        payloadJson = Value(payloadJson);
  static Insertable<Insight> custom({
    Expression<String>? id,
    Expression<String>? period,
    Expression<String>? kind,
    Expression<String>? payloadJson,
    Expression<bool>? dismissed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (period != null) 'period': period,
      if (kind != null) 'kind': kind,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (dismissed != null) 'dismissed': dismissed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InsightsCompanion copyWith(
      {Value<String>? id,
      Value<String>? period,
      Value<String>? kind,
      Value<String>? payloadJson,
      Value<bool>? dismissed,
      Value<int>? rowid}) {
    return InsightsCompanion(
      id: id ?? this.id,
      period: period ?? this.period,
      kind: kind ?? this.kind,
      payloadJson: payloadJson ?? this.payloadJson,
      dismissed: dismissed ?? this.dismissed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (dismissed.present) {
      map['dismissed'] = Variable<bool>(dismissed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InsightsCompanion(')
          ..write('id: $id, ')
          ..write('period: $period, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('dismissed: $dismissed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MerchantAliasesTable extends MerchantAliases
    with TableInfo<$MerchantAliasesTable, MerchantAliase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MerchantAliasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
      'alias', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _merchantIdMeta =
      const VerificationMeta('merchantId');
  @override
  late final GeneratedColumn<String> merchantId = GeneratedColumn<String>(
      'merchant_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES merchants (id)'));
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _confidenceMeta =
      const VerificationMeta('confidence');
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
      'confidence', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [alias, merchantId, source, confidence];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'merchant_aliases';
  @override
  VerificationContext validateIntegrity(Insertable<MerchantAliase> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('alias')) {
      context.handle(
          _aliasMeta, alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta));
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('merchant_id')) {
      context.handle(
          _merchantIdMeta,
          merchantId.isAcceptableOrUnknown(
              data['merchant_id']!, _merchantIdMeta));
    } else if (isInserting) {
      context.missing(_merchantIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
          _confidenceMeta,
          confidence.isAcceptableOrUnknown(
              data['confidence']!, _confidenceMeta));
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {alias};
  @override
  MerchantAliase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MerchantAliase(
      alias: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}alias'])!,
      merchantId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merchant_id'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      confidence: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}confidence'])!,
    );
  }

  @override
  $MerchantAliasesTable createAlias(String alias) {
    return $MerchantAliasesTable(attachedDatabase, alias);
  }
}

class MerchantAliase extends DataClass implements Insertable<MerchantAliase> {
  final String alias;
  final String merchantId;
  final String source;
  final double confidence;
  const MerchantAliase(
      {required this.alias,
      required this.merchantId,
      required this.source,
      required this.confidence});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['alias'] = Variable<String>(alias);
    map['merchant_id'] = Variable<String>(merchantId);
    map['source'] = Variable<String>(source);
    map['confidence'] = Variable<double>(confidence);
    return map;
  }

  MerchantAliasesCompanion toCompanion(bool nullToAbsent) {
    return MerchantAliasesCompanion(
      alias: Value(alias),
      merchantId: Value(merchantId),
      source: Value(source),
      confidence: Value(confidence),
    );
  }

  factory MerchantAliase.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MerchantAliase(
      alias: serializer.fromJson<String>(json['alias']),
      merchantId: serializer.fromJson<String>(json['merchantId']),
      source: serializer.fromJson<String>(json['source']),
      confidence: serializer.fromJson<double>(json['confidence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'alias': serializer.toJson<String>(alias),
      'merchantId': serializer.toJson<String>(merchantId),
      'source': serializer.toJson<String>(source),
      'confidence': serializer.toJson<double>(confidence),
    };
  }

  MerchantAliase copyWith(
          {String? alias,
          String? merchantId,
          String? source,
          double? confidence}) =>
      MerchantAliase(
        alias: alias ?? this.alias,
        merchantId: merchantId ?? this.merchantId,
        source: source ?? this.source,
        confidence: confidence ?? this.confidence,
      );
  @override
  String toString() {
    return (StringBuffer('MerchantAliase(')
          ..write('alias: $alias, ')
          ..write('merchantId: $merchantId, ')
          ..write('source: $source, ')
          ..write('confidence: $confidence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(alias, merchantId, source, confidence);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MerchantAliase &&
          other.alias == this.alias &&
          other.merchantId == this.merchantId &&
          other.source == this.source &&
          other.confidence == this.confidence);
}

class MerchantAliasesCompanion extends UpdateCompanion<MerchantAliase> {
  final Value<String> alias;
  final Value<String> merchantId;
  final Value<String> source;
  final Value<double> confidence;
  final Value<int> rowid;
  const MerchantAliasesCompanion({
    this.alias = const Value.absent(),
    this.merchantId = const Value.absent(),
    this.source = const Value.absent(),
    this.confidence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MerchantAliasesCompanion.insert({
    required String alias,
    required String merchantId,
    required String source,
    required double confidence,
    this.rowid = const Value.absent(),
  })  : alias = Value(alias),
        merchantId = Value(merchantId),
        source = Value(source),
        confidence = Value(confidence);
  static Insertable<MerchantAliase> custom({
    Expression<String>? alias,
    Expression<String>? merchantId,
    Expression<String>? source,
    Expression<double>? confidence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (alias != null) 'alias': alias,
      if (merchantId != null) 'merchant_id': merchantId,
      if (source != null) 'source': source,
      if (confidence != null) 'confidence': confidence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MerchantAliasesCompanion copyWith(
      {Value<String>? alias,
      Value<String>? merchantId,
      Value<String>? source,
      Value<double>? confidence,
      Value<int>? rowid}) {
    return MerchantAliasesCompanion(
      alias: alias ?? this.alias,
      merchantId: merchantId ?? this.merchantId,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (merchantId.present) {
      map['merchant_id'] = Variable<String>(merchantId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MerchantAliasesCompanion(')
          ..write('alias: $alias, ')
          ..write('merchantId: $merchantId, ')
          ..write('source: $source, ')
          ..write('confidence: $confidence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModelMetaTable extends ModelMeta
    with TableInfo<$ModelMetaTable, ModelMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'model_meta';
  @override
  VerificationContext validateIntegrity(Insertable<ModelMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ModelMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModelMetaData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $ModelMetaTable createAlias(String alias) {
    return $ModelMetaTable(attachedDatabase, alias);
  }
}

class ModelMetaData extends DataClass implements Insertable<ModelMetaData> {
  final String key;
  final String value;
  const ModelMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  ModelMetaCompanion toCompanion(bool nullToAbsent) {
    return ModelMetaCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory ModelMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModelMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  ModelMetaData copyWith({String? key, String? value}) => ModelMetaData(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  @override
  String toString() {
    return (StringBuffer('ModelMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModelMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class ModelMetaCompanion extends UpdateCompanion<ModelMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const ModelMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<ModelMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelMetaCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return ModelMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecurringSeriesTable extends RecurringSeries
    with TableInfo<$RecurringSeriesTable, RecurringSery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecurringSeriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _merchantIdMeta =
      const VerificationMeta('merchantId');
  @override
  late final GeneratedColumn<String> merchantId = GeneratedColumn<String>(
      'merchant_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES merchants (id)'));
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _expectedAmountMeta =
      const VerificationMeta('expectedAmount');
  @override
  late final GeneratedColumn<double> expectedAmount = GeneratedColumn<double>(
      'expected_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _tolerancePctMeta =
      const VerificationMeta('tolerancePct');
  @override
  late final GeneratedColumn<double> tolerancePct = GeneratedColumn<double>(
      'tolerance_pct', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
      'period', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _periodDaysMeta =
      const VerificationMeta('periodDays');
  @override
  late final GeneratedColumn<int> periodDays = GeneratedColumn<int>(
      'period_days', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nextExpectedDateMeta =
      const VerificationMeta('nextExpectedDate');
  @override
  late final GeneratedColumn<DateTime> nextExpectedDate =
      GeneratedColumn<DateTime>('next_expected_date', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastAmountMeta =
      const VerificationMeta('lastAmount');
  @override
  late final GeneratedColumn<double> lastAmount = GeneratedColumn<double>(
      'last_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _amountTrendMeta =
      const VerificationMeta('amountTrend');
  @override
  late final GeneratedColumn<String> amountTrend = GeneratedColumn<String>(
      'amount_trend', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _occurrencesMeta =
      const VerificationMeta('occurrences');
  @override
  late final GeneratedColumn<int> occurrences = GeneratedColumn<int>(
      'occurrences', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        merchantId,
        label,
        expectedAmount,
        tolerancePct,
        period,
        periodDays,
        nextExpectedDate,
        lastAmount,
        amountTrend,
        occurrences,
        status,
        kind
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recurring_series';
  @override
  VerificationContext validateIntegrity(Insertable<RecurringSery> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('merchant_id')) {
      context.handle(
          _merchantIdMeta,
          merchantId.isAcceptableOrUnknown(
              data['merchant_id']!, _merchantIdMeta));
    } else if (isInserting) {
      context.missing(_merchantIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('expected_amount')) {
      context.handle(
          _expectedAmountMeta,
          expectedAmount.isAcceptableOrUnknown(
              data['expected_amount']!, _expectedAmountMeta));
    } else if (isInserting) {
      context.missing(_expectedAmountMeta);
    }
    if (data.containsKey('tolerance_pct')) {
      context.handle(
          _tolerancePctMeta,
          tolerancePct.isAcceptableOrUnknown(
              data['tolerance_pct']!, _tolerancePctMeta));
    } else if (isInserting) {
      context.missing(_tolerancePctMeta);
    }
    if (data.containsKey('period')) {
      context.handle(_periodMeta,
          period.isAcceptableOrUnknown(data['period']!, _periodMeta));
    } else if (isInserting) {
      context.missing(_periodMeta);
    }
    if (data.containsKey('period_days')) {
      context.handle(
          _periodDaysMeta,
          periodDays.isAcceptableOrUnknown(
              data['period_days']!, _periodDaysMeta));
    } else if (isInserting) {
      context.missing(_periodDaysMeta);
    }
    if (data.containsKey('next_expected_date')) {
      context.handle(
          _nextExpectedDateMeta,
          nextExpectedDate.isAcceptableOrUnknown(
              data['next_expected_date']!, _nextExpectedDateMeta));
    } else if (isInserting) {
      context.missing(_nextExpectedDateMeta);
    }
    if (data.containsKey('last_amount')) {
      context.handle(
          _lastAmountMeta,
          lastAmount.isAcceptableOrUnknown(
              data['last_amount']!, _lastAmountMeta));
    } else if (isInserting) {
      context.missing(_lastAmountMeta);
    }
    if (data.containsKey('amount_trend')) {
      context.handle(
          _amountTrendMeta,
          amountTrend.isAcceptableOrUnknown(
              data['amount_trend']!, _amountTrendMeta));
    } else if (isInserting) {
      context.missing(_amountTrendMeta);
    }
    if (data.containsKey('occurrences')) {
      context.handle(
          _occurrencesMeta,
          occurrences.isAcceptableOrUnknown(
              data['occurrences']!, _occurrencesMeta));
    } else if (isInserting) {
      context.missing(_occurrencesMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecurringSery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecurringSery(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      merchantId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merchant_id'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      expectedAmount: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}expected_amount'])!,
      tolerancePct: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}tolerance_pct'])!,
      period: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}period'])!,
      periodDays: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}period_days'])!,
      nextExpectedDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}next_expected_date'])!,
      lastAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}last_amount'])!,
      amountTrend: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}amount_trend'])!,
      occurrences: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}occurrences'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
    );
  }

  @override
  $RecurringSeriesTable createAlias(String alias) {
    return $RecurringSeriesTable(attachedDatabase, alias);
  }
}

class RecurringSery extends DataClass implements Insertable<RecurringSery> {
  final String id;
  final String merchantId;
  final String label;
  final double expectedAmount;
  final double tolerancePct;
  final String period;
  final int periodDays;
  final DateTime nextExpectedDate;
  final double lastAmount;
  final String amountTrend;
  final int occurrences;
  final String status;
  final String kind;
  const RecurringSery(
      {required this.id,
      required this.merchantId,
      required this.label,
      required this.expectedAmount,
      required this.tolerancePct,
      required this.period,
      required this.periodDays,
      required this.nextExpectedDate,
      required this.lastAmount,
      required this.amountTrend,
      required this.occurrences,
      required this.status,
      required this.kind});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['merchant_id'] = Variable<String>(merchantId);
    map['label'] = Variable<String>(label);
    map['expected_amount'] = Variable<double>(expectedAmount);
    map['tolerance_pct'] = Variable<double>(tolerancePct);
    map['period'] = Variable<String>(period);
    map['period_days'] = Variable<int>(periodDays);
    map['next_expected_date'] = Variable<DateTime>(nextExpectedDate);
    map['last_amount'] = Variable<double>(lastAmount);
    map['amount_trend'] = Variable<String>(amountTrend);
    map['occurrences'] = Variable<int>(occurrences);
    map['status'] = Variable<String>(status);
    map['kind'] = Variable<String>(kind);
    return map;
  }

  RecurringSeriesCompanion toCompanion(bool nullToAbsent) {
    return RecurringSeriesCompanion(
      id: Value(id),
      merchantId: Value(merchantId),
      label: Value(label),
      expectedAmount: Value(expectedAmount),
      tolerancePct: Value(tolerancePct),
      period: Value(period),
      periodDays: Value(periodDays),
      nextExpectedDate: Value(nextExpectedDate),
      lastAmount: Value(lastAmount),
      amountTrend: Value(amountTrend),
      occurrences: Value(occurrences),
      status: Value(status),
      kind: Value(kind),
    );
  }

  factory RecurringSery.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecurringSery(
      id: serializer.fromJson<String>(json['id']),
      merchantId: serializer.fromJson<String>(json['merchantId']),
      label: serializer.fromJson<String>(json['label']),
      expectedAmount: serializer.fromJson<double>(json['expectedAmount']),
      tolerancePct: serializer.fromJson<double>(json['tolerancePct']),
      period: serializer.fromJson<String>(json['period']),
      periodDays: serializer.fromJson<int>(json['periodDays']),
      nextExpectedDate: serializer.fromJson<DateTime>(json['nextExpectedDate']),
      lastAmount: serializer.fromJson<double>(json['lastAmount']),
      amountTrend: serializer.fromJson<String>(json['amountTrend']),
      occurrences: serializer.fromJson<int>(json['occurrences']),
      status: serializer.fromJson<String>(json['status']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'merchantId': serializer.toJson<String>(merchantId),
      'label': serializer.toJson<String>(label),
      'expectedAmount': serializer.toJson<double>(expectedAmount),
      'tolerancePct': serializer.toJson<double>(tolerancePct),
      'period': serializer.toJson<String>(period),
      'periodDays': serializer.toJson<int>(periodDays),
      'nextExpectedDate': serializer.toJson<DateTime>(nextExpectedDate),
      'lastAmount': serializer.toJson<double>(lastAmount),
      'amountTrend': serializer.toJson<String>(amountTrend),
      'occurrences': serializer.toJson<int>(occurrences),
      'status': serializer.toJson<String>(status),
      'kind': serializer.toJson<String>(kind),
    };
  }

  RecurringSery copyWith(
          {String? id,
          String? merchantId,
          String? label,
          double? expectedAmount,
          double? tolerancePct,
          String? period,
          int? periodDays,
          DateTime? nextExpectedDate,
          double? lastAmount,
          String? amountTrend,
          int? occurrences,
          String? status,
          String? kind}) =>
      RecurringSery(
        id: id ?? this.id,
        merchantId: merchantId ?? this.merchantId,
        label: label ?? this.label,
        expectedAmount: expectedAmount ?? this.expectedAmount,
        tolerancePct: tolerancePct ?? this.tolerancePct,
        period: period ?? this.period,
        periodDays: periodDays ?? this.periodDays,
        nextExpectedDate: nextExpectedDate ?? this.nextExpectedDate,
        lastAmount: lastAmount ?? this.lastAmount,
        amountTrend: amountTrend ?? this.amountTrend,
        occurrences: occurrences ?? this.occurrences,
        status: status ?? this.status,
        kind: kind ?? this.kind,
      );
  @override
  String toString() {
    return (StringBuffer('RecurringSery(')
          ..write('id: $id, ')
          ..write('merchantId: $merchantId, ')
          ..write('label: $label, ')
          ..write('expectedAmount: $expectedAmount, ')
          ..write('tolerancePct: $tolerancePct, ')
          ..write('period: $period, ')
          ..write('periodDays: $periodDays, ')
          ..write('nextExpectedDate: $nextExpectedDate, ')
          ..write('lastAmount: $lastAmount, ')
          ..write('amountTrend: $amountTrend, ')
          ..write('occurrences: $occurrences, ')
          ..write('status: $status, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      merchantId,
      label,
      expectedAmount,
      tolerancePct,
      period,
      periodDays,
      nextExpectedDate,
      lastAmount,
      amountTrend,
      occurrences,
      status,
      kind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecurringSery &&
          other.id == this.id &&
          other.merchantId == this.merchantId &&
          other.label == this.label &&
          other.expectedAmount == this.expectedAmount &&
          other.tolerancePct == this.tolerancePct &&
          other.period == this.period &&
          other.periodDays == this.periodDays &&
          other.nextExpectedDate == this.nextExpectedDate &&
          other.lastAmount == this.lastAmount &&
          other.amountTrend == this.amountTrend &&
          other.occurrences == this.occurrences &&
          other.status == this.status &&
          other.kind == this.kind);
}

class RecurringSeriesCompanion extends UpdateCompanion<RecurringSery> {
  final Value<String> id;
  final Value<String> merchantId;
  final Value<String> label;
  final Value<double> expectedAmount;
  final Value<double> tolerancePct;
  final Value<String> period;
  final Value<int> periodDays;
  final Value<DateTime> nextExpectedDate;
  final Value<double> lastAmount;
  final Value<String> amountTrend;
  final Value<int> occurrences;
  final Value<String> status;
  final Value<String> kind;
  final Value<int> rowid;
  const RecurringSeriesCompanion({
    this.id = const Value.absent(),
    this.merchantId = const Value.absent(),
    this.label = const Value.absent(),
    this.expectedAmount = const Value.absent(),
    this.tolerancePct = const Value.absent(),
    this.period = const Value.absent(),
    this.periodDays = const Value.absent(),
    this.nextExpectedDate = const Value.absent(),
    this.lastAmount = const Value.absent(),
    this.amountTrend = const Value.absent(),
    this.occurrences = const Value.absent(),
    this.status = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecurringSeriesCompanion.insert({
    required String id,
    required String merchantId,
    required String label,
    required double expectedAmount,
    required double tolerancePct,
    required String period,
    required int periodDays,
    required DateTime nextExpectedDate,
    required double lastAmount,
    required String amountTrend,
    required int occurrences,
    required String status,
    required String kind,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        merchantId = Value(merchantId),
        label = Value(label),
        expectedAmount = Value(expectedAmount),
        tolerancePct = Value(tolerancePct),
        period = Value(period),
        periodDays = Value(periodDays),
        nextExpectedDate = Value(nextExpectedDate),
        lastAmount = Value(lastAmount),
        amountTrend = Value(amountTrend),
        occurrences = Value(occurrences),
        status = Value(status),
        kind = Value(kind);
  static Insertable<RecurringSery> custom({
    Expression<String>? id,
    Expression<String>? merchantId,
    Expression<String>? label,
    Expression<double>? expectedAmount,
    Expression<double>? tolerancePct,
    Expression<String>? period,
    Expression<int>? periodDays,
    Expression<DateTime>? nextExpectedDate,
    Expression<double>? lastAmount,
    Expression<String>? amountTrend,
    Expression<int>? occurrences,
    Expression<String>? status,
    Expression<String>? kind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (merchantId != null) 'merchant_id': merchantId,
      if (label != null) 'label': label,
      if (expectedAmount != null) 'expected_amount': expectedAmount,
      if (tolerancePct != null) 'tolerance_pct': tolerancePct,
      if (period != null) 'period': period,
      if (periodDays != null) 'period_days': periodDays,
      if (nextExpectedDate != null) 'next_expected_date': nextExpectedDate,
      if (lastAmount != null) 'last_amount': lastAmount,
      if (amountTrend != null) 'amount_trend': amountTrend,
      if (occurrences != null) 'occurrences': occurrences,
      if (status != null) 'status': status,
      if (kind != null) 'kind': kind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecurringSeriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? merchantId,
      Value<String>? label,
      Value<double>? expectedAmount,
      Value<double>? tolerancePct,
      Value<String>? period,
      Value<int>? periodDays,
      Value<DateTime>? nextExpectedDate,
      Value<double>? lastAmount,
      Value<String>? amountTrend,
      Value<int>? occurrences,
      Value<String>? status,
      Value<String>? kind,
      Value<int>? rowid}) {
    return RecurringSeriesCompanion(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      label: label ?? this.label,
      expectedAmount: expectedAmount ?? this.expectedAmount,
      tolerancePct: tolerancePct ?? this.tolerancePct,
      period: period ?? this.period,
      periodDays: periodDays ?? this.periodDays,
      nextExpectedDate: nextExpectedDate ?? this.nextExpectedDate,
      lastAmount: lastAmount ?? this.lastAmount,
      amountTrend: amountTrend ?? this.amountTrend,
      occurrences: occurrences ?? this.occurrences,
      status: status ?? this.status,
      kind: kind ?? this.kind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (merchantId.present) {
      map['merchant_id'] = Variable<String>(merchantId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (expectedAmount.present) {
      map['expected_amount'] = Variable<double>(expectedAmount.value);
    }
    if (tolerancePct.present) {
      map['tolerance_pct'] = Variable<double>(tolerancePct.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (periodDays.present) {
      map['period_days'] = Variable<int>(periodDays.value);
    }
    if (nextExpectedDate.present) {
      map['next_expected_date'] = Variable<DateTime>(nextExpectedDate.value);
    }
    if (lastAmount.present) {
      map['last_amount'] = Variable<double>(lastAmount.value);
    }
    if (amountTrend.present) {
      map['amount_trend'] = Variable<String>(amountTrend.value);
    }
    if (occurrences.present) {
      map['occurrences'] = Variable<int>(occurrences.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecurringSeriesCompanion(')
          ..write('id: $id, ')
          ..write('merchantId: $merchantId, ')
          ..write('label: $label, ')
          ..write('expectedAmount: $expectedAmount, ')
          ..write('tolerancePct: $tolerancePct, ')
          ..write('period: $period, ')
          ..write('periodDays: $periodDays, ')
          ..write('nextExpectedDate: $nextExpectedDate, ')
          ..write('lastAmount: $lastAmount, ')
          ..write('amountTrend: $amountTrend, ')
          ..write('occurrences: $occurrences, ')
          ..write('status: $status, ')
          ..write('kind: $kind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RulesTable extends Rules with TableInfo<$RulesTable, Rule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _matchTypeMeta =
      const VerificationMeta('matchType');
  @override
  late final GeneratedColumn<String> matchType = GeneratedColumn<String>(
      'match_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _matchValueMeta =
      const VerificationMeta('matchValue');
  @override
  late final GeneratedColumn<String> matchValue = GeneratedColumn<String>(
      'match_value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _setCategoryIdMeta =
      const VerificationMeta('setCategoryId');
  @override
  late final GeneratedColumn<String> setCategoryId = GeneratedColumn<String>(
      'set_category_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES categories (id)'));
  static const VerificationMeta _setDescriptionMeta =
      const VerificationMeta('setDescription');
  @override
  late final GeneratedColumn<String> setDescription = GeneratedColumn<String>(
      'set_description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdFromTxnIdMeta =
      const VerificationMeta('createdFromTxnId');
  @override
  late final GeneratedColumn<String> createdFromTxnId = GeneratedColumn<String>(
      'created_from_txn_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES transactions (id)'));
  static const VerificationMeta _hitCountMeta =
      const VerificationMeta('hitCount');
  @override
  late final GeneratedColumn<int> hitCount = GeneratedColumn<int>(
      'hit_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        matchType,
        matchValue,
        setCategoryId,
        setDescription,
        createdFromTxnId,
        hitCount,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rules';
  @override
  VerificationContext validateIntegrity(Insertable<Rule> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('match_type')) {
      context.handle(_matchTypeMeta,
          matchType.isAcceptableOrUnknown(data['match_type']!, _matchTypeMeta));
    } else if (isInserting) {
      context.missing(_matchTypeMeta);
    }
    if (data.containsKey('match_value')) {
      context.handle(
          _matchValueMeta,
          matchValue.isAcceptableOrUnknown(
              data['match_value']!, _matchValueMeta));
    } else if (isInserting) {
      context.missing(_matchValueMeta);
    }
    if (data.containsKey('set_category_id')) {
      context.handle(
          _setCategoryIdMeta,
          setCategoryId.isAcceptableOrUnknown(
              data['set_category_id']!, _setCategoryIdMeta));
    }
    if (data.containsKey('set_description')) {
      context.handle(
          _setDescriptionMeta,
          setDescription.isAcceptableOrUnknown(
              data['set_description']!, _setDescriptionMeta));
    }
    if (data.containsKey('created_from_txn_id')) {
      context.handle(
          _createdFromTxnIdMeta,
          createdFromTxnId.isAcceptableOrUnknown(
              data['created_from_txn_id']!, _createdFromTxnIdMeta));
    }
    if (data.containsKey('hit_count')) {
      context.handle(_hitCountMeta,
          hitCount.isAcceptableOrUnknown(data['hit_count']!, _hitCountMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Rule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Rule(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      matchType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}match_type'])!,
      matchValue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}match_value'])!,
      setCategoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}set_category_id']),
      setDescription: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}set_description']),
      createdFromTxnId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}created_from_txn_id']),
      hitCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}hit_count'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $RulesTable createAlias(String alias) {
    return $RulesTable(attachedDatabase, alias);
  }
}

class Rule extends DataClass implements Insertable<Rule> {
  final String id;
  final String matchType;
  final String matchValue;
  final String? setCategoryId;
  final String? setDescription;
  final String? createdFromTxnId;
  final int hitCount;
  final DateTime createdAt;
  const Rule(
      {required this.id,
      required this.matchType,
      required this.matchValue,
      this.setCategoryId,
      this.setDescription,
      this.createdFromTxnId,
      required this.hitCount,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['match_type'] = Variable<String>(matchType);
    map['match_value'] = Variable<String>(matchValue);
    if (!nullToAbsent || setCategoryId != null) {
      map['set_category_id'] = Variable<String>(setCategoryId);
    }
    if (!nullToAbsent || setDescription != null) {
      map['set_description'] = Variable<String>(setDescription);
    }
    if (!nullToAbsent || createdFromTxnId != null) {
      map['created_from_txn_id'] = Variable<String>(createdFromTxnId);
    }
    map['hit_count'] = Variable<int>(hitCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RulesCompanion toCompanion(bool nullToAbsent) {
    return RulesCompanion(
      id: Value(id),
      matchType: Value(matchType),
      matchValue: Value(matchValue),
      setCategoryId: setCategoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(setCategoryId),
      setDescription: setDescription == null && nullToAbsent
          ? const Value.absent()
          : Value(setDescription),
      createdFromTxnId: createdFromTxnId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdFromTxnId),
      hitCount: Value(hitCount),
      createdAt: Value(createdAt),
    );
  }

  factory Rule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Rule(
      id: serializer.fromJson<String>(json['id']),
      matchType: serializer.fromJson<String>(json['matchType']),
      matchValue: serializer.fromJson<String>(json['matchValue']),
      setCategoryId: serializer.fromJson<String?>(json['setCategoryId']),
      setDescription: serializer.fromJson<String?>(json['setDescription']),
      createdFromTxnId: serializer.fromJson<String?>(json['createdFromTxnId']),
      hitCount: serializer.fromJson<int>(json['hitCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'matchType': serializer.toJson<String>(matchType),
      'matchValue': serializer.toJson<String>(matchValue),
      'setCategoryId': serializer.toJson<String?>(setCategoryId),
      'setDescription': serializer.toJson<String?>(setDescription),
      'createdFromTxnId': serializer.toJson<String?>(createdFromTxnId),
      'hitCount': serializer.toJson<int>(hitCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Rule copyWith(
          {String? id,
          String? matchType,
          String? matchValue,
          Value<String?> setCategoryId = const Value.absent(),
          Value<String?> setDescription = const Value.absent(),
          Value<String?> createdFromTxnId = const Value.absent(),
          int? hitCount,
          DateTime? createdAt}) =>
      Rule(
        id: id ?? this.id,
        matchType: matchType ?? this.matchType,
        matchValue: matchValue ?? this.matchValue,
        setCategoryId:
            setCategoryId.present ? setCategoryId.value : this.setCategoryId,
        setDescription:
            setDescription.present ? setDescription.value : this.setDescription,
        createdFromTxnId: createdFromTxnId.present
            ? createdFromTxnId.value
            : this.createdFromTxnId,
        hitCount: hitCount ?? this.hitCount,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('Rule(')
          ..write('id: $id, ')
          ..write('matchType: $matchType, ')
          ..write('matchValue: $matchValue, ')
          ..write('setCategoryId: $setCategoryId, ')
          ..write('setDescription: $setDescription, ')
          ..write('createdFromTxnId: $createdFromTxnId, ')
          ..write('hitCount: $hitCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, matchType, matchValue, setCategoryId,
      setDescription, createdFromTxnId, hitCount, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Rule &&
          other.id == this.id &&
          other.matchType == this.matchType &&
          other.matchValue == this.matchValue &&
          other.setCategoryId == this.setCategoryId &&
          other.setDescription == this.setDescription &&
          other.createdFromTxnId == this.createdFromTxnId &&
          other.hitCount == this.hitCount &&
          other.createdAt == this.createdAt);
}

class RulesCompanion extends UpdateCompanion<Rule> {
  final Value<String> id;
  final Value<String> matchType;
  final Value<String> matchValue;
  final Value<String?> setCategoryId;
  final Value<String?> setDescription;
  final Value<String?> createdFromTxnId;
  final Value<int> hitCount;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RulesCompanion({
    this.id = const Value.absent(),
    this.matchType = const Value.absent(),
    this.matchValue = const Value.absent(),
    this.setCategoryId = const Value.absent(),
    this.setDescription = const Value.absent(),
    this.createdFromTxnId = const Value.absent(),
    this.hitCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RulesCompanion.insert({
    required String id,
    required String matchType,
    required String matchValue,
    this.setCategoryId = const Value.absent(),
    this.setDescription = const Value.absent(),
    this.createdFromTxnId = const Value.absent(),
    this.hitCount = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        matchType = Value(matchType),
        matchValue = Value(matchValue),
        createdAt = Value(createdAt);
  static Insertable<Rule> custom({
    Expression<String>? id,
    Expression<String>? matchType,
    Expression<String>? matchValue,
    Expression<String>? setCategoryId,
    Expression<String>? setDescription,
    Expression<String>? createdFromTxnId,
    Expression<int>? hitCount,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (matchType != null) 'match_type': matchType,
      if (matchValue != null) 'match_value': matchValue,
      if (setCategoryId != null) 'set_category_id': setCategoryId,
      if (setDescription != null) 'set_description': setDescription,
      if (createdFromTxnId != null) 'created_from_txn_id': createdFromTxnId,
      if (hitCount != null) 'hit_count': hitCount,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RulesCompanion copyWith(
      {Value<String>? id,
      Value<String>? matchType,
      Value<String>? matchValue,
      Value<String?>? setCategoryId,
      Value<String?>? setDescription,
      Value<String?>? createdFromTxnId,
      Value<int>? hitCount,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return RulesCompanion(
      id: id ?? this.id,
      matchType: matchType ?? this.matchType,
      matchValue: matchValue ?? this.matchValue,
      setCategoryId: setCategoryId ?? this.setCategoryId,
      setDescription: setDescription ?? this.setDescription,
      createdFromTxnId: createdFromTxnId ?? this.createdFromTxnId,
      hitCount: hitCount ?? this.hitCount,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (matchType.present) {
      map['match_type'] = Variable<String>(matchType.value);
    }
    if (matchValue.present) {
      map['match_value'] = Variable<String>(matchValue.value);
    }
    if (setCategoryId.present) {
      map['set_category_id'] = Variable<String>(setCategoryId.value);
    }
    if (setDescription.present) {
      map['set_description'] = Variable<String>(setDescription.value);
    }
    if (createdFromTxnId.present) {
      map['created_from_txn_id'] = Variable<String>(createdFromTxnId.value);
    }
    if (hitCount.present) {
      map['hit_count'] = Variable<int>(hitCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RulesCompanion(')
          ..write('id: $id, ')
          ..write('matchType: $matchType, ')
          ..write('matchValue: $matchValue, ')
          ..write('setCategoryId: $setCategoryId, ')
          ..write('setDescription: $setDescription, ')
          ..write('createdFromTxnId: $createdFromTxnId, ')
          ..write('hitCount: $hitCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  _$AppDatabaseManager get managers => _$AppDatabaseManager(this);
  late final $BaselinesTable baselines = $BaselinesTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $MerchantsTable merchants = $MerchantsTable(this);
  late final $RawSmsTable rawSms = $RawSmsTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $FeedbackTable feedback = $FeedbackTable(this);
  late final $InsightsTable insights = $InsightsTable(this);
  late final $MerchantAliasesTable merchantAliases =
      $MerchantAliasesTable(this);
  late final $ModelMetaTable modelMeta = $ModelMetaTable(this);
  late final $RecurringSeriesTable recurringSeries =
      $RecurringSeriesTable(this);
  late final $RulesTable rules = $RulesTable(this);
  late final Index idxInsightsPeriod = Index('idx_insights_period',
      'CREATE INDEX idx_insights_period ON insights (period)');
  late final Index idxRecurringSeriesMerchantId = Index(
      'idx_recurring_series_merchant_id',
      'CREATE INDEX idx_recurring_series_merchant_id ON recurring_series (merchant_id)');
  late final Index idxRecurringSeriesNextExpectedDate = Index(
      'idx_recurring_series_next_expected_date',
      'CREATE INDEX idx_recurring_series_next_expected_date ON recurring_series (next_expected_date)');
  late final Index idxTransactionsTs = Index('idx_transactions_ts',
      'CREATE INDEX idx_transactions_ts ON transactions (ts)');
  late final Index idxTransactionsMerchantId = Index(
      'idx_transactions_merchant_id',
      'CREATE INDEX idx_transactions_merchant_id ON transactions (merchant_id)');
  late final Index idxTransactionsCategoryId = Index(
      'idx_transactions_category_id',
      'CREATE INDEX idx_transactions_category_id ON transactions (category_id)');
  late final Index idxTransactionsRefId = Index('idx_transactions_ref_id',
      'CREATE INDEX idx_transactions_ref_id ON transactions (ref_id)');
  late final Index idxTransactionsStatus = Index('idx_transactions_status',
      'CREATE INDEX idx_transactions_status ON transactions (status)');
  late final Index idxTransactionsDuplicateOfTxnId = Index(
      'idx_transactions_duplicate_of_txn_id',
      'CREATE INDEX idx_transactions_duplicate_of_txn_id ON transactions (duplicate_of_txn_id)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        baselines,
        categories,
        merchants,
        rawSms,
        transactions,
        feedback,
        insights,
        merchantAliases,
        modelMeta,
        recurringSeries,
        rules,
        idxInsightsPeriod,
        idxRecurringSeriesMerchantId,
        idxRecurringSeriesNextExpectedDate,
        idxTransactionsTs,
        idxTransactionsMerchantId,
        idxTransactionsCategoryId,
        idxTransactionsRefId,
        idxTransactionsStatus,
        idxTransactionsDuplicateOfTxnId
      ];
}

typedef $$BaselinesTableInsertCompanionBuilder = BaselinesCompanion Function({
  required String key,
  required double mean,
  required double std,
  required int n,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$BaselinesTableUpdateCompanionBuilder = BaselinesCompanion Function({
  Value<String> key,
  Value<double> mean,
  Value<double> std,
  Value<int> n,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$BaselinesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BaselinesTable,
    Baseline,
    $$BaselinesTableFilterComposer,
    $$BaselinesTableOrderingComposer,
    $$BaselinesTableProcessedTableManager,
    $$BaselinesTableInsertCompanionBuilder,
    $$BaselinesTableUpdateCompanionBuilder> {
  $$BaselinesTableTableManager(_$AppDatabase db, $BaselinesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$BaselinesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$BaselinesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$BaselinesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> key = const Value.absent(),
            Value<double> mean = const Value.absent(),
            Value<double> std = const Value.absent(),
            Value<int> n = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BaselinesCompanion(
            key: key,
            mean: mean,
            std: std,
            n: n,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String key,
            required double mean,
            required double std,
            required int n,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              BaselinesCompanion.insert(
            key: key,
            mean: mean,
            std: std,
            n: n,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$BaselinesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $BaselinesTable,
    Baseline,
    $$BaselinesTableFilterComposer,
    $$BaselinesTableOrderingComposer,
    $$BaselinesTableProcessedTableManager,
    $$BaselinesTableInsertCompanionBuilder,
    $$BaselinesTableUpdateCompanionBuilder> {
  $$BaselinesTableProcessedTableManager(super.$state);
}

class $$BaselinesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $BaselinesTable> {
  $$BaselinesTableFilterComposer(super.$state);
  ColumnFilters<String> get key => $state.composableBuilder(
      column: $state.table.key,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get mean => $state.composableBuilder(
      column: $state.table.mean,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get std => $state.composableBuilder(
      column: $state.table.std,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get n => $state.composableBuilder(
      column: $state.table.n,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$BaselinesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $BaselinesTable> {
  $$BaselinesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get key => $state.composableBuilder(
      column: $state.table.key,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get mean => $state.composableBuilder(
      column: $state.table.mean,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get std => $state.composableBuilder(
      column: $state.table.std,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get n => $state.composableBuilder(
      column: $state.table.n,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$CategoriesTableInsertCompanionBuilder = CategoriesCompanion Function({
  required String id,
  required String name,
  Value<String?> parentId,
  required String icon,
  required bool isSpending,
  required int sortOrder,
  required bool isUserCreated,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> parentId,
  Value<String> icon,
  Value<bool> isSpending,
  Value<int> sortOrder,
  Value<bool> isUserCreated,
  Value<int> rowid,
});

class $$CategoriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableProcessedTableManager,
    $$CategoriesTableInsertCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder> {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$CategoriesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$CategoriesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$CategoriesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String> icon = const Value.absent(),
            Value<bool> isSpending = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<bool> isUserCreated = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoriesCompanion(
            id: id,
            name: name,
            parentId: parentId,
            icon: icon,
            isSpending: isSpending,
            sortOrder: sortOrder,
            isUserCreated: isUserCreated,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String name,
            Value<String?> parentId = const Value.absent(),
            required String icon,
            required bool isSpending,
            required int sortOrder,
            required bool isUserCreated,
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoriesCompanion.insert(
            id: id,
            name: name,
            parentId: parentId,
            icon: icon,
            isSpending: isSpending,
            sortOrder: sortOrder,
            isUserCreated: isUserCreated,
            rowid: rowid,
          ),
        ));
}

class $$CategoriesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableProcessedTableManager,
    $$CategoriesTableInsertCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder> {
  $$CategoriesTableProcessedTableManager(super.$state);
}

class $$CategoriesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get icon => $state.composableBuilder(
      column: $state.table.icon,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isSpending => $state.composableBuilder(
      column: $state.table.isSpending,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get sortOrder => $state.composableBuilder(
      column: $state.table.sortOrder,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isUserCreated => $state.composableBuilder(
      column: $state.table.isUserCreated,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$CategoriesTableFilterComposer get parentId {
    final $$CategoriesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $state.db.categories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$CategoriesTableFilterComposer(ComposerState($state.db,
                $state.db.categories, joinBuilder, parentComposers)));
    return composer;
  }

  ComposableFilter transactionsRefs(
      ComposableFilter Function($$TransactionsTableFilterComposer f) f) {
    final $$TransactionsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.categoryId,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableFilterComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter rulesRefs(
      ComposableFilter Function($$RulesTableFilterComposer f) f) {
    final $$RulesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.rules,
        getReferencedColumn: (t) => t.setCategoryId,
        builder: (joinBuilder, parentComposers) => $$RulesTableFilterComposer(
            ComposerState(
                $state.db, $state.db.rules, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get icon => $state.composableBuilder(
      column: $state.table.icon,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isSpending => $state.composableBuilder(
      column: $state.table.isSpending,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get sortOrder => $state.composableBuilder(
      column: $state.table.sortOrder,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isUserCreated => $state.composableBuilder(
      column: $state.table.isUserCreated,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$CategoriesTableOrderingComposer get parentId {
    final $$CategoriesTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $state.db.categories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$CategoriesTableOrderingComposer(ComposerState($state.db,
                $state.db.categories, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$MerchantsTableInsertCompanionBuilder = MerchantsCompanion Function({
  required String id,
  required String canonicalName,
  Value<String?> categoryHint,
  Value<Uint8List?> embedding,
  Value<int> txnCount,
  required DateTime firstSeen,
  required DateTime lastSeen,
  Value<int> rowid,
});
typedef $$MerchantsTableUpdateCompanionBuilder = MerchantsCompanion Function({
  Value<String> id,
  Value<String> canonicalName,
  Value<String?> categoryHint,
  Value<Uint8List?> embedding,
  Value<int> txnCount,
  Value<DateTime> firstSeen,
  Value<DateTime> lastSeen,
  Value<int> rowid,
});

class $$MerchantsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MerchantsTable,
    Merchant,
    $$MerchantsTableFilterComposer,
    $$MerchantsTableOrderingComposer,
    $$MerchantsTableProcessedTableManager,
    $$MerchantsTableInsertCompanionBuilder,
    $$MerchantsTableUpdateCompanionBuilder> {
  $$MerchantsTableTableManager(_$AppDatabase db, $MerchantsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$MerchantsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$MerchantsTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$MerchantsTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> canonicalName = const Value.absent(),
            Value<String?> categoryHint = const Value.absent(),
            Value<Uint8List?> embedding = const Value.absent(),
            Value<int> txnCount = const Value.absent(),
            Value<DateTime> firstSeen = const Value.absent(),
            Value<DateTime> lastSeen = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MerchantsCompanion(
            id: id,
            canonicalName: canonicalName,
            categoryHint: categoryHint,
            embedding: embedding,
            txnCount: txnCount,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String canonicalName,
            Value<String?> categoryHint = const Value.absent(),
            Value<Uint8List?> embedding = const Value.absent(),
            Value<int> txnCount = const Value.absent(),
            required DateTime firstSeen,
            required DateTime lastSeen,
            Value<int> rowid = const Value.absent(),
          }) =>
              MerchantsCompanion.insert(
            id: id,
            canonicalName: canonicalName,
            categoryHint: categoryHint,
            embedding: embedding,
            txnCount: txnCount,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            rowid: rowid,
          ),
        ));
}

class $$MerchantsTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $MerchantsTable,
    Merchant,
    $$MerchantsTableFilterComposer,
    $$MerchantsTableOrderingComposer,
    $$MerchantsTableProcessedTableManager,
    $$MerchantsTableInsertCompanionBuilder,
    $$MerchantsTableUpdateCompanionBuilder> {
  $$MerchantsTableProcessedTableManager(super.$state);
}

class $$MerchantsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $MerchantsTable> {
  $$MerchantsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get canonicalName => $state.composableBuilder(
      column: $state.table.canonicalName,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get categoryHint => $state.composableBuilder(
      column: $state.table.categoryHint,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<Uint8List> get embedding => $state.composableBuilder(
      column: $state.table.embedding,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get txnCount => $state.composableBuilder(
      column: $state.table.txnCount,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get firstSeen => $state.composableBuilder(
      column: $state.table.firstSeen,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get lastSeen => $state.composableBuilder(
      column: $state.table.lastSeen,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ComposableFilter transactionsRefs(
      ComposableFilter Function($$TransactionsTableFilterComposer f) f) {
    final $$TransactionsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.merchantId,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableFilterComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter merchantAliasesRefs(
      ComposableFilter Function($$MerchantAliasesTableFilterComposer f) f) {
    final $$MerchantAliasesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.merchantAliases,
            getReferencedColumn: (t) => t.merchantId,
            builder: (joinBuilder, parentComposers) =>
                $$MerchantAliasesTableFilterComposer(ComposerState($state.db,
                    $state.db.merchantAliases, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter recurringSeriesRefs(
      ComposableFilter Function($$RecurringSeriesTableFilterComposer f) f) {
    final $$RecurringSeriesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.recurringSeries,
            getReferencedColumn: (t) => t.merchantId,
            builder: (joinBuilder, parentComposers) =>
                $$RecurringSeriesTableFilterComposer(ComposerState($state.db,
                    $state.db.recurringSeries, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$MerchantsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $MerchantsTable> {
  $$MerchantsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get canonicalName => $state.composableBuilder(
      column: $state.table.canonicalName,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get categoryHint => $state.composableBuilder(
      column: $state.table.categoryHint,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<Uint8List> get embedding => $state.composableBuilder(
      column: $state.table.embedding,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get txnCount => $state.composableBuilder(
      column: $state.table.txnCount,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get firstSeen => $state.composableBuilder(
      column: $state.table.firstSeen,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get lastSeen => $state.composableBuilder(
      column: $state.table.lastSeen,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$RawSmsTableInsertCompanionBuilder = RawSmsCompanion Function({
  required String id,
  required String sender,
  required String body,
  required DateTime receivedAt,
  Value<bool> processed,
  required DateTime purgeAfter,
  Value<int> rowid,
});
typedef $$RawSmsTableUpdateCompanionBuilder = RawSmsCompanion Function({
  Value<String> id,
  Value<String> sender,
  Value<String> body,
  Value<DateTime> receivedAt,
  Value<bool> processed,
  Value<DateTime> purgeAfter,
  Value<int> rowid,
});

class $$RawSmsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RawSmsTable,
    RawSm,
    $$RawSmsTableFilterComposer,
    $$RawSmsTableOrderingComposer,
    $$RawSmsTableProcessedTableManager,
    $$RawSmsTableInsertCompanionBuilder,
    $$RawSmsTableUpdateCompanionBuilder> {
  $$RawSmsTableTableManager(_$AppDatabase db, $RawSmsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$RawSmsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$RawSmsTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) => $$RawSmsTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> sender = const Value.absent(),
            Value<String> body = const Value.absent(),
            Value<DateTime> receivedAt = const Value.absent(),
            Value<bool> processed = const Value.absent(),
            Value<DateTime> purgeAfter = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RawSmsCompanion(
            id: id,
            sender: sender,
            body: body,
            receivedAt: receivedAt,
            processed: processed,
            purgeAfter: purgeAfter,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String sender,
            required String body,
            required DateTime receivedAt,
            Value<bool> processed = const Value.absent(),
            required DateTime purgeAfter,
            Value<int> rowid = const Value.absent(),
          }) =>
              RawSmsCompanion.insert(
            id: id,
            sender: sender,
            body: body,
            receivedAt: receivedAt,
            processed: processed,
            purgeAfter: purgeAfter,
            rowid: rowid,
          ),
        ));
}

class $$RawSmsTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $RawSmsTable,
    RawSm,
    $$RawSmsTableFilterComposer,
    $$RawSmsTableOrderingComposer,
    $$RawSmsTableProcessedTableManager,
    $$RawSmsTableInsertCompanionBuilder,
    $$RawSmsTableUpdateCompanionBuilder> {
  $$RawSmsTableProcessedTableManager(super.$state);
}

class $$RawSmsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $RawSmsTable> {
  $$RawSmsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get sender => $state.composableBuilder(
      column: $state.table.sender,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get body => $state.composableBuilder(
      column: $state.table.body,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get receivedAt => $state.composableBuilder(
      column: $state.table.receivedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get processed => $state.composableBuilder(
      column: $state.table.processed,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get purgeAfter => $state.composableBuilder(
      column: $state.table.purgeAfter,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ComposableFilter transactionsRefs(
      ComposableFilter Function($$TransactionsTableFilterComposer f) f) {
    final $$TransactionsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.smsId,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableFilterComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$RawSmsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $RawSmsTable> {
  $$RawSmsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get sender => $state.composableBuilder(
      column: $state.table.sender,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get body => $state.composableBuilder(
      column: $state.table.body,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get receivedAt => $state.composableBuilder(
      column: $state.table.receivedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get processed => $state.composableBuilder(
      column: $state.table.processed,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get purgeAfter => $state.composableBuilder(
      column: $state.table.purgeAfter,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$TransactionsTableInsertCompanionBuilder = TransactionsCompanion
    Function({
  required String id,
  required int ts,
  required double amount,
  required String direction,
  required String channel,
  Value<String?> accountHint,
  Value<String?> merchantRaw,
  Value<String?> merchantId,
  Value<String?> categoryId,
  Value<String?> description,
  Value<double?> balanceAfter,
  Value<String?> refId,
  required String parseSource,
  Value<String?> smsId,
  required String confidenceJson,
  required String status,
  Value<bool> isDeleted,
  Value<String?> counterpartyVpa,
  Value<String?> duplicateOfTxnId,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$TransactionsTableUpdateCompanionBuilder = TransactionsCompanion
    Function({
  Value<String> id,
  Value<int> ts,
  Value<double> amount,
  Value<String> direction,
  Value<String> channel,
  Value<String?> accountHint,
  Value<String?> merchantRaw,
  Value<String?> merchantId,
  Value<String?> categoryId,
  Value<String?> description,
  Value<double?> balanceAfter,
  Value<String?> refId,
  Value<String> parseSource,
  Value<String?> smsId,
  Value<String> confidenceJson,
  Value<String> status,
  Value<bool> isDeleted,
  Value<String?> counterpartyVpa,
  Value<String?> duplicateOfTxnId,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$TransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableProcessedTableManager,
    $$TransactionsTableInsertCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder> {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$TransactionsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$TransactionsTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$TransactionsTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<int> ts = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<String> channel = const Value.absent(),
            Value<String?> accountHint = const Value.absent(),
            Value<String?> merchantRaw = const Value.absent(),
            Value<String?> merchantId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<double?> balanceAfter = const Value.absent(),
            Value<String?> refId = const Value.absent(),
            Value<String> parseSource = const Value.absent(),
            Value<String?> smsId = const Value.absent(),
            Value<String> confidenceJson = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<String?> counterpartyVpa = const Value.absent(),
            Value<String?> duplicateOfTxnId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionsCompanion(
            id: id,
            ts: ts,
            amount: amount,
            direction: direction,
            channel: channel,
            accountHint: accountHint,
            merchantRaw: merchantRaw,
            merchantId: merchantId,
            categoryId: categoryId,
            description: description,
            balanceAfter: balanceAfter,
            refId: refId,
            parseSource: parseSource,
            smsId: smsId,
            confidenceJson: confidenceJson,
            status: status,
            isDeleted: isDeleted,
            counterpartyVpa: counterpartyVpa,
            duplicateOfTxnId: duplicateOfTxnId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required int ts,
            required double amount,
            required String direction,
            required String channel,
            Value<String?> accountHint = const Value.absent(),
            Value<String?> merchantRaw = const Value.absent(),
            Value<String?> merchantId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<double?> balanceAfter = const Value.absent(),
            Value<String?> refId = const Value.absent(),
            required String parseSource,
            Value<String?> smsId = const Value.absent(),
            required String confidenceJson,
            required String status,
            Value<bool> isDeleted = const Value.absent(),
            Value<String?> counterpartyVpa = const Value.absent(),
            Value<String?> duplicateOfTxnId = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TransactionsCompanion.insert(
            id: id,
            ts: ts,
            amount: amount,
            direction: direction,
            channel: channel,
            accountHint: accountHint,
            merchantRaw: merchantRaw,
            merchantId: merchantId,
            categoryId: categoryId,
            description: description,
            balanceAfter: balanceAfter,
            refId: refId,
            parseSource: parseSource,
            smsId: smsId,
            confidenceJson: confidenceJson,
            status: status,
            isDeleted: isDeleted,
            counterpartyVpa: counterpartyVpa,
            duplicateOfTxnId: duplicateOfTxnId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$TransactionsTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $TransactionsTable,
    Transaction,
    $$TransactionsTableFilterComposer,
    $$TransactionsTableOrderingComposer,
    $$TransactionsTableProcessedTableManager,
    $$TransactionsTableInsertCompanionBuilder,
    $$TransactionsTableUpdateCompanionBuilder> {
  $$TransactionsTableProcessedTableManager(super.$state);
}

class $$TransactionsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get ts => $state.composableBuilder(
      column: $state.table.ts,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get amount => $state.composableBuilder(
      column: $state.table.amount,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get direction => $state.composableBuilder(
      column: $state.table.direction,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get channel => $state.composableBuilder(
      column: $state.table.channel,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get accountHint => $state.composableBuilder(
      column: $state.table.accountHint,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get merchantRaw => $state.composableBuilder(
      column: $state.table.merchantRaw,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get balanceAfter => $state.composableBuilder(
      column: $state.table.balanceAfter,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get refId => $state.composableBuilder(
      column: $state.table.refId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get parseSource => $state.composableBuilder(
      column: $state.table.parseSource,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get confidenceJson => $state.composableBuilder(
      column: $state.table.confidenceJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isDeleted => $state.composableBuilder(
      column: $state.table.isDeleted,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get counterpartyVpa => $state.composableBuilder(
      column: $state.table.counterpartyVpa,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$MerchantsTableFilterComposer get merchantId {
    final $$MerchantsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.merchantId,
        referencedTable: $state.db.merchants,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MerchantsTableFilterComposer(ComposerState(
                $state.db, $state.db.merchants, joinBuilder, parentComposers)));
    return composer;
  }

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.categoryId,
        referencedTable: $state.db.categories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$CategoriesTableFilterComposer(ComposerState($state.db,
                $state.db.categories, joinBuilder, parentComposers)));
    return composer;
  }

  $$RawSmsTableFilterComposer get smsId {
    final $$RawSmsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.smsId,
        referencedTable: $state.db.rawSms,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) => $$RawSmsTableFilterComposer(
            ComposerState(
                $state.db, $state.db.rawSms, joinBuilder, parentComposers)));
    return composer;
  }

  $$TransactionsTableFilterComposer get duplicateOfTxnId {
    final $$TransactionsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.duplicateOfTxnId,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableFilterComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return composer;
  }

  ComposableFilter feedbackRefs(
      ComposableFilter Function($$FeedbackTableFilterComposer f) f) {
    final $$FeedbackTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.feedback,
        getReferencedColumn: (t) => t.txnId,
        builder: (joinBuilder, parentComposers) =>
            $$FeedbackTableFilterComposer(ComposerState(
                $state.db, $state.db.feedback, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter rulesRefs(
      ComposableFilter Function($$RulesTableFilterComposer f) f) {
    final $$RulesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.rules,
        getReferencedColumn: (t) => t.createdFromTxnId,
        builder: (joinBuilder, parentComposers) => $$RulesTableFilterComposer(
            ComposerState(
                $state.db, $state.db.rules, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$TransactionsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get ts => $state.composableBuilder(
      column: $state.table.ts,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get amount => $state.composableBuilder(
      column: $state.table.amount,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get direction => $state.composableBuilder(
      column: $state.table.direction,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get channel => $state.composableBuilder(
      column: $state.table.channel,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get accountHint => $state.composableBuilder(
      column: $state.table.accountHint,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get merchantRaw => $state.composableBuilder(
      column: $state.table.merchantRaw,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get balanceAfter => $state.composableBuilder(
      column: $state.table.balanceAfter,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get refId => $state.composableBuilder(
      column: $state.table.refId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get parseSource => $state.composableBuilder(
      column: $state.table.parseSource,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get confidenceJson => $state.composableBuilder(
      column: $state.table.confidenceJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isDeleted => $state.composableBuilder(
      column: $state.table.isDeleted,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get counterpartyVpa => $state.composableBuilder(
      column: $state.table.counterpartyVpa,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$MerchantsTableOrderingComposer get merchantId {
    final $$MerchantsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.merchantId,
        referencedTable: $state.db.merchants,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MerchantsTableOrderingComposer(ComposerState(
                $state.db, $state.db.merchants, joinBuilder, parentComposers)));
    return composer;
  }

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.categoryId,
        referencedTable: $state.db.categories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$CategoriesTableOrderingComposer(ComposerState($state.db,
                $state.db.categories, joinBuilder, parentComposers)));
    return composer;
  }

  $$RawSmsTableOrderingComposer get smsId {
    final $$RawSmsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.smsId,
        referencedTable: $state.db.rawSms,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$RawSmsTableOrderingComposer(ComposerState(
                $state.db, $state.db.rawSms, joinBuilder, parentComposers)));
    return composer;
  }

  $$TransactionsTableOrderingComposer get duplicateOfTxnId {
    final $$TransactionsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.duplicateOfTxnId,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableOrderingComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$FeedbackTableInsertCompanionBuilder = FeedbackCompanion Function({
  required String id,
  required String txnId,
  required String field,
  Value<String?> oldValue,
  Value<String?> newValue,
  required String context,
  Value<double?> modelConfidenceAtTime,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$FeedbackTableUpdateCompanionBuilder = FeedbackCompanion Function({
  Value<String> id,
  Value<String> txnId,
  Value<String> field,
  Value<String?> oldValue,
  Value<String?> newValue,
  Value<String> context,
  Value<double?> modelConfidenceAtTime,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$FeedbackTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FeedbackTable,
    FeedbackData,
    $$FeedbackTableFilterComposer,
    $$FeedbackTableOrderingComposer,
    $$FeedbackTableProcessedTableManager,
    $$FeedbackTableInsertCompanionBuilder,
    $$FeedbackTableUpdateCompanionBuilder> {
  $$FeedbackTableTableManager(_$AppDatabase db, $FeedbackTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$FeedbackTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$FeedbackTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$FeedbackTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> txnId = const Value.absent(),
            Value<String> field = const Value.absent(),
            Value<String?> oldValue = const Value.absent(),
            Value<String?> newValue = const Value.absent(),
            Value<String> context = const Value.absent(),
            Value<double?> modelConfidenceAtTime = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FeedbackCompanion(
            id: id,
            txnId: txnId,
            field: field,
            oldValue: oldValue,
            newValue: newValue,
            context: context,
            modelConfidenceAtTime: modelConfidenceAtTime,
            createdAt: createdAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String txnId,
            required String field,
            Value<String?> oldValue = const Value.absent(),
            Value<String?> newValue = const Value.absent(),
            required String context,
            Value<double?> modelConfidenceAtTime = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FeedbackCompanion.insert(
            id: id,
            txnId: txnId,
            field: field,
            oldValue: oldValue,
            newValue: newValue,
            context: context,
            modelConfidenceAtTime: modelConfidenceAtTime,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$FeedbackTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $FeedbackTable,
    FeedbackData,
    $$FeedbackTableFilterComposer,
    $$FeedbackTableOrderingComposer,
    $$FeedbackTableProcessedTableManager,
    $$FeedbackTableInsertCompanionBuilder,
    $$FeedbackTableUpdateCompanionBuilder> {
  $$FeedbackTableProcessedTableManager(super.$state);
}

class $$FeedbackTableFilterComposer
    extends FilterComposer<_$AppDatabase, $FeedbackTable> {
  $$FeedbackTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get field => $state.composableBuilder(
      column: $state.table.field,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get oldValue => $state.composableBuilder(
      column: $state.table.oldValue,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get newValue => $state.composableBuilder(
      column: $state.table.newValue,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get context => $state.composableBuilder(
      column: $state.table.context,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get modelConfidenceAtTime => $state.composableBuilder(
      column: $state.table.modelConfidenceAtTime,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$TransactionsTableFilterComposer get txnId {
    final $$TransactionsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.txnId,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableFilterComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$FeedbackTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $FeedbackTable> {
  $$FeedbackTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get field => $state.composableBuilder(
      column: $state.table.field,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get oldValue => $state.composableBuilder(
      column: $state.table.oldValue,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get newValue => $state.composableBuilder(
      column: $state.table.newValue,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get context => $state.composableBuilder(
      column: $state.table.context,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get modelConfidenceAtTime => $state.composableBuilder(
      column: $state.table.modelConfidenceAtTime,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$TransactionsTableOrderingComposer get txnId {
    final $$TransactionsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.txnId,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableOrderingComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$InsightsTableInsertCompanionBuilder = InsightsCompanion Function({
  required String id,
  required String period,
  required String kind,
  required String payloadJson,
  Value<bool> dismissed,
  Value<int> rowid,
});
typedef $$InsightsTableUpdateCompanionBuilder = InsightsCompanion Function({
  Value<String> id,
  Value<String> period,
  Value<String> kind,
  Value<String> payloadJson,
  Value<bool> dismissed,
  Value<int> rowid,
});

class $$InsightsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $InsightsTable,
    Insight,
    $$InsightsTableFilterComposer,
    $$InsightsTableOrderingComposer,
    $$InsightsTableProcessedTableManager,
    $$InsightsTableInsertCompanionBuilder,
    $$InsightsTableUpdateCompanionBuilder> {
  $$InsightsTableTableManager(_$AppDatabase db, $InsightsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$InsightsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$InsightsTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$InsightsTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> period = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<bool> dismissed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              InsightsCompanion(
            id: id,
            period: period,
            kind: kind,
            payloadJson: payloadJson,
            dismissed: dismissed,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String period,
            required String kind,
            required String payloadJson,
            Value<bool> dismissed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              InsightsCompanion.insert(
            id: id,
            period: period,
            kind: kind,
            payloadJson: payloadJson,
            dismissed: dismissed,
            rowid: rowid,
          ),
        ));
}

class $$InsightsTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $InsightsTable,
    Insight,
    $$InsightsTableFilterComposer,
    $$InsightsTableOrderingComposer,
    $$InsightsTableProcessedTableManager,
    $$InsightsTableInsertCompanionBuilder,
    $$InsightsTableUpdateCompanionBuilder> {
  $$InsightsTableProcessedTableManager(super.$state);
}

class $$InsightsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $InsightsTable> {
  $$InsightsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get period => $state.composableBuilder(
      column: $state.table.period,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get kind => $state.composableBuilder(
      column: $state.table.kind,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get payloadJson => $state.composableBuilder(
      column: $state.table.payloadJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get dismissed => $state.composableBuilder(
      column: $state.table.dismissed,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$InsightsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $InsightsTable> {
  $$InsightsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get period => $state.composableBuilder(
      column: $state.table.period,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get kind => $state.composableBuilder(
      column: $state.table.kind,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get payloadJson => $state.composableBuilder(
      column: $state.table.payloadJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get dismissed => $state.composableBuilder(
      column: $state.table.dismissed,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$MerchantAliasesTableInsertCompanionBuilder = MerchantAliasesCompanion
    Function({
  required String alias,
  required String merchantId,
  required String source,
  required double confidence,
  Value<int> rowid,
});
typedef $$MerchantAliasesTableUpdateCompanionBuilder = MerchantAliasesCompanion
    Function({
  Value<String> alias,
  Value<String> merchantId,
  Value<String> source,
  Value<double> confidence,
  Value<int> rowid,
});

class $$MerchantAliasesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MerchantAliasesTable,
    MerchantAliase,
    $$MerchantAliasesTableFilterComposer,
    $$MerchantAliasesTableOrderingComposer,
    $$MerchantAliasesTableProcessedTableManager,
    $$MerchantAliasesTableInsertCompanionBuilder,
    $$MerchantAliasesTableUpdateCompanionBuilder> {
  $$MerchantAliasesTableTableManager(
      _$AppDatabase db, $MerchantAliasesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$MerchantAliasesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$MerchantAliasesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$MerchantAliasesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> alias = const Value.absent(),
            Value<String> merchantId = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<double> confidence = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MerchantAliasesCompanion(
            alias: alias,
            merchantId: merchantId,
            source: source,
            confidence: confidence,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String alias,
            required String merchantId,
            required String source,
            required double confidence,
            Value<int> rowid = const Value.absent(),
          }) =>
              MerchantAliasesCompanion.insert(
            alias: alias,
            merchantId: merchantId,
            source: source,
            confidence: confidence,
            rowid: rowid,
          ),
        ));
}

class $$MerchantAliasesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $MerchantAliasesTable,
    MerchantAliase,
    $$MerchantAliasesTableFilterComposer,
    $$MerchantAliasesTableOrderingComposer,
    $$MerchantAliasesTableProcessedTableManager,
    $$MerchantAliasesTableInsertCompanionBuilder,
    $$MerchantAliasesTableUpdateCompanionBuilder> {
  $$MerchantAliasesTableProcessedTableManager(super.$state);
}

class $$MerchantAliasesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $MerchantAliasesTable> {
  $$MerchantAliasesTableFilterComposer(super.$state);
  ColumnFilters<String> get alias => $state.composableBuilder(
      column: $state.table.alias,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get source => $state.composableBuilder(
      column: $state.table.source,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get confidence => $state.composableBuilder(
      column: $state.table.confidence,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$MerchantsTableFilterComposer get merchantId {
    final $$MerchantsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.merchantId,
        referencedTable: $state.db.merchants,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MerchantsTableFilterComposer(ComposerState(
                $state.db, $state.db.merchants, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$MerchantAliasesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $MerchantAliasesTable> {
  $$MerchantAliasesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get alias => $state.composableBuilder(
      column: $state.table.alias,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get source => $state.composableBuilder(
      column: $state.table.source,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get confidence => $state.composableBuilder(
      column: $state.table.confidence,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$MerchantsTableOrderingComposer get merchantId {
    final $$MerchantsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.merchantId,
        referencedTable: $state.db.merchants,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MerchantsTableOrderingComposer(ComposerState(
                $state.db, $state.db.merchants, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$ModelMetaTableInsertCompanionBuilder = ModelMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$ModelMetaTableUpdateCompanionBuilder = ModelMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$ModelMetaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ModelMetaTable,
    ModelMetaData,
    $$ModelMetaTableFilterComposer,
    $$ModelMetaTableOrderingComposer,
    $$ModelMetaTableProcessedTableManager,
    $$ModelMetaTableInsertCompanionBuilder,
    $$ModelMetaTableUpdateCompanionBuilder> {
  $$ModelMetaTableTableManager(_$AppDatabase db, $ModelMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$ModelMetaTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$ModelMetaTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$ModelMetaTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ModelMetaCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              ModelMetaCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
        ));
}

class $$ModelMetaTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $ModelMetaTable,
    ModelMetaData,
    $$ModelMetaTableFilterComposer,
    $$ModelMetaTableOrderingComposer,
    $$ModelMetaTableProcessedTableManager,
    $$ModelMetaTableInsertCompanionBuilder,
    $$ModelMetaTableUpdateCompanionBuilder> {
  $$ModelMetaTableProcessedTableManager(super.$state);
}

class $$ModelMetaTableFilterComposer
    extends FilterComposer<_$AppDatabase, $ModelMetaTable> {
  $$ModelMetaTableFilterComposer(super.$state);
  ColumnFilters<String> get key => $state.composableBuilder(
      column: $state.table.key,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get value => $state.composableBuilder(
      column: $state.table.value,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$ModelMetaTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $ModelMetaTable> {
  $$ModelMetaTableOrderingComposer(super.$state);
  ColumnOrderings<String> get key => $state.composableBuilder(
      column: $state.table.key,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get value => $state.composableBuilder(
      column: $state.table.value,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$RecurringSeriesTableInsertCompanionBuilder = RecurringSeriesCompanion
    Function({
  required String id,
  required String merchantId,
  required String label,
  required double expectedAmount,
  required double tolerancePct,
  required String period,
  required int periodDays,
  required DateTime nextExpectedDate,
  required double lastAmount,
  required String amountTrend,
  required int occurrences,
  required String status,
  required String kind,
  Value<int> rowid,
});
typedef $$RecurringSeriesTableUpdateCompanionBuilder = RecurringSeriesCompanion
    Function({
  Value<String> id,
  Value<String> merchantId,
  Value<String> label,
  Value<double> expectedAmount,
  Value<double> tolerancePct,
  Value<String> period,
  Value<int> periodDays,
  Value<DateTime> nextExpectedDate,
  Value<double> lastAmount,
  Value<String> amountTrend,
  Value<int> occurrences,
  Value<String> status,
  Value<String> kind,
  Value<int> rowid,
});

class $$RecurringSeriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RecurringSeriesTable,
    RecurringSery,
    $$RecurringSeriesTableFilterComposer,
    $$RecurringSeriesTableOrderingComposer,
    $$RecurringSeriesTableProcessedTableManager,
    $$RecurringSeriesTableInsertCompanionBuilder,
    $$RecurringSeriesTableUpdateCompanionBuilder> {
  $$RecurringSeriesTableTableManager(
      _$AppDatabase db, $RecurringSeriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$RecurringSeriesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$RecurringSeriesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$RecurringSeriesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> merchantId = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<double> expectedAmount = const Value.absent(),
            Value<double> tolerancePct = const Value.absent(),
            Value<String> period = const Value.absent(),
            Value<int> periodDays = const Value.absent(),
            Value<DateTime> nextExpectedDate = const Value.absent(),
            Value<double> lastAmount = const Value.absent(),
            Value<String> amountTrend = const Value.absent(),
            Value<int> occurrences = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecurringSeriesCompanion(
            id: id,
            merchantId: merchantId,
            label: label,
            expectedAmount: expectedAmount,
            tolerancePct: tolerancePct,
            period: period,
            periodDays: periodDays,
            nextExpectedDate: nextExpectedDate,
            lastAmount: lastAmount,
            amountTrend: amountTrend,
            occurrences: occurrences,
            status: status,
            kind: kind,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String merchantId,
            required String label,
            required double expectedAmount,
            required double tolerancePct,
            required String period,
            required int periodDays,
            required DateTime nextExpectedDate,
            required double lastAmount,
            required String amountTrend,
            required int occurrences,
            required String status,
            required String kind,
            Value<int> rowid = const Value.absent(),
          }) =>
              RecurringSeriesCompanion.insert(
            id: id,
            merchantId: merchantId,
            label: label,
            expectedAmount: expectedAmount,
            tolerancePct: tolerancePct,
            period: period,
            periodDays: periodDays,
            nextExpectedDate: nextExpectedDate,
            lastAmount: lastAmount,
            amountTrend: amountTrend,
            occurrences: occurrences,
            status: status,
            kind: kind,
            rowid: rowid,
          ),
        ));
}

class $$RecurringSeriesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $RecurringSeriesTable,
    RecurringSery,
    $$RecurringSeriesTableFilterComposer,
    $$RecurringSeriesTableOrderingComposer,
    $$RecurringSeriesTableProcessedTableManager,
    $$RecurringSeriesTableInsertCompanionBuilder,
    $$RecurringSeriesTableUpdateCompanionBuilder> {
  $$RecurringSeriesTableProcessedTableManager(super.$state);
}

class $$RecurringSeriesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $RecurringSeriesTable> {
  $$RecurringSeriesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get label => $state.composableBuilder(
      column: $state.table.label,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get expectedAmount => $state.composableBuilder(
      column: $state.table.expectedAmount,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get tolerancePct => $state.composableBuilder(
      column: $state.table.tolerancePct,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get period => $state.composableBuilder(
      column: $state.table.period,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get periodDays => $state.composableBuilder(
      column: $state.table.periodDays,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get nextExpectedDate => $state.composableBuilder(
      column: $state.table.nextExpectedDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get lastAmount => $state.composableBuilder(
      column: $state.table.lastAmount,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get amountTrend => $state.composableBuilder(
      column: $state.table.amountTrend,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get occurrences => $state.composableBuilder(
      column: $state.table.occurrences,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get kind => $state.composableBuilder(
      column: $state.table.kind,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$MerchantsTableFilterComposer get merchantId {
    final $$MerchantsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.merchantId,
        referencedTable: $state.db.merchants,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MerchantsTableFilterComposer(ComposerState(
                $state.db, $state.db.merchants, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$RecurringSeriesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $RecurringSeriesTable> {
  $$RecurringSeriesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get label => $state.composableBuilder(
      column: $state.table.label,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get expectedAmount => $state.composableBuilder(
      column: $state.table.expectedAmount,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get tolerancePct => $state.composableBuilder(
      column: $state.table.tolerancePct,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get period => $state.composableBuilder(
      column: $state.table.period,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get periodDays => $state.composableBuilder(
      column: $state.table.periodDays,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get nextExpectedDate => $state.composableBuilder(
      column: $state.table.nextExpectedDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get lastAmount => $state.composableBuilder(
      column: $state.table.lastAmount,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get amountTrend => $state.composableBuilder(
      column: $state.table.amountTrend,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get occurrences => $state.composableBuilder(
      column: $state.table.occurrences,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get kind => $state.composableBuilder(
      column: $state.table.kind,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$MerchantsTableOrderingComposer get merchantId {
    final $$MerchantsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.merchantId,
        referencedTable: $state.db.merchants,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MerchantsTableOrderingComposer(ComposerState(
                $state.db, $state.db.merchants, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$RulesTableInsertCompanionBuilder = RulesCompanion Function({
  required String id,
  required String matchType,
  required String matchValue,
  Value<String?> setCategoryId,
  Value<String?> setDescription,
  Value<String?> createdFromTxnId,
  Value<int> hitCount,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$RulesTableUpdateCompanionBuilder = RulesCompanion Function({
  Value<String> id,
  Value<String> matchType,
  Value<String> matchValue,
  Value<String?> setCategoryId,
  Value<String?> setDescription,
  Value<String?> createdFromTxnId,
  Value<int> hitCount,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$RulesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RulesTable,
    Rule,
    $$RulesTableFilterComposer,
    $$RulesTableOrderingComposer,
    $$RulesTableProcessedTableManager,
    $$RulesTableInsertCompanionBuilder,
    $$RulesTableUpdateCompanionBuilder> {
  $$RulesTableTableManager(_$AppDatabase db, $RulesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$RulesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$RulesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) => $$RulesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> matchType = const Value.absent(),
            Value<String> matchValue = const Value.absent(),
            Value<String?> setCategoryId = const Value.absent(),
            Value<String?> setDescription = const Value.absent(),
            Value<String?> createdFromTxnId = const Value.absent(),
            Value<int> hitCount = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RulesCompanion(
            id: id,
            matchType: matchType,
            matchValue: matchValue,
            setCategoryId: setCategoryId,
            setDescription: setDescription,
            createdFromTxnId: createdFromTxnId,
            hitCount: hitCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String matchType,
            required String matchValue,
            Value<String?> setCategoryId = const Value.absent(),
            Value<String?> setDescription = const Value.absent(),
            Value<String?> createdFromTxnId = const Value.absent(),
            Value<int> hitCount = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              RulesCompanion.insert(
            id: id,
            matchType: matchType,
            matchValue: matchValue,
            setCategoryId: setCategoryId,
            setDescription: setDescription,
            createdFromTxnId: createdFromTxnId,
            hitCount: hitCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$RulesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $RulesTable,
    Rule,
    $$RulesTableFilterComposer,
    $$RulesTableOrderingComposer,
    $$RulesTableProcessedTableManager,
    $$RulesTableInsertCompanionBuilder,
    $$RulesTableUpdateCompanionBuilder> {
  $$RulesTableProcessedTableManager(super.$state);
}

class $$RulesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $RulesTable> {
  $$RulesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get matchType => $state.composableBuilder(
      column: $state.table.matchType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get matchValue => $state.composableBuilder(
      column: $state.table.matchValue,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get setDescription => $state.composableBuilder(
      column: $state.table.setDescription,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get hitCount => $state.composableBuilder(
      column: $state.table.hitCount,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$CategoriesTableFilterComposer get setCategoryId {
    final $$CategoriesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.setCategoryId,
        referencedTable: $state.db.categories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$CategoriesTableFilterComposer(ComposerState($state.db,
                $state.db.categories, joinBuilder, parentComposers)));
    return composer;
  }

  $$TransactionsTableFilterComposer get createdFromTxnId {
    final $$TransactionsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.createdFromTxnId,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableFilterComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$RulesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $RulesTable> {
  $$RulesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get matchType => $state.composableBuilder(
      column: $state.table.matchType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get matchValue => $state.composableBuilder(
      column: $state.table.matchValue,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get setDescription => $state.composableBuilder(
      column: $state.table.setDescription,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get hitCount => $state.composableBuilder(
      column: $state.table.hitCount,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$CategoriesTableOrderingComposer get setCategoryId {
    final $$CategoriesTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.setCategoryId,
        referencedTable: $state.db.categories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$CategoriesTableOrderingComposer(ComposerState($state.db,
                $state.db.categories, joinBuilder, parentComposers)));
    return composer;
  }

  $$TransactionsTableOrderingComposer get createdFromTxnId {
    final $$TransactionsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.createdFromTxnId,
        referencedTable: $state.db.transactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$TransactionsTableOrderingComposer(ComposerState($state.db,
                $state.db.transactions, joinBuilder, parentComposers)));
    return composer;
  }
}

class _$AppDatabaseManager {
  final _$AppDatabase _db;
  _$AppDatabaseManager(this._db);
  $$BaselinesTableTableManager get baselines =>
      $$BaselinesTableTableManager(_db, _db.baselines);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$MerchantsTableTableManager get merchants =>
      $$MerchantsTableTableManager(_db, _db.merchants);
  $$RawSmsTableTableManager get rawSms =>
      $$RawSmsTableTableManager(_db, _db.rawSms);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$FeedbackTableTableManager get feedback =>
      $$FeedbackTableTableManager(_db, _db.feedback);
  $$InsightsTableTableManager get insights =>
      $$InsightsTableTableManager(_db, _db.insights);
  $$MerchantAliasesTableTableManager get merchantAliases =>
      $$MerchantAliasesTableTableManager(_db, _db.merchantAliases);
  $$ModelMetaTableTableManager get modelMeta =>
      $$ModelMetaTableTableManager(_db, _db.modelMeta);
  $$RecurringSeriesTableTableManager get recurringSeries =>
      $$RecurringSeriesTableTableManager(_db, _db.recurringSeries);
  $$RulesTableTableManager get rules =>
      $$RulesTableTableManager(_db, _db.rules);
}
