import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';

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
  String _selectedFilter = 'ALL';
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
    final filtered = _auditLogs.where((log) {
      final action = (log['action_type'] as String? ?? '').toLowerCase();
      final target = (log['target_name'] as String? ?? '').toLowerCase();
      final admin = (log['admin_name'] as String? ?? '').toLowerCase();
      final targetType = (log['target_type'] as String? ?? '').toUpperCase();
      final status = (log['status'] as String? ?? '').toUpperCase();

      // Filter by type
      bool matchesType = true;
      if (_selectedFilter == 'APPROV') {
        matchesType = action.contains('اعتماد') || action.contains('توثيق') || targetType == 'DOCTOR' || targetType == 'PHARMACY';
      } else if (_selectedFilter == 'SUBS') {
        matchesType = targetType == 'SUBSCRIPTION' || action.contains('اشتراك') || action.contains('سداد');
      } else if (_selectedFilter == 'QUEUE') {
        matchesType = targetType.contains('BRANCH') || action.contains('طابور') || action.contains('حجز');
      } else if (_selectedFilter == 'BLOCKED') {
        matchesType = status == 'BLOCKED' || status == 'REJECTED' || action.contains('رفض') || action.contains('حظر');
      }

      // Filter by search
      bool matchesSearch = true;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        matchesSearch = action.contains(q) || target.contains(q) || admin.contains(q);
      }

      return matchesType && matchesSearch;
    }).toList();

    return Padding(
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
                  IconButton(
                    tooltip: 'تحديث السجل الآن',
                    icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                    onPressed: () => _fetchAuditLogs(),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Filters and Search Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  style: GoogleFonts.cairo(fontSize: 13),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: '🔍 ابحث في سجل العمليات باسم المشرف، الإجراء، أو الطرف المستهدف...',
                    hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                    filled: true,
                    fillColor: AdminColors.surfaceWhite,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.primaryDark),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildFilterChip('الكل 🌐', 'ALL'),
              const SizedBox(width: 6),
              _buildFilterChip('الاعتمادات 📋', 'APPROV'),
              const SizedBox(width: 6),
              _buildFilterChip('الاشتراكات 💳', 'SUBS'),
              const SizedBox(width: 6),
              _buildFilterChip('الطوابير 🏥', 'QUEUE'),
              const SizedBox(width: 6),
              _buildFilterChip('الرفض والحظر 🛑', 'BLOCKED'),
            ],
          ),

          const SizedBox(height: 16),

          // Audit Logs List
          Expanded(
            child: _isLoading && _auditLogs.isEmpty
                ? const SingleChildScrollView(child: AdminTableSkeleton(rows: 8))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.verified_user_outlined, size: 48, color: AdminColors.textSecondary),
                            const SizedBox(height: 10),
                            Text('لا توجد سجلات رقابية مطابقة للبحث', style: GoogleFonts.cairo(fontSize: 14, color: AdminColors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.builder(
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
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterKey) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primaryDark : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AdminColors.primaryDark : AdminColors.cardBorderMint),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : AdminColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
