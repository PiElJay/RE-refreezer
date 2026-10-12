import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/service/queue_selection.dart';

class Entry {
  final String id;
  Entry(this.id);
}

void main() {
  test('unavailable predecessor never shifts a click to the next song', () {
    final queue = [Entry('missing'), Entry('clicked'), Entry('next')];
    expect(resolveQueueSelection(queue, 1, queue.sublist(1)), 0);
  });
  test('missing clicked song is rejected rather than playing another song', () {
    final queue = [Entry('a'), Entry('missing'), Entry('c')];
    expect(resolveQueueSelection(queue, 1, [queue.first, queue.last]), -1);
    expect(resolveQueueSelection(queue, -1, queue), -1);
    expect(resolveQueueSelection(queue, queue.length, queue), -1);
  });
  test('duplicate IDs retain the selected occurrence', () {
    final queue = [Entry('same'), Entry('same'), Entry('end')];
    expect(resolveQueueSelection(queue, 1, queue), 1);
    expect(resolveQueueSelection(queue, 1, [queue.first, queue.last]), -1);
  });
  test('every filtered subset preserves each surviving clicked occurrence', () {
    final queue = List.generate(7, (i) => Entry('$i'));
    for (var mask = 0; mask < (1 << queue.length); mask++) {
      final available = [
        for (var i = 0; i < queue.length; i++)
          if ((mask & (1 << i)) != 0) queue[i],
      ];
      for (var selected = 0; selected < queue.length; selected++) {
        final resolved = resolveQueueSelection(queue, selected, available);
        if (resolved >= 0)
          expect(identical(available[resolved], queue[selected]), isTrue);
        else
          expect(available.contains(queue[selected]), isFalse);
      }
    }
  });
  test('recovery follows shuffle order and never wraps to its beginning', () {
    expect(nextQueueCandidates([2, 0, 3, 1], 0, {3}).toList(), [1]);
    expect(nextQueueCandidates([2, 0, 3, 1], 1, {}).toList(), isEmpty);
    expect(nextQueueCandidates([0, 1, 2], 0, {1, 2}).toList(), isEmpty);
  });
}
