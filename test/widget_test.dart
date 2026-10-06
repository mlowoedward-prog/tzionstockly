import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tzion_stockly/main.dart';

void main() {
  testWidgets('App shell renders all five navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TzionStocklyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify all five navigation tab labels are rendered in the app shell
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Products'), findsWidgets);
    expect(find.text('Stock'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('More'), findsWidgets);
  });
}
