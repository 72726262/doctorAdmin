import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/features/queue_war_room/presentation/screens/queue_war_room_screen.dart';
import 'package:doctor_admin/features/doctors_governance/presentation/screens/doctors_governance_screen.dart';
import 'package:doctor_admin/features/pharmacies_governance/presentation/screens/pharmacies_governance_screen.dart';
import 'package:doctor_admin/features/approvals/presentation/screens/pending_approvals_screen.dart';
import 'package:doctor_admin/features/subscriptions/presentation/screens/subscription_requests_screen.dart';
import 'package:doctor_admin/features/announcements/presentation/screens/announcements_screen.dart';
import 'package:doctor_admin/features/audit_security/presentation/screens/audit_security_screen.dart';
import 'package:doctor_admin/features/analytics/presentation/screens/analytics_bi_screen.dart';
import 'package:doctor_admin/features/settings/presentation/screens/admin_settings_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTabIndex = 0;

  final List<String> _tabTitles = [
    'نظرة عامة ومؤشرات المنصة',
    'غرفة العمليات ورادار الطوابير اللحظي',
    'حوكمة وإدارة الأطباء والعيادات',
    'رقابة الصيدليات وتداول الروشتات',
    'طلبات الاعتماد والانضمام الجديدة',
    'إيصالات واشتراكات الأطباء',
    'الإذاعة والتنبيهات الجغرافية',
    'الأمان ومكافحة الاحتيال وسجل العمليات',
    'التحليلات الاستراتيجية والخرائط الحرارية',
    'طرق السداد وإعدادات النظام',
  ];

  @override
  Widget build(BuildContext context) {
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
                        ),
                        child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'شفاء | الإدارة العليا',
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
                                color: AdminColors.accentMintLight,
                                fontSize: 10.5,
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
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    children: [
                      _buildSidebarItem(0, 'نظرة عامة وإحصائيات', Icons.dashboard_rounded),
                      _buildSidebarItem(1, 'رادار الطوابير اللحظي', Icons.radar_rounded, isUrgent: true),
                      _buildSidebarItem(2, 'حوكمة الأطباء والعيادات', Icons.medical_services_rounded),
                      _buildSidebarItem(3, 'رقابة الصيدليات', Icons.local_pharmacy_rounded),
                      _buildSidebarItem(4, 'طلبات الاعتماد', Icons.verified_user_rounded, badgeCount: 2),
                      _buildSidebarItem(5, 'الاشتراكات والإيصالات', Icons.receipt_long_rounded),
                      _buildSidebarItem(6, 'الإذاعة والتنبيهات', Icons.campaign_rounded),
                      _buildSidebarItem(7, 'سجل العمليات والأمان', Icons.shield_rounded),
                      _buildSidebarItem(8, 'تحليلات الخرائط BI', Icons.analytics_rounded),
                      _buildSidebarItem(9, 'إعدادات المنظومة', Icons.settings_rounded),
                    ],
                  ),
                ),

                // Footer Info
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_person_rounded, color: AdminColors.accentMint, size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Super Admin Session Active',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AdminColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AdminColors.accentMintLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: AdminColors.success, size: 8),
                                SizedBox(width: 6),
                                Text(
                                  'الرادار متصل بالسحابة 🟢',
                                  style: TextStyle(
                                    color: AdminColors.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
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
                      const PharmaciesGovernanceScreen(),
                      const PendingApprovalsScreen(),
                      const SubscriptionRequestsScreen(),
                      const AnnouncementsScreen(),
                      const AuditSecurityScreen(),
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
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        trailing: badgeCount != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminColors.emergency,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildOverviewTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchPlatformStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark));
        }

        final stats = snapshot.data ?? {};

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // كروت المؤشرات الإحصائية الأربعة في شبكة متجاوبة
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: _buildMetricCard('إجمالي المرضى', '${stats['patients'] ?? 0}', Icons.people_alt_rounded, AdminColors.primaryDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildMetricCard('الأطباء المعتمدين', '${stats['doctors'] ?? 0}', Icons.medical_services_rounded, AdminColors.accentCyan)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildMetricCard('الصيدليات المسجلة', '${stats['pharmacies'] ?? 0}', Icons.local_pharmacy_rounded, AdminColors.accentMint)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildMetricCard('تذاكر الكشوفات', '${stats['tickets'] ?? 0}', Icons.confirmation_number_rounded, AdminColors.warning)),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildMetricCard('إجمالي المرضى', '${stats['patients'] ?? 0}', Icons.people_alt_rounded, AdminColors.primaryDark)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildMetricCard('الأطباء المعتمدين', '${stats['doctors'] ?? 0}', Icons.medical_services_rounded, AdminColors.accentCyan)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _buildMetricCard('الصيدليات المسجلة', '${stats['pharmacies'] ?? 0}', Icons.local_pharmacy_rounded, AdminColors.accentMint)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildMetricCard('تذاكر الكشوفات', '${stats['tickets'] ?? 0}', Icons.confirmation_number_rounded, AdminColors.warning)),
                        ],
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // روابط العمليات السريعة
              const Text(
                'مراكز السيطرة والتدخل السريع:',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
              ),
              const SizedBox(height: 12),

              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  final item1 = InkWell(
                    onTap: () => setState(() => _selectedTabIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminColors.surfaceWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AdminColors.emergency.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.radar_rounded, color: AdminColors.emergency, size: 26),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('رادار وغرفة عمليات الطوابير اللحظية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                Text('متابعة كثافة المرضى والتدخل في حالات التكدس والطوارئ', style: TextStyle(fontSize: 11.5, color: AdminColors.textSecondary)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AdminColors.textMuted),
                        ],
                      ),
                    ),
                  );

                  final item2 = InkWell(
                    onTap: () => setState(() => _selectedTabIndex = 5),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminColors.surfaceWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AdminColors.cardBorderMint),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.payments_rounded, color: AdminColors.success, size: 26),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('فحص إيصالات الاشتراكات والمدفوعات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                Text('تأكيد سداد فودافون كاش وتفعيل باقات العيادات', style: TextStyle(fontSize: 11.5, color: AdminColors.textSecondary)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AdminColors.textMuted),
                        ],
                      ),
                    ),
                  );

                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: item1),
                        const SizedBox(width: 12),
                        Expanded(child: item2),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      item1,
                      const SizedBox(height: 10),
                      item2,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.cardBorderMint),
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
                  style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
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
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchPlatformStats() async {
    final client = AdminSupabaseConfig.client;

    try {
      final patientsCount = await client.from('profiles').select('id').eq('role', 'PATIENT');
      final doctorsCount = await client.from('doctors').select('id');
      final pharmaciesCount = await client.from('pharmacies').select('id');
      final ticketsCount = await client.from('tickets').select('id');

      return {
        'patients': (patientsCount as List).length,
        'doctors': (doctorsCount as List).length,
        'pharmacies': (pharmaciesCount as List).length,
        'tickets': (ticketsCount as List).length,
      };
    } catch (e) {
      return {'patients': 0, 'doctors': 0, 'pharmacies': 0, 'tickets': 0};
    }
  }
}
