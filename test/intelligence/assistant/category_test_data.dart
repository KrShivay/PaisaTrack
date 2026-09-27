import 'dart:convert';
import 'dart:io';

import 'package:paisatrack/intelligence/assistant/assistant_intent.dart';

List<Map<String, Object?>> seededCategoryRows() =>
    (jsonDecode(File('assets/seed/categories.json').readAsStringSync()) as List)
        .cast<Map<String, Object?>>();

List<AssistantCategoryOption> seededCategoryOptions() => seededCategoryRows()
    .map(
      (row) => AssistantCategoryOption(
        id: row['id']! as String,
        name: row['name']! as String,
        parentId: row['parent_id'] as String?,
      ),
    )
    .toList(growable: false);
