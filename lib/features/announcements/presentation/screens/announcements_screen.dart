import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _client = AdminSupabaseConfig.client;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _searchController = TextEditingController();
  final _daysThresholdController = TextEditingController(text: '10');

  String _targetRole = 'ALL';
  int _daysThreshold = 10;
  String _priority = 'NORMAL';
  String _selectedFilter = 'الكل';
  String _searchQuery = '';
  bool _isPublishing = false;
  bool _isLoading = true;
  bool _isLoadingPreview = false;
  Map<String, dynamic>? _audiencePreview;
  List<Map<String, dynamic>> _announcements = [];

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
    _fetchAudiencePreview();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _searchController.dispose();
    _daysThresholdController.dispose();
    super.dispose();
  }

  Future<void> _fetchAudiencePreview() async {
    if (!mounted) return;
    setState(() => _isLoadingPreview = true);
    try {
      final res = await _client.rpc('preview_broadcast_audience', params: {
        'p_target_type': _targetRole,
        'p_days_threshold': _daysThreshold,
      });
      if (mounted) {
        setState(() {
          _audiencePreview = res is Map ? Map<String, dynamic>.from(res) : null;
          _isLoadingPreview = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPreview = false);
    }
  }

  Future<void> _fetchAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client
          .from('system_announcements')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePublish() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة عنوان الإعلان والرسالة التفصيلية أولاً'),
          backgroundColor: AdminColors.warning,
        ),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final res = await _client.rpc('dispatch_system_broadcast_and_alerts', params: {
        'p_title': title,
        'p_content': content,
        'p_priority': _priority,
        'p_target_type': _targetRole,
        'p_days_threshold': _daysThreshold,
        'p_announcement_type': _priority,
      });

      final resMap = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final fcmTopic = resMap['fcm_topic'] as String?;
      final tokens = (resMap['tokens'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final announcementId = resMap['announcement_id'] as String? ?? '';
      final inAppCount = resMap['in_app_notifications_created'] ?? 0;

      int pushDelivered = 0;
      try {
        if (fcmTopic != null && fcmTopic.isNotEmpty) {
          final pushRes = await _client.functions.invoke('push-dispatcher', body: {
            'topic': fcmTopic,
            'title': title,
            'body': content,
            'data': {
              'announcement_id': announcementId,
              'target_type': _targetRole,
              'priority': _priority,
            },
            'channelId': 'shefaa_announcements_channel',
          });
          if (pushRes.status == 200) pushDelivered = 1;
        } else if (tokens.isNotEmpty) {
          final pushRes = await _client.functions.invoke('push-dispatcher', body: {
            'tokens': tokens,
            'title': title,
            'body': content,
            'data': {
              'announcement_id': announcementId,
              'target_type': _targetRole,
              'priority': _priority,
            },
            'channelId': 'shefaa_announcements_channel',
          });
          final pushData = pushRes.data is Map ? pushRes.data : {};
          pushDelivered = pushData['successCount'] ?? tokens.length;
        }
      } catch (pushErr) {
        debugPrint('⚠️ Push Dispatcher Warning: $pushErr');
      }

      _titleController.clear();
      _contentController.clear();
      await _fetchAnnouncements();
      await _fetchAudiencePreview();

      AdminAuditService.log(
        actionType: 'بث إعلان عام وتنبيه فوري',
        targetType: 'ANNOUNCEMENT',
        targetName: title,
        details: {
          'target_role': _targetRole,
          'priority': _priority,
          'days_threshold': _daysThreshold,
          'in_app_count': inAppCount,
          'push_delivered': pushDelivered,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📢 تم بث الإعلان بنجاح! تم إنشاء $inAppCount إشعار في صندوق الوارد، ووصل التنبيه الفوري لأجهزة المستخدمين.',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AdminColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر بث الإعلان: $e'),
            backgroundColor: AdminColors.emergency,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _toggleAnnouncementStatus(String id, bool currentStatus) async {
    try {
      await _client
          .from('system_announcements')
          .update({'is_active': !currentStatus})
          .eq('id', id);

      _fetchAnnouncements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentStatus ? 'تم إيقاف بث الإعلان مؤقتاً' : 'تم استئناف وتفعيل بث الإعلان 🟢'),
            backgroundColor: currentStatus ? AdminColors.warning : AdminColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  Future<void> _deleteAnnouncement(String id, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text('تأكيد حذف الإعلان', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في حذف إعلان "$title" نهائياً من المنظومة؟',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نعم، احذف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _client.from('system_announcements').delete().eq('id', id);
      _fetchAnnouncements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الإعلان بنجاح'), backgroundColor: AdminColors.emergency),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحذف: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // إحصائيات KPI
    final totalCount = _announcements.length;
    final activeCount = _announcements.where((a) => a['is_active'] == true).length;
    final partnersCount = _announcements.where((a) {
      final role = (a['target_role'] ?? '').toString().toUpperCase();
      return role == 'DOCTOR' || role == 'PHARMACY';
    }).length;
    final urgentCount = _announcements.where((a) {
      final p = (a['priority'] ?? a['announcement_type'] ?? '').toString().toUpperCase();
      return p == 'URGENT';
    }).length;

    // فلترة القائمة
    final filtered = _announcements.where((a) {
      final role = (a['target_role'] ?? 'ALL').toString().toUpperCase();
      final isActive = a['is_active'] == true;
      final priority = (a['priority'] ?? a['announcement_type'] ?? 'NORMAL').toString().toUpperCase();

      if (_selectedFilter == 'نشطة فقط 🟢' && !isActive) return false;
      if (_selectedFilter == 'للأطباء 🩺' && role != 'DOCTOR' && role != 'DOCTORS_EXPIRING') return false;
      if (_selectedFilter == 'للصيدليات 💊' && role != 'PHARMACY' && role != 'PHARMACIES_EXPIRING') return false;
      if (_selectedFilter == 'للمرضى 👥' && role != 'PATIENT') return false;
      if (_selectedFilter == 'تجديد اشتراكات ⏳' && role != 'DOCTORS_EXPIRING' && role != 'PHARMACIES_EXPIRING') return false;
      if (_selectedFilter == 'عاجلة ⚡' && priority != 'URGENT') return false;

      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      final title = (a['title'] ?? '').toString().toLowerCase();
      final content = (a['content'] ?? a['message'] ?? '').toString().toLowerCase();
      return title.contains(q) || content.contains(q);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AdminColors.primaryDark.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'مركز الإذاعة والبث العام والتنبيهات',
                        style: GoogleFonts.cairo(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إرسال وإدارة التنبيهات المباشرة للأطباء، الصيدليات، والمرضى وبث الإعلانات الرسمية اللحظية',
                    style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث الإعلانات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: _fetchAnnouncements,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 2. Top KPI Summary Strip
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'إجمالي الإعلانات',
                  count: totalCount,
                  subtitle: 'مسجلة في قاعدة البيانات',
                  icon: Icons.all_inbox_rounded,
                  color: const Color(0xFF6366F1), // Indigo
                  bgColor: const Color(0xFFEEF2FF),
                  borderColor: const Color(0xFFC7D2FE),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'إعلانات نشطة تبث الآن 🟢',
                  count: activeCount,
                  subtitle: 'تظهر للمستخدمين حالياً',
                  icon: Icons.campaign_rounded,
                  color: const Color(0xFF10B981), // Emerald
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'موجهة للشركاء 🩺',
                  count: partnersCount,
                  subtitle: 'للأطباء والصيدليات',
                  icon: Icons.medical_services_rounded,
                  color: AdminColors.primaryDark, // Teal
                  bgColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'تنبيهات عاجلة ⚡',
                  count: urgentCount,
                  subtitle: 'أولوية قصوى للمنظومة',
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFFF59E0B), // Amber
                  bgColor: const Color(0xFFFFFBEB),
                  borderColor: const Color(0xFFFDE68A),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 3. Broadcast Form Card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AdminColors.surfaceWhite,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AdminColors.cardBorderMint),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AdminColors.accentMintLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_alert_rounded, color: AdminColors.primaryDark, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'إنشاء وبث إعلان وتنبيه فوري للمنظومة 📢',
                          style: GoogleFonts.cairo(fontSize: 15.5, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'إشعار لحظي فوري',
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Priority Selector Chips
                Text('نوع ومستوى أولوية التنبيه:', style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPriorityChip('📢 تنبيه عام', 'NORMAL', const Color(0xFF0D9488)),
                    _buildPriorityChip('⚡ عاجل وفوري', 'URGENT', const Color(0xFFEF4444)),
                    _buildPriorityChip('🛠️ صيانة خوادم', 'MAINTENANCE', const Color(0xFFF59E0B)),
                    _buildPriorityChip('🎁 عروض وخصومات', 'OFFER', const Color(0xFF8B5CF6)),
                  ],
                ),

                const SizedBox(height: 16),

                // Title Input
                TextField(
                  controller: _titleController,
                  style: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText: 'عنوان الإعلان أو التنبيه الرئيسي',
                    labelStyle: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                    hintText: 'مثال: صيانة دورية مجدولة لخوادم المزامنة الفورية...',
                    hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.campaign_outlined, color: AdminColors.primaryDark, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.primaryDark, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),

                const SizedBox(height: 14),

                // Content Input
                TextField(
                  controller: _contentController,
                  maxLines: 3,
                  style: GoogleFonts.cairo(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'نص الإعلان والرسالة التفصيلية',
                    labelStyle: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                    hintText: 'اكتب نص الرسالة التي ستظهر للمستخدمين بوضوح وتفصيل...',
                    hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 40),
                      child: Icon(Icons.edit_note_rounded, color: AdminColors.primaryDark, size: 22),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.primaryDark, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),

                const SizedBox(height: 16),

                // Target Audience & Broadcast Action Row
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'الفئة المستهدفة: ',
                              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildRoleChip('جميع المستخدمين 🌐', 'ALL'),
                                _buildRoleChip('الأطباء والعيادات 🩺', 'DOCTOR'),
                                _buildRoleChip('الصيدليات فقط 💊', 'PHARMACY'),
                                _buildRoleChip('المرضى فقط 👥', 'PATIENT'),
                                _buildRoleChip('⏳ أطباء ينتهي اشتراكهم قريباً', 'DOCTORS_EXPIRING'),
                                _buildRoleChip('⏳ صيدليات ينتهي اشتراكها قريباً', 'PHARMACIES_EXPIRING'),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Dedicated Expiration Configuration Box
                      if (_targetRole.contains('EXPIRING')) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade300, width: 1.2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, color: Color(0xFFD97706), size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    _targetRole == 'DOCTORS_EXPIRING'
                                        ? 'تحديد مهلة أيام انتهاء اشتراك الأطباء:'
                                        : 'تحديد مهلة أيام انتهاء اشتراك الصيدليات:',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 12.5, color: const Color(0xFF92400E)),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFFB45309),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    ),
                                    icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
                                    label: Text(
                                      'تعبئة قالب تذكير التجديد 📝',
                                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5),
                                    ),
                                    onPressed: () {
                                      if (_targetRole == 'DOCTORS_EXPIRING') {
                                        _titleController.text = 'تذكير: موعد تجديد اشتراك عيادتكم في منصة كشفك ⏳';
                                        _contentController.text = 'عزيزي الطبيب، نود إحاطتكم علماً بقرب انتهاء اشتراك عيادتكم خلال $_daysThreshold أيام. يرجى التكرم بالمبادرة بالتجديد لضمان استمرار ظهور العيادة واستقبال حجوزات المرضى دون انقطاع 💚';
                                      } else {
                                        _titleController.text = 'تذكير: موعد تجديد اشتراك صيدليتكم في منصة كشفك 💊';
                                        _contentController.text = 'دكتور الصيدلية العزيز، نود تذكيركم بأن اشتراك صيدليتكم في منصة كشفك يقترب من الانتهاء خلال $_daysThreshold أيام. يرجى المبادرة بسداد التجديد لاستمرار استقبال الروشتات والطلبات.';
                                      }
                                      _priority = 'URGENT';
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('المهلة السريعة:', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                                  const SizedBox(width: 8),
                                  Wrap(
                                    spacing: 6,
                                    children: [3, 7, 10, 15, 30].map((days) {
                                      final isSel = _daysThreshold == days;
                                      return ChoiceChip(
                                        label: Text('$days أيام', style: GoogleFonts.cairo(fontSize: 11, fontWeight: isSel ? FontWeight.w900 : FontWeight.bold, color: isSel ? Colors.white : AdminColors.textPrimary)),
                                        selected: isSel,
                                        selectedColor: const Color(0xFFD97706),
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        onSelected: (_) {
                                          setState(() {
                                            _daysThreshold = days;
                                            _daysThresholdController.text = '$days';
                                          });
                                          _fetchAudiencePreview();
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(width: 14),
                                  Text('أو عدد أيام مخصص:', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 65,
                                    height: 34,
                                    child: TextField(
                                      controller: _daysThresholdController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w900),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                                      ),
                                      onChanged: (val) {
                                        final d = int.tryParse(val.trim());
                                        if (d != null && d > 0 && d != _daysThreshold) {
                                          _daysThreshold = d;
                                          _fetchAudiencePreview();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Live Audience Preview Strip
                      if (_audiencePreview != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.people_alt_rounded, size: 16, color: AdminColors.primaryDark),
                              const SizedBox(width: 6),
                              Text('معاينة الجمهور المستهدف:', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AdminColors.primaryDark.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '👥 ${_audiencePreview!['total_matching_users'] ?? 0} مستخدم مطابق',
                                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w900, color: AdminColors.primaryDark),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '📱 ${_audiencePreview!['users_with_push_tokens'] ?? 0} جهاز مفعل للإشعار الفوري',
                                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                                ),
                              ),
                              if ((_audiencePreview!['sample_names'] as List?)?.isNotEmpty == true) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'عينة: ${(_audiencePreview!['sample_names'] as List).join('، ')}',
                                    style: GoogleFonts.cairo(fontSize: 10.5, color: const Color(0xFF64748B)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              if (_isLoadingPreview)
                                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Action Button Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminColors.primaryDark,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                            ),
                            icon: _isPublishing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.send_rounded, size: 18),
                            label: Text(
                              _isPublishing ? 'جاري البث والإرسال...' : 'بث الإعلان والتنبيه الفوري الآن 🚀',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13.5),
                            ),
                            onPressed: _isPublishing ? null : _handlePublish,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 4. Toolbar: Search Bar & Filters
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ابحث في نصوص الإعلانات، العناوين، أو الفئات...',
                      hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              AdminFilterChips(
                options: const ['الكل', 'نشطة فقط 🟢', 'للأطباء 🩺', 'للصيدليات 💊', 'للمرضى 👥', 'تجديد اشتراكات ⏳', 'عاجلة ⚡'],
                selectedOption: _selectedFilter,
                onSelected: (val) => setState(() => _selectedFilter = val),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 5. Active Announcements Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'سجل الإعلانات والتنبيهات المبثوثة (${filtered.length}):',
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
              ),
              if (_searchQuery.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('مسح البحث', style: GoogleFonts.cairo(fontSize: 12)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
            ],
          ),

          const SizedBox(height: 12),

          // 6. Announcements Cards List / Empty State
          if (_isLoading && _announcements.isEmpty)
            const AdminTableSkeleton(rows: 4)
          else if (filtered.isEmpty)
            AdminEmptyStateCard(
              title: _searchQuery.isNotEmpty
                  ? 'لا توجد إعلانات مطابقة لبحث "$_searchQuery"'
                  : 'لا توجد إعلانات مبثوثة في هذا القسم حالياً',
              description: _searchQuery.isNotEmpty
                  ? 'تأكد من كتابة الكلمات الدلالية بشكل صحيح، أو اختر تصنيفاً آخر.'
                  : 'يمكنك إنشاء إعلان جديد وبثه لجميع المستخدمين أو فئات محددة من النموذج أعلاه.',
              icon: Icons.campaign_outlined,
              onRefresh: _fetchAnnouncements,
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final a = filtered[index];
                return _buildAnnouncementCard(a);
              },
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPriorityChip(String label, String value, Color color) {
    final isSelected = _priority == value;
    return InkWell(
      onTap: () => setState(() => _priority = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : const Color(0xFFCBD5E1)),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            color: isSelected ? Colors.white : AdminColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildRoleChip(String label, String value) {
    final isSelected = _targetRole == value;
    return InkWell(
      onTap: () {
        setState(() => _targetRole = value);
        _fetchAudiencePreview();
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primaryDark : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AdminColors.primaryDark : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
            color: isSelected ? Colors.white : AdminColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> a) {
    final id = a['id'] as String;
    final title = a['title'] ?? 'بدون عنوان';
    final content = (a['content'] ?? a['message'] ?? '').toString().trim();
    final targetRole = (a['target_role'] ?? 'ALL').toString().toUpperCase();
    final isActive = a['is_active'] == true;
    final priority = (a['priority'] ?? a['announcement_type'] ?? 'NORMAL').toString().toUpperCase();
    final dateStr = a['created_at'] as String?;

    String formattedDate = 'الآن';
    if (dateStr != null) {
      try {
        final dt = DateTime.parse(dateStr).toLocal();
        formattedDate = intl.DateFormat('yyyy/MM/dd - hh:mm a').format(dt);
      } catch (_) {}
    }

    // Dynamic Theming based on Priority
    Color themeColor = AdminColors.primaryDark;
    IconData themeIcon = Icons.campaign_rounded;
    String priorityLabel = 'تنبيه عام 📢';

    if (priority == 'URGENT') {
      themeColor = const Color(0xFFEF4444);
      themeIcon = Icons.bolt_rounded;
      priorityLabel = 'عاجل وفوري ⚡';
    } else if (priority == 'MAINTENANCE') {
      themeColor = const Color(0xFFF59E0B);
      themeIcon = Icons.build_rounded;
      priorityLabel = 'صيانة خوادم 🛠️';
    } else if (priority == 'OFFER') {
      themeColor = const Color(0xFF8B5CF6);
      themeIcon = Icons.card_giftcard_rounded;
      priorityLabel = 'عرض وخصم 🎁';
    }

    // Friendly Role Label
    String roleLabel = 'كافة المنظومة (مرضى، أطباء، صيدليات) 🌐';
    if (targetRole == 'DOCTOR') {
       roleLabel = 'الأطباء والعيادات فقط 🩺';
    } else if (targetRole == 'PHARMACY') {
       roleLabel = 'الصيدليات فقط 💊';
    } else if (targetRole == 'PATIENT') {
       roleLabel = 'المرضى فقط 👥';
    } else if (targetRole == 'DOCTORS_EXPIRING') {
       roleLabel = 'أطباء ينتهي اشتراكهم قريباً ⏳🩺';
    } else if (targetRole == 'PHARMACIES_EXPIRING') {
       roleLabel = 'صيدليات ينتهي اشتراكها قريباً ⏳💊';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? themeColor.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(themeIcon, color: themeColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Target Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AdminColors.primaryDark.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'المستهدف: $roleLabel',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AdminColors.primaryDark,
                            ),
                          ),
                        ),

                        // Priority Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            priorityLabel,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                        ),

                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive ? AdminColors.accentMintLight : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isActive ? 'نشط ويبث حالياً 🟢' : 'موقوف مؤقتاً ⏸️',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isActive ? AdminColors.success : Colors.grey.shade700,
                            ),
                          ),
                        ),

                        // Date
                        Text(
                          '📅 $formattedDate',
                          style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions Row
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isActive ? 'إيقاف البث مؤقتاً' : 'استئناف البث',
                    icon: Icon(
                      isActive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                      color: isActive ? Colors.orange : AdminColors.success,
                      size: 22,
                    ),
                    onPressed: () => _toggleAnnouncementStatus(id, isActive),
                  ),
                  IconButton(
                    tooltip: 'حذف الإعلان',
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    onPressed: () => _deleteAnnouncement(id, title),
                  ),
                ],
              ),
            ],
          ),

          // Message / Content Box
          if (content.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                content,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  height: 1.6,
                  color: const Color(0xFF334155),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.textSecondary,
                  ),
                ),
                Text(
                  '$count',
                  style: GoogleFonts.cairo(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AdminColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10.5,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
