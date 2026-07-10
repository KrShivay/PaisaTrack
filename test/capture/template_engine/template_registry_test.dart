import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';

void main() {
  test('template provenance defaults to device for legacy JSON', () {
    final registry = TemplateRegistry.fromJson('''
      {"sender_patterns": [], "templates": [{
        "id": "legacy", "regex": "x", "direction": "debit",
        "channel": "upi"
      }]}
    ''');

    expect(registry.templates.single.provenance, TemplateProvenance.device);
  });

  test('template registry reads public provenance from JSON', () {
    final registry = TemplateRegistry.fromJson('''
      {"sender_patterns": [], "templates": [{
        "id": "public", "regex": "x", "direction": "debit",
        "channel": "upi", "provenance": "public"
      }]}
    ''');

    expect(registry.templates.single.provenance, TemplateProvenance.public);
  });
}
