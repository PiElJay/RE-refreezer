/// Resolve the clicked occurrence after unavailable sources have been removed.
/// Identity is intentional: duplicate track IDs can occupy different positions.
int resolveQueueSelection<T>(
  List<T> original,
  int selectedIndex,
  List<T> available,
) {
  if (selectedIndex < 0 || selectedIndex >= original.length) return -1;
  return available.indexWhere(
    (item) => identical(item, original[selectedIndex]),
  );
}

Iterable<int> nextQueueCandidates(
  List<int> order,
  int? current,
  Set<int> failed,
) sync* {
  final position = current == null ? -1 : order.indexOf(current);
  for (final index in order.skip(position + 1)) {
    if (!failed.contains(index)) yield index;
  }
}
