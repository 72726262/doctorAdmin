import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AdminSupabaseConfig.initialize();
  });

  testWidgets('Doctor Admin Web Smoke Test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const DoctorAdminApp());
    expect(find.byType(DoctorAdminApp), findsOneWidget);
  });
}
