import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/features/queue_war_room/presentation/screens/queue_war_room_screen.dart';
import 'package:doctor_admin/features/doctors_governance/presentation/screens/doctors_governance_screen.dart';
import 'package:doctor_admin/features/doctor_ratings/presentation/screens/doctor_ratings_screen.dart';
import 'package:doctor_admin/features/pharmacies_governance/presentation/screens/pharmacies_governance_screen.dart';
import 'package:doctor_admin/features/approvals/presentation/screens/pending_approvals_screen.dart';
import 'package:doctor_admin/features/subscriptions/presentation/screens/subscription_requests_screen.dart';
import 'package:doctor_admin/features/announcements/presentation/screens/announcements_screen.dart';
import 'package:doctor_admin/features/announcements/presentation/screens/promotional_ads_screen.dart';
import 'package:doctor_admin/features/audit_security/presentation/screens/audit_security_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doctor_admin/features/auth/presentation/screens/admin_login_screen.dart';
import 'package:doctor_admin/features/analytics/presentation/screens/analytics_bi_screen.dart';
import 'package:doctor_admin/features/settings/presentation/screens/admin_settings_screen.dart';
import 'package:doctor_admin/features/admin_management/presentation/screens/admin_management_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTabIndex = 0;
  final _realtimeManager = AdminRealtimeManager();

  // ذاكرة الكاش اللحظية لمنع وميض التحميل (Cache-First)
  static Map<String, dynamic>? _cachedStats;
  bool _isLoadingStats = false;
  String _latestActivity = 'الرادار اللحظي متصل بالسيرفر وجاهز لرصد العمليات 🟢';

  final List<String> _tabTitles = [
    'نظرة عامة ومؤشرات المنصة',
    'غرفة العمليات ورادار الطوابير اللحظي',
    'حوكمة وإدارة الأطباء والعيادات',
    'إدارة تقييمات الأطباء والموصى بهم ⭐',
    'رقابة الصيدليات وتداول الروشتات',
    'طلبات الاعتماد والانضمام الجديدة',
    'إيصالات واشتراكات الأطباء',
    'إدارة الإعلانات والبنرات الممولة 📢',
    'الإذاعة والتنبيهات العامة وإشعارات المنظومة',
    'الأمان ومكافحة الاحتيال وسجل العمليات',
    'إدارة وحوكمة فريق المشرفين 👥',
    'التحليلات الاستراتيجية والخرائط الحرارية',
    'طرق السداد وإعدادات النظام',
  ];

  @override
  void initState() {
    super.initState();
    // 1. تفعيل محرك الريل تايم المركزي
    _realtimeManager.initialize();

    // 2. الاستماع لتحديث الإحصائيات في الخلفية تلقائياً
    _realtimeManager.addTicketListener(_fetchStatsSilently);
    _realtimeManager.addPartnerListener(_fetchStatsSilently);
    _realtimeManager.addSubscriptionListener(_fetchStatsSilently);
    _realtimeManager.addBranchListener(_fetchStatsSilently);

    // 3. الاستماع لشريط البث المباشر
    _realtimeManager.activityStream.listen((msg) {
      if (mounted) {
        setState(() => _latestActivity = msg);
      }
    });

    // 4. جلب البيانات اللحظية
    _fetchStats();
  }

  @override
  void dispose() {
    _realtimeManager.removeTicketListener(_fetchStatsSilently);
    _realtimeManager.removePartnerListener(_fetchStatsSilently);
    _realtimeManager.removeSubscriptionListener(_fetchStatsSilently);
    _realtimeManager.removeBranchListener(_fetchStatsSilently);
    super.dispose();
  }

  Future<void> _fetchStats() async {
    if (_cachedStats == null) {
      setState(() => _isLoadingStats = true);
    }
    await _fetchStatsSilently();
    if (mounted) {
      setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _fetchStatsSilently() async {
    try {
      final client = AdminSupabaseConfig.client;
      final res = await client.rpc('get_admin_dashboard_live_kpis');
      if (mounted && res != null) {
        setState(() {
          _cachedStats = Map<String, dynamic>.from(res as Map);
        });
      }
    } catch (e) {
      debugPrint('Error fetching admin live KPIs: $e');
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_admin_logged_in');
    try {
      await AdminSupabaseConfig.client.auth.signOut();
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AdminLoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingApprovalsCount = _cachedStats?['pending_approvals'] as int? ?? 0;
    final pendingSubsCount = _cachedStats?['pending_subscriptions'] as int? ?? 0;

    return Scaffold(
      backgroundColor: AdminColors.backgroundCanvas,
      body: Row(
        children: [
          // 1. القائمة الجانبية الفاخرة (Sidebar)
          Container(
            width: 260,
            color: AdminColors.sidebarDark,
            child: Column(
              children: [
                // Logo & Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AdminColors.primaryMain,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: AdminColors.accentMint.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'كشفك | الإدارة العليا',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            Text(
                              'مركز القيادة والتحكم الشامل',
                              style: TextStyle(
                                color: AdminColors.accentMint,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white12, height: 1),

                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    children: [
                      _buildSidebarItem(0, 'نظرة عامة ومؤشرات المنصة', Icons.dashboard_rounded),
                      _buildSidebarItem(1, 'غرفة العمليات ورادار الطوابير 📡', Icons.radar_rounded),
                      _buildSidebarItem(2, 'حوكمة الأطباء والعيادات', Icons.medical_services_rounded),
                      _buildSidebarItem(3, 'إدارة تقييمات الأطباء والموصى بهم ⭐', Icons.stars_rounded),
                      _buildSidebarItem(4, 'رقابة الصيدليات وتداول الروشتات', Icons.local_pharmacy_rounded),
                      _buildSidebarItem(
                        5,
                        'طلبات الاعتماد والانضمام',
                        Icons.verified_user_rounded,
                        badgeCount: pendingApprovalsCount > 0 ? pendingApprovalsCount : null,
                        isUrgent: pendingApprovalsCount > 0,
                      ),
                      _buildSidebarItem(
                        6,
                        'إيصالات واشتراكات الأطباء',
                        Icons.receipt_long_rounded,
                        badgeCount: pendingSubsCount > 0 ? pendingSubsCount : null,
                        isUrgent: pendingSubsCount > 0,
                      ),
                      _buildSidebarItem(7, 'إدارة الإعلانات والترويج 📢', Icons.campaign_rounded),
                      _buildSidebarItem(8, 'الإذاعة والتنبيهات العامة', Icons.notifications_active_rounded),
                      _buildSidebarItem(9, 'الأمان وسجل العمليات 🛡️', Icons.security_rounded),
                      _buildSidebarItem(10, 'فريق المشرفين والمسؤولين 👥', Icons.admin_panel_settings_rounded),
                      _buildSidebarItem(11, 'التحليلات الاستراتيجية BI', Icons.insights_rounded),
                      _buildSidebarItem(12, 'طرق السداد وإعدادات النظام', Icons.settings_rounded),
                    ],
                  ),
                ),

                const Divider(color: Colors.white12, height: 1),

                // Admin Footer Info & Logout
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: AdminColors.accentMint,
                        child: Icon(Icons.shield_rounded, color: Colors.black87, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('أدمن المنظومة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            Text('مسؤول عام معتمد', style: TextStyle(color: Colors.white60, fontSize: 10)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'تسجيل الخروج',
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                        onPressed: () => _handleLogout(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. مساحة المحتوى الرئيسية
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceWhite,
                    border: Border(bottom: BorderSide(color: AdminColors.cardBorder)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _tabTitles[_selectedTabIndex],
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AdminColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // شارة التحديث اللحظي النشط
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AdminColors.accentMintLight,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AdminColors.success.withValues(alpha: 0.2)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: AdminColors.success, size: 8),
                                SizedBox(width: 6),
                                Text(
                                  'تحديث لحظي نشط 🟢',
                                  style: TextStyle(
                                    color: AdminColors.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark, size: 20),
                            tooltip: 'تحديث البيانات فوراً',
                            onPressed: _fetchStats,
                          ),
                          const SizedBox(width: 8),
                          const CircleAvatar(
                            radius: 16,
                            backgroundColor: AdminColors.primaryDark,
                            child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Body Content
                Expanded(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: [
                      _buildOverviewTab(),
                      const QueueWarRoomScreen(),
                      const DoctorsGovernanceScreen(),
                      const DoctorRatingsScreen(),
                      const PharmaciesGovernanceScreen(),
                      const PendingApprovalsScreen(),
                      const SubscriptionRequestsScreen(),
                      const PromotionalAdsScreen(),
                      const AnnouncementsScreen(),
                      const AuditSecurityScreen(),
                      const AdminManagementScreen(),
                      const AnalyticsBiScreen(),
                      const AdminSettingsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, String title, IconData icon, {int? badgeCount, bool isUrgent = false}) {
    final isSelected = _selectedTabIndex == index;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      child: ListTile(
        dense: true,
        onTap: () => setState(() => _selectedTabIndex = index),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: isSelected ? AdminColors.sidebarActive : Colors.transparent,
        leading: Icon(
          icon,
          color: isSelected
              ? AdminColors.accentMint
              : isUrgent
                  ? AdminColors.emergency
                  : Colors.white70,
          size: 19,
        ),
        title: Text(
          title,
          style: GoogleFonts.cairo(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing: badgeCount != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminColors.emergency,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900),
                ),
              )
            : null,
      ),
    );
  }

  /// 🌟 شاشة النظرة العامة المطورة وغرفة القيادة السحابية (Zero Spinner + Cache First)
  Widget _buildOverviewTab() {
    if (_isLoadingStats && _cachedStats == null) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Column(
          children: [
            AdminStatSkeleton(count: 4),
            SizedBox(height: 20),
            AdminStatSkeleton(count: 4),
          ],
        ),
      );
    }

    final stats = _cachedStats ?? {};
    final totalPatients = stats['total_patients'] ?? 0;
    final totalDoctors = stats['total_doctors'] ?? 0;
    final totalPharmacies = stats['total_pharmacies'] ?? 0;
    final totalTickets = stats['total_tickets'] ?? 0;
    final todayTickets = stats['today_tickets'] ?? 0;
    final activeQueues = stats['active_queues'] ?? 0;
    final inSessionNow = stats['in_session_now'] ?? 0;
    final pendingApprovals = stats['pending_approvals'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. شريط البث المباشر لعمليات المنظومة (Live Activity Ticker)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F2E28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.accentMint.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AdminColors.accentMint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'بث مباشر ⚡',
                    style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _latestActivity,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. كروت مؤشرات الأداء الحية لليوم (Today's Live Pulse)
          Text(
            'مؤشرات المنظومة في هذه اللحظة (Live Pulse):',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 10),

          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final cardWidth = isWide
                  ? (constraints.maxWidth - (3 * 14)) / 4
                  : (constraints.maxWidth - 14) / 2;

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'كشوفات جارية الآن',
                      '$inSessionNow كشف',
                      Icons.sensors_rounded,
                      const Color(0xFF10B981),
                      subtitle: 'مرضى داخل غرف الأطباء حالياً',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'عيادات نشطة الآن',
                      '$activeQueues عيادة',
                      Icons.storefront_rounded,
                      AdminColors.primaryDark,
                      subtitle: 'طوابير مفتوحة وتستقبل مرضى',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'كشوفات اليوم',
                      '$todayTickets تذكرة',
                      Icons.today_rounded,
                      const Color(0xFF0284C7),
                      subtitle: 'إجمالي الحجوزات المسجلة اليوم',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'طلبات بانتظار الاعتماد',
                      '$pendingApprovals طلب',
                      Icons.pending_actions_rounded,
                      pendingApprovals > 0 ? AdminColors.emergency : AdminColors.warning,
                      subtitle: 'تراخيص أطباء وصيدليات جديدة',
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // 4. كروت إجمالي المنظومة العامة
          Text(
            'الحجم الإجمالي للمنصة التراكمي:',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 10),

          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final cardWidth = isWide
                  ? (constraints.maxWidth - (3 * 14)) / 4
                  : (constraints.maxWidth - 14) / 2;

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'إجمالي المرضى المسجلين',
                      '$totalPatients',
                      Icons.people_alt_rounded,
                      AdminColors.primaryMain,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'الأطباء والاستشاريين',
                      '$totalDoctors',
                      Icons.medical_services_rounded,
                      AdminColors.accentCyan,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'الصيدليات المعتمدة',
                      '$totalPharmacies',
                      Icons.local_pharmacy_rounded,
                      Colors.teal,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildMetricCard(
                      'إجمالي الكشوفات المنفذة',
                      '$totalTickets',
                      Icons.confirmation_num_rounded,
                      Colors.indigo,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 28),

          // 5. روابط التحكم والعمليات السريعة
          Text(
            'إجراءات التدخل والرقابة السريعة:',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildActionBanner(
                  title: 'رادار الطوابير وغرفة العمليات اللحظية 📡',
                  subtitle: 'مراقبة العيادات المزدحمة وتصريف الضغط بالتدخل المباشر',
                  icon: Icons.radar_rounded,
                  color: AdminColors.primaryDark,
                  onTap: () => setState(() => _selectedTabIndex = 1),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildActionBanner(
                  title: 'فحص التراخيص والطلبات الجديدة 📋',
                  subtitle: 'اعتماد رخص مزاولة المهنة وكارنيهات النقابة الطبية',
                  icon: Icons.verified_user_rounded,
                  color: const Color(0xFF0F766E),
                  onTap: () => setState(() => _selectedTabIndex = 5),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildActionBanner(
                  title: 'مراجعة إيصالات باقات الاشتراكات 💳',
                  subtitle: 'تأكيد تحويلات فودافون كاش وتفعيل حسابات الأطباء',
                  icon: Icons.receipt_long_rounded,
                  color: Colors.indigo,
                  onTap: () => setState(() => _selectedTabIndex = 6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AdminColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.cairo(fontSize: 10, color: AdminColors.textMuted, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionBanner({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminColors.surfaceWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AdminColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13, color: AdminColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AdminColors.textMuted),
          ],
        ),
      ),
    );
  }
}
