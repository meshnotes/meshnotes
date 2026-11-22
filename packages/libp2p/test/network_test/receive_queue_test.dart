import 'package:test/test.dart';
import 'package:libp2p/network/buffer_and_queue.dart';

void main() {
  group('ReceiveQueue ring window', () {
    test('drains full 256-object windows repeatedly without overflow', () {
      final queue = ReceiveQueue(maxBufferWindow: 256);
      for(var round = 0; round < 4; round++) {
        final start = round * 256;
        for(var offset = 0; offset < 256; offset++) {
          final id = start + offset;
          expect(queue.enqueue(id, 0, 1, [id]), isTrue);
        }
        expect(queue.popAvailableData(), List.generate(256, (offset) => [start + offset]));
        expect(queue.minObjectId, start + 256);
        expect(queue.popAvailableData(), isEmpty);
      }
    });

    test('reuses the correct slot after each partial advancement', () {
      final queue = ReceiveQueue(maxBufferWindow: 256);
      for(var id = 0; id < 1024; id++) {
        expect(queue.enqueue(id, 0, 1, [id]), isTrue);
        expect(queue.popAvailableData(), [[id]]);
        expect(queue.minObjectId, id + 1);
      }
    });

    test('preserves fragmented and out-of-order objects across a wrap', () {
      final queue = ReceiveQueue(maxBufferWindow: 4);
      expect(queue.enqueue(0, 0, 1, [0]), isTrue);
      expect(queue.popAvailableData(), [[0]]);
      expect(queue.enqueue(4, 0, 1, [40]), isTrue);
      expect(queue.enqueue(2, 0, 1, [20]), isTrue);
      expect(queue.popAvailableData(), [[20], [40]]);
      expect(queue.minObjectId, 1);
      expect(queue.isDone(2), isTrue);
      expect(queue.isDone(4), isTrue);
      // Already delivered objects must ACK duplicates without being delivered twice.
      expect(queue.enqueue(2, 0, 1, [99]), isTrue);
      expect(queue.enqueue(1, 1, 2, [11]), isTrue);
      expect(queue.enqueue(1, 1, 2, [11]), isTrue);
      expect(queue.enqueue(3, 0, 1, [30]), isTrue);
      expect(queue.popAvailableData(), [[30]]);
      expect(queue.minObjectId, 1);
      expect(queue.enqueue(1, 0, 2, [10]), isTrue);
      expect(queue.popAvailableData(), [[10, 11]]);
      expect(queue.minObjectId, 5);
      expect(queue.popAvailableData(), isEmpty);
      expect(queue.enqueue(5, 0, 1, [50]), isTrue);
      expect(queue.popAvailableData(), [[50]]);
      expect(queue.minObjectId, 6);
    });

    test('rejects beyond-window frames and accepts them after advancement', () {
      final queue = ReceiveQueue(maxBufferWindow: 4);
      expect(queue.enqueue(4, 0, 1, [4]), isFalse);
      expect(queue.enqueue(0, 0, 1, [0]), isTrue);
      // Duplicate complete objects must not overwrite the payload before delivery.
      expect(queue.enqueue(0, 0, 1, [99]), isTrue);
      expect(queue.popAvailableData(), [[0]]);
      expect(queue.enqueue(0, 0, 1, [99]), isTrue);
      expect(queue.popAvailableData(), isEmpty);
      expect(queue.enqueue(4, 0, 1, [4]), isTrue);
      expect(queue.enqueue(5, 0, 1, [5]), isFalse);
      expect(queue.popAvailableData(), [[4]]);
      expect(queue.minObjectId, 1);
      for(var id = 1; id < 4; id++) {
        expect(queue.enqueue(id, 0, 1, [id]), isTrue);
      }
      expect(queue.popAvailableData(), [[1], [2], [3]]);
      expect(queue.minObjectId, 5);
      expect(queue.enqueue(5, 0, 1, [5]), isTrue);
      expect(queue.popAvailableData(), [[5]]);
      expect(queue.minObjectId, 6);
    });
  });
}
