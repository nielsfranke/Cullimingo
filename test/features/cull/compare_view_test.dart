import 'package:cullimingo/features/cull/presentation/widgets/compare_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('columnsFor lays tiles out roughly square', () {
    expect(CompareView.columnsFor(1), 1);
    expect(CompareView.columnsFor(2), 2); // 2-up side by side
    expect(CompareView.columnsFor(3), 2); // 2 + 1
    expect(CompareView.columnsFor(4), 2); // 2×2
    expect(CompareView.columnsFor(5), 3);
    expect(CompareView.columnsFor(9), 3); // 3×3
    expect(CompareView.columnsFor(10), 4);
  });
}
