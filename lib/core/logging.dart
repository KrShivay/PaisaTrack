/// Debug-only logging helper.
///
/// Do not pass raw SMS bodies, account identifiers, or other sensitive payloads
/// to this function. The assert wrapper strips calls from release builds.
void debugLog(String message) {
  assert(() {
    // Keep debug logging behind assert so it is stripped from release builds.
    // Never pass raw SMS bodies to this function.
    // ignore: avoid_print
    print(message);
    return true;
  }());
}
