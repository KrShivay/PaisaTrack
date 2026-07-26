import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sort (Weekly Review) view mode: Card (Tinder-style) or List.
enum ReviewViewMode { card, list }

/// Notifier preserving view mode and active search query across tab switches.
///
/// The Sort screen's chosen mode and search string survive shell tab
/// navigation because they live in a Riverpod provider outside the widget
/// tree's lifecycle.
class ReviewViewState {
  const ReviewViewState({
    this.viewMode = ReviewViewMode.card,
    this.searchQuery = '',
  });

  final ReviewViewMode viewMode;
  final String searchQuery;

  ReviewViewState copyWith({
    ReviewViewMode? viewMode,
    String? searchQuery,
  }) =>
      ReviewViewState(
        viewMode: viewMode ?? this.viewMode,
        searchQuery: searchQuery ?? this.searchQuery,
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
}

final reviewViewProvider =
    NotifierProvider<ReviewViewNotifier, ReviewViewState>(
  ReviewViewNotifier.new,
);
