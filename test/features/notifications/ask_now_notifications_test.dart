import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/notifications/ask_now_notifications.dart';

void main() {
  test('payload builder puts the current guess first then fills top three',
      () async {
    final item = TransactionReviewItem(
      id: 'txn_1',
      ts: DateTime.utc(2026, 7, 8),
      amount: 749,
      direction: TransactionDirection.debit,
      displayName: 'Swiggy',
      categoryName: 'Food & Dining',
      categoryId: 'food_dining',
      categoryIcon: 'restaurant',
      status: 'asked',
    );
    final categories = [
      _categoryRow('shopping', 'Shopping', sortOrder: 1),
      _categoryRow('food_dining', 'Food & Dining', sortOrder: 2),
      _categoryRow('transport', 'Transport', sortOrder: 3),
      _categoryRow('income', 'Income', isSpending: false, sortOrder: 4),
    ];

    final payload = const AskNowPayloadBuilder().build(
      item: item,
      categories: categories,
    );

    expect(payload.txnId, 'txn_1');
    expect(payload.title, 'Categorize spend');
    expect(payload.body, contains('Swiggy'));
    expect(
      payload.actions.map((action) => action.categoryId),
      ['food_dining', 'shopping', 'transport'],
    );
  });

  test('payload builder uses income-side categories for credits', () async {
    final item = TransactionReviewItem(
      id: 'txn_credit_1',
      ts: DateTime.utc(2026, 7, 8),
      amount: 100,
      direction: TransactionDirection.credit,
      displayName: '8574973525@ptaxis',
      categoryName: 'Other',
      categoryId: 'other',
      categoryIcon: 'category',
      status: 'asked',
    );
    final categories = [
      _categoryRow('other', 'Other', sortOrder: 1),
      _categoryRow('food_dining', 'Food & Dining', sortOrder: 2),
      _categoryRow('groceries', 'Groceries', sortOrder: 3),
      _categoryRow('transfers', 'Transfers', isSpending: false, sortOrder: 4),
      _categoryRow('income', 'Income', isSpending: false, sortOrder: 5),
      _categoryRow(
        'cash_withdrawal',
        'Cash Withdrawal',
        isSpending: false,
        sortOrder: 6,
      ),
    ];

    final payload = const AskNowPayloadBuilder().build(
      item: item,
      categories: categories,
    );

    expect(payload.title, 'Categorize income');
    expect(
      payload.actions.map((action) => action.categoryId),
      ['other', 'transfers', 'income'],
    );
  });

  test('response handler writes rule, feedback and confirmed status atomically',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedCategories(database);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_ask_1',
            ts: DateTime.utc(2026, 7, 8, 9).millisecondsSinceEpoch,
            amount: 250,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: const Value('SWIGGY'),
            categoryId: const Value('other'),
            parseSource: 'template',
            confidenceJson: '{"parser":{"c":0.74,"src":"template"}}',
            status: 'asked',
            createdAt: DateTime.utc(2026, 7, 8, 9),
            updatedAt: DateTime.utc(2026, 7, 8, 9),
          ),
        );

    await const AskNowResponseHandler().handle(
      gateway: _FakeGateway([
        const AskNowResponse(txnId: 'txn_ask_1', categoryId: 'food_dining'),
      ]),
      repository: TransactionRepository(database),
      categories: [
        _categoryRow('other', 'Other', sortOrder: 1),
        _categoryRow('food_dining', 'Food & Dining', sortOrder: 2),
      ],
    );

    final txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_ask_1')))
        .getSingle();
    expect(txn.categoryId, 'food_dining');
    expect(txn.status, 'confirmed');

    final rules = await database.select(database.rules).get();
    expect(rules, hasLength(1));
    expect(rules.single.matchType, 'merchant');
    expect(rules.single.matchValue, 'SWIGGY');
    expect(rules.single.setCategoryId, 'food_dining');
    expect(rules.single.createdFromTxnId, 'txn_ask_1');

    final feedback = await database.select(database.feedback).get();
    expect(feedback, hasLength(2));
    final categoryFeedback = feedback.singleWhere(
      (row) => row.field == 'category_id',
    );
    expect(categoryFeedback.oldValue, 'other');
    expect(categoryFeedback.newValue, 'food_dining');
    expect(categoryFeedback.context, 'ask_now');
    expect(categoryFeedback.modelConfidenceAtTime, 0.74);

    final statusFeedback = feedback.singleWhere((row) => row.field == 'status');
    expect(statusFeedback.oldValue, 'asked');
    expect(statusFeedback.newValue, 'confirmed');
    expect(statusFeedback.context, 'ask_now');
  });
}

Future<void> _seedCategories(AppDatabase database) async {
  await database
      .into(database.categories)
      .insert(_categoryCompanion('other', 'Other'));
  await database
      .into(database.categories)
      .insert(_categoryCompanion('food_dining', 'Food & Dining', sortOrder: 2));
}

Category _categoryRow(
  String id,
  String name, {
  bool isSpending = true,
  int sortOrder = 1,
}) {
  return Category(
    id: id,
    name: name,
    parentId: null,
    icon: 'category',
    isSpending: isSpending,
    sortOrder: sortOrder,
    isUserCreated: false,
  );
}

CategoriesCompanion _categoryCompanion(
  String id,
  String name, {
  bool isSpending = true,
  int sortOrder = 1,
}) {
  return CategoriesCompanion.insert(
    id: id,
    name: name,
    icon: 'category',
    isSpending: isSpending,
    sortOrder: sortOrder,
    isUserCreated: false,
  );
}

class _FakeGateway implements AskNowNotificationGateway {
  _FakeGateway(this.responses);

  final List<AskNowResponse> responses;

  @override
  Future<bool> show(AskNowPayload payload) async => true;

  @override
  Future<List<AskNowResponse>> takePendingResponses() async => responses;

  @override
  Future<void> ackPendingResponses(Set<String> txnIds) async {}
}
