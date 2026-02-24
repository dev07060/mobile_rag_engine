import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/internal/serial_async_executor.dart';

void main() {
  group('SerialAsyncExecutor', () {
    test('runs tasks in FIFO order', () async {
      final executor = SerialAsyncExecutor();
      final executionOrder = <int>[];

      final results = await Future.wait<int>([
        executor.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          executionOrder.add(1);
          return 1;
        }),
        executor.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          executionOrder.add(2);
          return 2;
        }),
        executor.run(() async {
          executionOrder.add(3);
          return 3;
        }),
      ]);

      expect(results, <int>[1, 2, 3]);
      expect(executionOrder, <int>[1, 2, 3]);
    });

    test('continues processing after a task fails', () async {
      final executor = SerialAsyncExecutor();
      final executionOrder = <String>[];

      final first = executor.run<void>(() async {
        executionOrder.add('first');
        throw StateError('boom');
      });

      final second = executor.run<int>(() async {
        executionOrder.add('second');
        return 42;
      });

      await expectLater(first, throwsA(isA<StateError>()));
      await expectLater(second, completion(42));
      expect(executionOrder, <String>['first', 'second']);
    });
  });
}
