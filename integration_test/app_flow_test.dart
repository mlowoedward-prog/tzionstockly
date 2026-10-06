import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tzion_stockly/main.dart';

void main() {
  testWidgets('Integration Flow: Launch app and verify core navigation branches', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TzionStocklyApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Verify main navigation tabs exist and render
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Products'), findsWidgets);
    expect(find.text('Stock'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('More'), findsWidgets);
  });
}
