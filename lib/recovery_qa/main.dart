import 'package:flutter/widgets.dart';

import '../core/platform/recovery_qa_identity.dart';
import '../main.dart' as production;

/// QA-only entrypoint; production startup runs only after native identity proof.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await verifyRecoveryQaIdentity();
  await production.main();
}
