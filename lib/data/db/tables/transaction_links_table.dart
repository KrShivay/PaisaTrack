import 'package:drift/drift.dart';

import 'transactions_table.dart';

/// Transaction links table establishing graph relationships between transactions.
class TransactionLinks extends Table {
  TextColumn get id => text()();
  @ReferenceName('fromTransactionLinks')
  TextColumn get fromTxnId => text().references(Transactions, #id)();
  @ReferenceName('toTransactionLinks')
  TextColumn get toTxnId => text().references(Transactions, #id)();
  TextColumn get linkType => text()(); // echo | settles | reverses | refunds | repays | transfer_leg | fulfills
  RealColumn get confidence => real().withDefault(const Constant(1.0))();
  TextColumn get basis => text()();
  TextColumn get createdBy => text().withDefault(const Constant('system'))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
