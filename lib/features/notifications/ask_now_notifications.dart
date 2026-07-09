import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../transactions/transactions_providers.dart';

class AskNowAction {
  const AskNowAction({
    required this.categoryId,
    required this.label,
  });

  final String categoryId;
  final String label;

  Map<String, Object?> toJson() {
    return {
      'categoryId': categoryId,
      'label': label,
    };
  }
}

class AskNowPayload {
  const AskNowPayload({
    required this.txnId,
    required this.title,
    required this.body,
    required this.actions,
  });

  final String txnId;
  final String title;
  final String body;
  final List<AskNowAction> actions;

  Map<String, Object?> toJson() {
    return {
      'txnId': txnId,
      'title': title,
      'body': body,
      'actions': actions.map((action) => action.toJson()).toList(),
    };
  }
}

class AskNowResponse {
  const AskNowResponse({
    required this.txnId,
    this.categoryId,
    this.freeText,
  });

  final String txnId;
  final String? categoryId;
  final String? freeText;

  static AskNowResponse fromJson(Map<Object?, Object?> json) {
    return AskNowResponse(
      txnId: json['txnId']! as String,
      categoryId: json['categoryId'] as String?,
      freeText: json['freeText'] as String?,
    );
  }
}

class AskNowPayloadBuilder {
  const AskNowPayloadBuilder();

  AskNowPayload build({
    required TransactionReviewItem item,
    required List<Category> categories,
  }) {
    final actions = <AskNowAction>[];
    final byId = {for (final category in categories) category.id: category};
    final isCredit = item.direction == TransactionDirection.credit;

    void addCategory(String? id) {
      if (id == null || actions.any((action) => action.categoryId == id)) {
        return;
      }
      final category = byId[id];
      if (category == null) return;
      if (category.id != 'other' && category.isSpending == isCredit) return;
      actions.add(AskNowAction(categoryId: category.id, label: category.name));
    }

    addCategory(item.categoryId);
    for (final category in categories.where(
      (category) => category.id == 'other' || category.isSpending != isCredit,
    )) {
      addCategory(category.id);
      if (actions.length == 3) break;
    }

    return AskNowPayload(
      txnId: item.id,
      title: 'Categorize ${isCredit ? 'income' : 'spend'}',
      body: '${item.displayName} ${formatInr(item.amount)}',
      actions: actions,
    );
  }
}

abstract class AskNowNotificationGateway {
  Future<bool> show(AskNowPayload payload);

  Future<List<AskNowResponse>> takePendingResponses();

  Future<void> ackPendingResponses(Set<String> txnIds);
}

