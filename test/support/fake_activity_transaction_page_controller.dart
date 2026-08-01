import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

class FakeActivityTransactionPageController
    extends ActivityTransactionPageController {
  FakeActivityTransactionPageController(this.page, {this.nextPage});

  ActivityTransactionPage page;
  ActivityTransactionPage? nextPage;

  @override
  Future<ActivityTransactionPage> build() async => page;

  @override
  Future<void> loadMore() async {
    final pageAfterLoad = nextPage;
    if (pageAfterLoad == null) return;
    page = pageAfterLoad;
    state = AsyncData(pageAfterLoad);
  }
}
