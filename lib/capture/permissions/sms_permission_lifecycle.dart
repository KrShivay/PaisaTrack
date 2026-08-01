import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sms_permission_provider.dart';

/// Refreshes SMS permission after Android settings or another app changes it
/// while PaisaTrack is backgrounded.
class SmsPermissionLifecycleRefresher extends ConsumerStatefulWidget {
  const SmsPermissionLifecycleRefresher({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SmsPermissionLifecycleRefresher> createState() =>
      _SmsPermissionLifecycleRefresherState();
}

class _SmsPermissionLifecycleRefresherState
    extends ConsumerState<SmsPermissionLifecycleRefresher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(smsPermissionControllerProvider.notifier).recheckStatus(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