class MethodChannelAskNowNotificationGateway
    implements AskNowNotificationGateway {
  MethodChannelAskNowNotificationGateway({
    MethodChannel channel = const MethodChannel('com.paisatrack/ask_now'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<bool> show(AskNowPayload payload) async {
    return await _channel.invokeMethod<bool>('show', payload.toJson()) ?? false;
  }

  @override
  Future<List<AskNowResponse>> takePendingResponses() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
          'takePendingResponses',
        ) ??
        const [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map(AskNowResponse.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> ackPendingResponses(Set<String> txnIds) async {
    if (txnIds.isEmpty) return;
    await _channel.invokeMethod<void>('ackPendingResponses', txnIds.toList());
  }
}

class AskNowResponseHandler {
  const AskNowResponseHandler();

  Future<Set<String>> handle({
    required AskNowNotificationGateway gateway,
    required TransactionRepository repository,
    required List<Category> categories,
  }) async {
    final handledTxnIds = <String>{};
    final ackTxnIds = <String>{};
    final responses = await gateway.takePendingResponses();
    for (final response in responses) {
      final resolved = _resolveResponse(response, categories);
      if (resolved == null) {
        ackTxnIds.add(response.txnId);
        continue;
      }
      try {
        await repository.correctWithRule(
          txnId: response.txnId,
          categoryId: resolved.categoryId,
          description: resolved.description,
          context: 'ask_now',
        );
        handledTxnIds.add(response.txnId);
        ackTxnIds.add(response.txnId);
      } on StateError {
        ackTxnIds.add(response.txnId);
      }
    }
    await gateway.ackPendingResponses(ackTxnIds);
    return handledTxnIds;
  }
}

final askNowNotificationGatewayProvider =
    Provider<AskNowNotificationGateway>((ref) {
  return MethodChannelAskNowNotificationGateway();
});

final shownAskNowTxnIdsProvider = StateProvider<Set<String>>((ref) {
  return <String>{};
});

var _askNowResponsePollInFlight = false;

final askNowNotificationControllerProvider = Provider<void>((ref) {
  final database = ref.watch(appDatabaseProvider).valueOrNull;
  final askQueue = ref.watch(askQueueProvider).valueOrNull ?? const [];
  final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];
  if (database == null || categories.isEmpty) return;

  var disposed = false;
  ref.onDispose(() => disposed = true);

  final gateway = ref.watch(askNowNotificationGatewayProvider);
  final repository = ref.watch(transactionRepositoryProvider(database));
  const builder = AskNowPayloadBuilder();
  const responseHandler = AskNowResponseHandler();

  Future<void> processPendingResponses() async {
    if (_askNowResponsePollInFlight) return;
    _askNowResponsePollInFlight = true;
    try {
      final handledTxnIds = await responseHandler.handle(
        gateway: gateway,
        repository: repository,
        categories: categories,
      );
      if (handledTxnIds.isEmpty || disposed) return;
      ref.read(shownAskNowTxnIdsProvider.notifier).update(
            (shownTxnIds) => shownTxnIds.difference(handledTxnIds),
          );
    } finally {
      _askNowResponsePollInFlight = false;
    }
  }

  unawaited(processPendingResponses());
  final responsePoller = Timer.periodic(
    const Duration(seconds: 5),
    (_) => unawaited(processPendingResponses()),
  );
  ref.onDispose(responsePoller.cancel);

  final currentTxnIds = askQueue.map((item) => item.id).toSet();
  final shownTxnIds = ref.watch(shownAskNowTxnIdsProvider);
  final prunedShownTxnIds = shownTxnIds.intersection(currentTxnIds);
  if (prunedShownTxnIds.length != shownTxnIds.length) {
    ref.read(shownAskNowTxnIdsProvider.notifier).state = prunedShownTxnIds;
  }

  final pendingShows =
      askQueue.where((item) => !prunedShownTxnIds.contains(item.id)).toList();
  if (pendingShows.isEmpty) return;

  // Show notifications sequentially, record which succeeded, then commit the
  // "shown" set in a single guarded write *after* all shows finish. Because
  // this provider watches shownAskNowTxnIdsProvider, writing to it from a
  // per-show callback would dispose this instance while other shows are still
  // in flight, and those callbacks would then touch a disposed ref (uncaught
  // StateError) and leave their items to be re-shown. One write at the end,
  // gated on `disposed`, closes that window.
  Future<void> showPendingNotifications() async {
    final newlyShownTxnIds = <String>{};
    for (final item in pendingShows) {
      final bool shown;
      try {
        shown = await gateway.show(
          builder.build(item: item, categories: categories),
        );
      } on Exception {
        continue;
      }
      if (shown) newlyShownTxnIds.add(item.id);
    }
    if (disposed || newlyShownTxnIds.isEmpty) return;
    ref.read(shownAskNowTxnIdsProvider.notifier).update(
          (shownTxnIds) => {...shownTxnIds, ...newlyShownTxnIds},
        );
  }

  unawaited(showPendingNotifications());
});

_ResolvedAskNowAnswer? _resolveResponse(
  AskNowResponse response,
  List<Category> categories,
) {
  final categoryId = response.categoryId;
  if (categoryId != null &&
      categories.any((category) => category.id == categoryId)) {
    return _ResolvedAskNowAnswer(categoryId: categoryId);
  }

  final text = response.freeText?.trim();
  if (text == null || text.isEmpty) return null;

  for (final category in categories) {
    if (category.name.toLowerCase() == text.toLowerCase()) {
      return _ResolvedAskNowAnswer(categoryId: category.id);
    }
  }

  final fallback = categories.firstWhere(
    (category) => category.id == 'other',
    orElse: () => categories.first,
  );
  return _ResolvedAskNowAnswer(
    categoryId: fallback.id,
    description: text,
  );
}

class _ResolvedAskNowAnswer {
  const _ResolvedAskNowAnswer({
    required this.categoryId,
    this.description,
  });

  final String categoryId;
  final String? description;
}
