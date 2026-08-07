import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sort (Weekly Review) view mode: Card (Tinder-style) or List.
enum ReviewViewMode { card, list }

/// Notifier preserving view mode, active search query, and skip state across
/// tab switches and widget rebuilds.
class ReviewViewState {
  const ReviewViewState({
    this.viewMode = ReviewViewMode.card,
    this.searchQuery = '',
    this.skippedIds = const {},
  });

  final ReviewViewMode viewMode;
  final String searchQuery;

  /// IDs of transactions skipped in the current sort session. Kept in the
  /// provider so the skip set survives the Sort widget being disposed and
  /// recreated (e.g., navigating away and back).
  final Set<String> skippedIds;

  ReviewViewState copyWith({
    ReviewViewMode? viewMode,
    String? searchQuery,
    Set<String>? skippedIds,
  }) =>
      ReviewViewState(
        viewMode: viewMode ?? this.viewMode,
        searchQuery: searchQuery ?? this.searchQuery,
        skippedIds: skippedIds ?? this.skippedIds,
      );
}

class ReviewViewNotifier extends Notifier<ReviewViewState> {
  @override
  ReviewViewState build() => const ReviewViewState();

  void setViewMode(ReviewViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void clearSearch() {
    state = state.copyWith(searchQuery: '');
  }

  void skipItem(String id) {
    state = state.copyWith(skippedIds: {...state.skippedIds, id});
  }

  void unskipItem(String id) {
    state = state.copyWith(
      skippedIds: state.skippedIds.difference({id}),
    );
  }

  void clearSkipped() {
    state = state.copyWith(skippedIds: const {});
  }
}

final reviewViewProvider =
    NotifierProvider<ReviewViewNotifier, ReviewViewState>(
  ReviewViewNotifier.new,
);
