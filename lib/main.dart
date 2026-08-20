import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/features/dashboard/presentation/screens/admin_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdminSupabaseConfig.initialize();

  runApp(const DoctorAdminApp());
}

class DoctorAdminApp extends StatelessWidget {
  const DoctorAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'شفاء | لوحة تحكم الإدارة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AdminColors.backgroundCanvas,
        primaryColor: AdminColors.primaryDark,
        fontFamily: GoogleFonts.cairo().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AdminColors.primaryDark,
          primary: AdminColors.primaryDark,
          secondary: AdminColors.accentCyan,
          surface: AdminColors.surfaceWhite,
        ),
      ),
      home: const AdminDashboardScreen(),
    );
  }
}
