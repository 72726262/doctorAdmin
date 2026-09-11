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

      await _client.rpc('insert_audit_log', params: {
        'p_admin_id': user?.id ?? '00000000-0000-0000-0000-000000000000',
        'p_admin_name': effectiveAdminName,
        'p_action_type': actionType,
        'p_target_type': targetType,
        'p_target_id': targetId ?? '',
        'p_target_name': targetName,
        'p_status': status,
        'p_details': details ?? {},
      });
    } catch (e) {
      debugPrint('⚠️ [Audit] Error logging admin action: $e');
    }
  }
}
