import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/core/widgets/create_admin_dialog.dart';

class AuditSecurityScreen extends StatefulWidget {
  const AuditSecurityScreen({super.key});

  @override
  State<AuditSecurityScreen> createState() => _AuditSecurityScreenState();
}

class _AuditSecurityScreenState extends State<AuditSecurityScreen> {
  final _client = AdminSupabaseConfig.client;
  final _realtimeManager = AdminRealtimeManager();

  static List<Map<String, dynamic>>? _cachedLogs;

  bool _isLoading = true;
  List<Map<String, dynamic>> _auditLogs = [];
  int _selectedTabIndex = 0; // 0: ALL, 1: APPROV, 2: SUBS, 3: QUEUE, 4: BLOCKED
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    if (_cachedLogs != null && _cachedLogs!.isNotEmpty) {
      _auditLogs = _cachedLogs!;
      _isLoading = false;
    }

    _fetchAuditLogs(silent: _cachedLogs != null);
    _realtimeManager.addAuditListener(_onRealtimeAudit);
  }

  @override
  void dispose() {
    _realtimeManager.removeAuditListener(_onRealtimeAudit);
    super.dispose();
  }

  void _onRealtimeAudit() {
    if (mounted) {
      _fetchAuditLogs(silent: true);
    }
  }

  Future<void> _fetchAuditLogs({bool silent = false}) async {
    if (!silent && _auditLogs.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final res = await _client
          .from('admin_audit_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      final list = List<Map<String, dynamic>>.from(res as List);

      if (mounted) {
        setState(() {
          _auditLogs = list;
          _cachedLogs = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching audit logs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'غير محدد';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final diff = DateTime.now().difference(dt);

      if (diff.inMinutes < 1) {
        return 'الآن (بث حي)';
      } else if (diff.inMinutes < 60) {
        return 'منذ ${diff.inMinutes} دقيقة';
      } else if (diff.inHours < 24) {
        return 'منذ ${diff.inHours} ساعة';
      } else {
        return intl.DateFormat('yyyy/MM/dd - hh:mm a').format(dt);
      }
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalCount = _auditLogs.length;
    int approvCount = 0;
    int subsCount = 0;
    int queueCount = 0;
    int blockedCount = 0;

    for (final log in _auditLogs) {
      final action = (log['action_type'] as String? ?? '').toLowerCase();
      final targetType = (log['target_type'] as String? ?? '').toUpperCase();
      final status = (log['status'] as String? ?? '').toUpperCase();
      if (action.contains('اعتماد') || action.contains('توثيق') || targetType == 'DOCTOR' || targetType == 'PHARMACY') {
        approvCount++;
      }
      if (targetType == 'SUBSCRIPTION' || action.contains('اشتراك') || action.contains('سداد')) {
        subsCount++;
      }
      if (targetType.contains('BRANCH') || action.contains('طابور') || action.contains('حجز')) {
        queueCount++;
      }
      if (status == 'BLOCKED' || status == 'REJECTED' || action.contains('رفض') || action.contains('حظر')) {
        blockedCount++;
      }
    }

    final filtered = _auditLogs.where((log) {
      final action = (log['action_type'] as String? ?? '').toLowerCase();
      final target = (log['target_name'] as String? ?? '').toLowerCase();
      final admin = (log['admin_name'] as String? ?? '').toLowerCase();
      final targetType = (log['target_type'] as String? ?? '').toUpperCase();
      final status = (log['status'] as String? ?? '').toUpperCase();

      bool matchesType = true;
      if (_selectedTabIndex == 1) {
        matchesType = action.contains('اعتماد') || action.contains('توثيق') || targetType == 'DOCTOR' || targetType == 'PHARMACY';
      } else if (_selectedTabIndex == 2) {
        matchesType = targetType == 'SUBSCRIPTION' || action.contains('اشتراك') || action.contains('سداد');
      } else if (_selectedTabIndex == 3) {
        matchesType = targetType.contains('BRANCH') || action.contains('طابور') || action.contains('حجز');
      } else if (_selectedTabIndex == 4) {
        matchesType = status == 'BLOCKED' || status == 'REJECTED' || action.contains('رفض') || action.contains('حظر');
      }

      bool matchesSearch = true;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        matchesSearch = action.contains(q) || target.contains(q) || admin.contains(q);
      }

      return matchesType && matchesSearch;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AdminColors.primaryDark.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shield_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'مركز الأمان وسجل العمليات الرقابية الحي (Audit Trail)',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'سجل رقابي مشفر غير قابل للتعديل لكل حركة إدارية وتغيير في المنظومة مع رصد العمليات في التو واللحظة',
                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AdminColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AdminColors.success, size: 16),
                        const SizedBox(width: 6),
                        Text('درع الرقابة نشط 🛡️', style: GoogleFonts.cairo(color: AdminColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => showCreateAdminAccountDialog(
                      context,
                      onAdminCreated: () => _fetchAuditLogs(silent: true),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'إنشاء حساب مسؤول جديد ➕',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'تحديث السجل الآن',
                    icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                    onPressed: () => _fetchAuditLogs(),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // كروت المؤشرات العلوية (KPI Metric Summary Cards)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'إجمالي السجلات',
                  count: totalCount,
                  subtitle: 'عمليات موثقة ومؤرشفة',
                  icon: Icons.shield_rounded,
                  color: AdminColors.primaryDark,
                  bgColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'اعتمادات وتوثيق 📋',
                  count: approvCount,
                  subtitle: 'تراخيص وهوية الأطباء والصيادلة',
                  icon: Icons.verified_user_rounded,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'سداد واشتراكات 💳',
                  count: subsCount,
                  subtitle: 'إيصالات واعتماد المدفوعات',
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF0EA5E9),
                  bgColor: const Color(0xFFF0F9FF),
                  borderColor: const Color(0xFFBAE6FD),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'حظر ورفض 🛑',
                  count: blockedCount,
                  subtitle: 'قرارات إدارية رقابية مشددة',
                  icon: Icons.block_rounded,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFECACA),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Filters and Search Bar
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: TextField(
                    style: GoogleFonts.cairo(fontSize: 13),
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: '🔍 ابحث في سجل العمليات باسم المشرف، الإجراء، أو الطرف المستهدف...',
                      hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.primaryDark),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // تابات الحالة العصرية (Segmented Modern Tab Bar)
          AdminModernTabBar(
            tabs: [
              AdminTabItem(label: 'الكل', icon: Icons.all_inbox_rounded, count: totalCount),
              AdminTabItem(label: 'الاعتمادات 📋', icon: Icons.verified_user_rounded, count: approvCount, badgeColor: const Color(0xFF10B981)),
              AdminTabItem(label: 'الاشتراكات 💳', icon: Icons.payments_rounded, count: subsCount, badgeColor: const Color(0xFF0EA5E9)),
              AdminTabItem(label: 'الطوابير 🏥', icon: Icons.radar_rounded, count: queueCount, badgeColor: const Color(0xFFF59E0B)),
              AdminTabItem(label: 'الرفض والحظر 🛑', icon: Icons.block_rounded, count: blockedCount, badgeColor: const Color(0xFFEF4444)),
            ],
            selectedIndex: _selectedTabIndex,
            onTabSelected: (idx) => setState(() => _selectedTabIndex = idx),
          ),

          const SizedBox(height: 16),

          // Audit Logs List
          if (_isLoading && _auditLogs.isEmpty)
            const AdminTableSkeleton(rows: 8)
          else if (filtered.isEmpty)
            AdminEmptyStateCard(
              title: _searchQuery.isNotEmpty
                  ? 'لا توجد سجلات رقابية مطابقة لبحث "$_searchQuery"'
                  : 'لا توجد سجلات رقابية في هذا القسم',
              description: _searchQuery.isNotEmpty
                  ? 'تأكد من كتابة الكلمات الدلالية بشكل صحيح، أو اختر تصنيفاً آخر.'
                  : 'جميع الحركات الإدارية والرقابية في المنظومة تدون هنا بشكل مشفر ولحظي.',
              icon: Icons.security_rounded,
              onRefresh: _fetchAuditLogs,
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                          final log = filtered[index];
                          final status = (log['status'] as String? ?? 'SUCCESS').toUpperCase();
                          final isBlocked = status == 'BLOCKED' || status == 'REJECTED';
                          final action = log['action_type'] as String? ?? 'إجراء إداري';
                          final target = log['target_name'] as String? ?? '';
                          final admin = log['admin_name'] as String? ?? 'أدمن المنظومة';
                          final ip = log['ip_address'] as String? ?? 'Web Console';
                          final timeStr = _formatTimestamp(log['created_at'] as String?);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AdminColors.surfaceWhite,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isBlocked
                                    ? AdminColors.emergency.withValues(alpha: 0.3)
                                    : AdminColors.cardBorderMint,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
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
                                    color: (isBlocked ? AdminColors.emergency : AdminColors.primaryDark)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isBlocked ? Icons.block_rounded : Icons.history_edu_rounded,
                                    color: isBlocked ? AdminColors.emergency : AdminColors.primaryDark,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(action, style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13.5)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AdminColors.primaryDark.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(admin, style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.primaryDark, fontWeight: FontWeight.bold)),
                                          ),
                                          const Spacer(),
                                          Text(timeStr, style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(target, style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textPrimary, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text('المصدر: $ip • الحالة: ${isBlocked ? "مرفوض / محظور" : "تم بنجاح ✅"}',
                                          style: GoogleFonts.cairo(fontSize: 11, color: isBlocked ? AdminColors.emergency : AdminColors.success)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          const SizedBox(height: 32),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.04),
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
            child: Icon(icon, color: color, size: 22),
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
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      '$count',
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AdminColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        count > 0 ? 'نشط' : '0',
                        style: GoogleFonts.cairo(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
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
