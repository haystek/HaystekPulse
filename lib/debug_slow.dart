import 'dart:async';

/// TEMPORARY test switch (node slowdebug.js ON / OFF).
/// true: every start-up loader shows its name and waits a little,
/// so you can see which one appears. Must be false for real builds.
const bool kSlowStart = false;

/// Waits [ms] in test mode, nothing otherwise.
Future<void> slowWait(int ms) =>
    kSlowStart ? Future<void>.delayed(Duration(milliseconds: ms)) : Future<void>.value();

/// Test mode: the FIRST value of [s] arrives [ms] later. Otherwise [s] as is.
Stream<T> slowFirst<T>(Stream<T> s, int ms) {
  if (!kSlowStart) return s;
  var first = true;
  return s.asyncMap((v) async {
    if (first) {
      first = false;
      await Future<void>.delayed(Duration(milliseconds: ms));
    }
    return v;
  });
}
