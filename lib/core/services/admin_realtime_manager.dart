import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doctor_admin/core/supabase_config.dart';

/// ⚡ محرك البث المباشر والريل تايم المركزي لإدارة المنظومة (Admin Realtime Engine)
/// يستمع لحظياً لكافة أحداث قاعدة البيانات (تذاكر، طوابير، تراخيص، اشتراكات)
/// ويعكس التغييرات في أجزاء من الثانية دون أي ريفريش يدوي.
class AdminRealtimeManager {
  static final AdminRealtimeManager _instance = AdminRealtimeManager._internal();
  factory AdminRealtimeManager() => _instance;
  AdminRealtimeManager._internal();

  final SupabaseClient _client = AdminSupabaseConfig.client;
  RealtimeChannel? _channel;
  bool _isSubscribed = false;

  // بث شريط العمليات المباشر (Live Activity Stream)
  final StreamController<String> _activityStreamController =
      StreamController<String>.broadcast();
  Stream<String> get activityStream => _activityStreamController.stream;

  // مستمعو الأحداث المباشرة (Event Callbacks)
  final Set<VoidCallback> _ticketListeners = {};
  final Set<VoidCallback> _partnerListeners = {};
  final Set<VoidCallback> _subscriptionListeners = {};
  final Set<VoidCallback> _branchListeners = {};
  final Set<VoidCallback> _auditListeners = {};

  bool get isConnected => _isSubscribed;

  /// تهيئة وبدء الاستماع اللحظي المركزي
  void initialize() {
    if (_isSubscribed) return;

    try {
      _channel = _client.channel('admin_central_command_tower');

      // 1. الاستماع لتغييرات تذاكر اليوم والطابور الحي (Tickets)
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tickets',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Ticket Event: ${payload.eventType}');
          final record = payload.newRecord;
          final status = record['status'] ?? '';
          final ticketNum = record['ticket_number'] ?? '';

          if (payload.eventType == PostgresChangeEvent.insert) {
            _broadcastActivity('حجز جديد: تذكرة رقم #$ticketNum في الطابور');
          } else if (status == 'CALLED' || status == 'IN_SESSION') {
            _broadcastActivity('طبيب بدأ الكشف: نداء على تذكرة رقم #$ticketNum');
          } else if (status == 'COMPLETED') {
            _broadcastActivity('اكتمل الكشف بنجاح لتذكرة رقم #$ticketNum');
          }

          _notify(_ticketListeners);
        },
      );

      // 2. الاستماع لتسجيل الأطباء والصيدليات الجدد (Partner Verifications)
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'partner_verifications',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Partner Verification Event: ${payload.eventType}');
          final name = payload.newRecord['full_name'] ?? 'طبيب/صيدلي جديد';
          if (payload.eventType == PostgresChangeEvent.insert) {
            _broadcastActivity('طلب انضمام جديد: $name بانتظار فحص التراخيص 📋');
          }
          _notify(_partnerListeners);
        },
      );

      // 3. الاستماع لإيصالات واشتراكات الأطباء (Subscription Requests)
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'subscription_requests',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Subscription Event: ${payload.eventType}');
          if (payload.eventType == PostgresChangeEvent.insert) {
            _broadcastActivity('إيصال سداد واشتراك جديد مرفوع بانتظار المراجعة 💳');
          }
          _notify(_subscriptionListeners);
        },
      );

      // 4. الاستماع لحالة فروع العيادات والطوابير (Branches)
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'branches',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Branch Status Event: ${payload.eventType}');
          final name = payload.newRecord['name'] ?? 'فرع عيادة';
          final isActive = payload.newRecord['is_queue_active'] == true;
          _broadcastActivity(isActive ? 'تم فتح الطابور في $name 🟢' : 'تم إغلاق الطابور في $name ⚪');
          _notify(_branchListeners);
        },
      );

      // 5. الاستماع لسجل العمليات والرقابة (Audit Logs)
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'admin_audit_logs',
        callback: (payload) {
          _notify(_auditListeners);
        },
      );

      _channel!.subscribe((status, error) {
        debugPrint('⚡ Admin Realtime Channel Status: $status | $error');
        _isSubscribed = (status == RealtimeSubscribeStatus.subscribed);
      });
    } catch (e) {
      debugPrint('Error initializing AdminRealtimeManager: $e');
    }
  }

  void _broadcastActivity(String message) {
    if (!_activityStreamController.isClosed) {
      _activityStreamController.add(message);
    }
  }

  void _notify(Set<VoidCallback> listeners) {
    for (final listener in listeners.toList()) {
      try {
        listener();
      } catch (e) {
        debugPrint('Error in realtime listener callback: $e');
      }
    }
  }

  // دوال تسجيل وإلغاء تسجيل المستمعين
  void addTicketListener(VoidCallback cb) => _ticketListeners.add(cb);
  void removeTicketListener(VoidCallback cb) => _ticketListeners.remove(cb);

  void addPartnerListener(VoidCallback cb) => _partnerListeners.add(cb);
  void removePartnerListener(VoidCallback cb) => _partnerListeners.remove(cb);

  void addSubscriptionListener(VoidCallback cb) => _subscriptionListeners.add(cb);
  void removeSubscriptionListener(VoidCallback cb) => _subscriptionListeners.remove(cb);

  void addBranchListener(VoidCallback cb) => _branchListeners.add(cb);
  void removeBranchListener(VoidCallback cb) => _branchListeners.remove(cb);

  void addAuditListener(VoidCallback cb) => _auditListeners.add(cb);
  void removeAuditListener(VoidCallback cb) => _auditListeners.remove(cb);

  void dispose() {
    _channel?.unsubscribe();
    _activityStreamController.close();
    _ticketListeners.clear();
    _partnerListeners.clear();
    _subscriptionListeners.clear();
    _branchListeners.clear();
    _auditListeners.clear();
  }
}
