/// A small success-or-failure container for operations that should not throw
/// for expected domain outcomes.
sealed class Result<T, E> {
  const Result();

  /// Whether this result contains a successful value.
  bool get isOk => this is Ok<T, E>;

  /// Whether this result contains a domain error.
  bool get isErr => this is Err<T, E>;
}

/// Successful result variant.
final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);

  /// The operation's successful value.
  final T value;
}

/// Failed result variant for expected, recoverable domain errors.
final class Err<T, E> extends Result<T, E> {
  const Err(this.error);

  /// The operation's domain error.
  final E error;
}
