import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MyApp());
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });
    expect(find.byType(MyApp), findsOneWidget);
  });
}
