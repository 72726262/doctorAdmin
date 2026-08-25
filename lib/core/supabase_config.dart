import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSupabaseConfig {
  static const String supabaseUrl = 'https://griffin-cooling-method-ata.trycloudflare.com';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3NjE5Njg5LCJleHAiOjIxMDI5Nzk2ODl9.dEfM6Hzs_QiVgqBqjWa3kbsrwKMauHemBB8IvrKwgRM';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
