import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSupabaseConfig {
  static const String supabaseUrl = 'https://ztpqokvytjmlgyxhuhrv.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp0cHFva3Z5dGptbGd5eGh1aHJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwOTk4MjgsImV4cCI6MjEwMjY3NTgyOH0.enGVqIEGglow7ncDz-oCoDjfgI8zRRcISQQdB53aHws';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
