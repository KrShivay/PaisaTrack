import '../../core/undo/undo_controller.dart';
import '../../data/db/database.dart';
import '../../data/repositories/transaction_repository.dart';

typedef TransactionDatabaseLoader = Future<AppDatabase?> Function();
typedef TransactionRepositoryResolver = TransactionRepository Function(
  AppDatabase database,
);

/// Runs a transaction correction and registers its reversible action.
///
/// Screens own their optimistic presentation updates and pass them as
/// callbacks. This keeps the database/undo ordering in one place without
/// coupling the controller to a particular screen's state model.
class TransactionCorrectionController {
  const TransactionCorrectionController({
    required this.loadDatabase,
    required this.resolveRepository,
    required this.undoController,
  });

  final TransactionDatabaseLoader loadDatabase;
  final TransactionRepositoryResolver resolveRepository;
  final UndoController undoController;

  /// Applies [action], then pushes an undo token whose callback runs [undo].
  /// A null repository is allowed for review queues that can render before
  /// the database provider is ready; their UI undo callback still runs.
  Future<void> apply({
    required String id,
    required String message,
    required Future<void> Function(TransactionRepository? repository) action,
    required Future<void> Function(TransactionRepository? repository) undo,
  }) async {
    final database = await loadDatabase();
    final repository = database == null ? null : resolveRepository(database);
    await action(repository);

    undoController.pushUndo(
      UndoToken(
        id: id,
        message: message,
        undoAction: () => undo(repository),
      ),
    );
  }
}
