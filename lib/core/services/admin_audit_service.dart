import 'package:flutter/foundation.dart';
import 'package:doctor_admin/core/supabase_config.dart';

/// 🛡️ خدمة تسجيل العمليات الرقابية والأمنية (Admin Audit Trail Service)
/// توثق كل إجراء يتخذه المشرف في قاعدة البيانات لحظياً لضمان الشفافية والأمان.
class AdminAuditService {
  static final _client = AdminSupabaseConfig.client;

  /// تسجيل عملية رقابية جديدة
  static Future<void> log({
    required String actionType,
    required String targetType,
    required String targetName,
    String? targetId,
    Map<String, dynamic>? details,
    String status = 'SUCCESS',
    String? adminName,
  }) async {
    try {
      final user = _client.auth.currentUser;
      final effectiveAdminName = adminName ??
          user?.userMetadata?['full_name'] as String? ??
          user?.email ??
          'أدمن المنظومة الرئيسي';

      await _client.from('admin_audit_logs').insert({
        'admin_id': user?.id,
        'admin_name': effectiveAdminName,
        'action_type': actionType,
        'target_type': targetType,
        'target_id': targetId,
        'target_name': targetName,
        'details': details ?? {},
        'status': status,
        'ip_address': kIsWeb ? 'Web Console' : 'App Client',
      });
    } catch (e) {
      debugPrint('⚠️ [Audit] Error logging admin action: $e');
    }
  }
}
