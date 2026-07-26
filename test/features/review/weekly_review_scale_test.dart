import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/review/weekly_review_providers.dart';

void main() {
  group('ReviewViewNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('defaults to card mode with empty search', () {
      final state = container.read(reviewViewProvider);
      expect(state.viewMode, equals(ReviewViewMode.card));
      expect(state.searchQuery, equals(''));
    });

    test('setViewMode switches to list mode', () {
      container
          .read(reviewViewProvider.notifier)
          .setViewMode(ReviewViewMode.list);

      final state = container.read(reviewViewProvider);
      expect(state.viewMode, equals(ReviewViewMode.list));
    });

    test('setViewMode switches back to card mode', () {
      container
          .read(reviewViewProvider.notifier)
          .setViewMode(ReviewViewMode.list);
      container
          .read(reviewViewProvider.notifier)
          .setViewMode(ReviewViewMode.card);

      final state = container.read(reviewViewProvider);
      expect(state.viewMode, equals(ReviewViewMode.card));
    });

    test('setSearchQuery updates the search query', () {
      container.read(reviewViewProvider.notifier).setSearchQuery('swiggy');

      final state = container.read(reviewViewProvider);
      expect(state.searchQuery, equals('swiggy'));
    });

    test('clearSearch resets the search query', () {
      container.read(reviewViewProvider.notifier).setSearchQuery('swiggy');
      container.read(reviewViewProvider.notifier).clearSearch();

      final state = container.read(reviewViewProvider);
      expect(state.searchQuery, equals(''));
    });

    test('view mode persists when search query changes', () {
      container
          .read(reviewViewProvider.notifier)
          .setViewMode(ReviewViewMode.list);
      container.read(reviewViewProvider.notifier).setSearchQuery('test');

      final state = container.read(reviewViewProvider);
      expect(state.viewMode, equals(ReviewViewMode.list));
      expect(state.searchQuery, equals('test'));
    });
  });
}
