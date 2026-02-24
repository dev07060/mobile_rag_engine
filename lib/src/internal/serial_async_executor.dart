library;

import 'dart:async';

/// Runs async tasks one-by-one in FIFO order.
///
/// A failed task does not block subsequent tasks.
class SerialAsyncExecutor {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(FutureOr<T> Function() task) {
    final completer = Completer<T>();

    _tail = _tail.catchError((_) {}).then((_) async {
      try {
        final result = await Future<T>.sync(task);
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }
}
