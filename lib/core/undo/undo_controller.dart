import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a reversible action with its inverse callback.
class UndoToken {
  UndoToken({
    required this.id,
    required this.message,
    required this.undoAction,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Unique identifier for this action.
  final String id;

  /// User-facing descriptive message (e.g., "Filed under Food").
  final String message;

  /// Real inverse operation to execute if the user taps Undo.
  final Future<void> Function() undoAction;

  /// Creation timestamp.
  final DateTime createdAt;
}

/// Global Riverpod controller managing 10-second undo state.
class UndoController extends Notifier<UndoToken?> {
  Timer? _dismissTimer;

  @override
  UndoToken? build() {
    ref.onDispose(() {
      _dismissTimer?.cancel();
    });
    return null;
  }

  /// Pushes a new undo token. Cancels any active timer and starts a 10-second countdown.
  void pushUndo(UndoToken token) {
    _dismissTimer?.cancel();
    state = token;
    _dismissTimer = Timer(const Duration(seconds: 10), () {
      if (state?.id == token.id) {
        state = null;
      }
    });
  }

  /// Executes the active undo action if present and clears the undo state.
  Future<bool> undo() async {
    final token = state;
    if (token == null) return false;

    _dismissTimer?.cancel();
    state = null;
    try {
      await token.undoAction();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clears the active undo token without running the undo action.
  void clear() {
    _dismissTimer?.cancel();
    state = null;
  }
}

final undoControllerProvider =
    NotifierProvider<UndoController, UndoToken?>(UndoController.new);
