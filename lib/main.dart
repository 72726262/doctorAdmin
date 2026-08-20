import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doctor_admin/features/auth/presentation/screens/admin_login_screen.dart';
import 'package:doctor_admin/features/dashboard/presentation/screens/admin_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdminSupabaseConfig.initialize();

  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('is_admin_logged_in') ?? false;

  runApp(DoctorAdminApp(initialLoggedIn: isLoggedIn));
}

class DoctorAdminApp extends StatelessWidget {
  final bool initialLoggedIn;
  const DoctorAdminApp({super.key, required this.initialLoggedIn});

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
      home: initialLoggedIn ? const AdminDashboardScreen() : const AdminLoginScreen(),
    );
  }
}
