import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class DoctorsGovernanceScreen extends StatefulWidget {
  const DoctorsGovernanceScreen({super.key});

  @override
  State<DoctorsGovernanceScreen> createState() => _DoctorsGovernanceScreenState();
}

class _DoctorsGovernanceScreenState extends State<DoctorsGovernanceScreen> {
  final _client = AdminSupabaseConfig.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _doctors = [];
  String _searchQuery = '';
  String _governorateFilter = 'الكل';
  String _statusFilter = 'الكل';

  @override
  void initState() {
    super.initState();
    _fetchDoctors();
  }

  Future<void> _fetchDoctors() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.from('doctors').select('''
        id,
        specialty,
        bio,
        rating_avg,
        rating_count,
        subscription_status,
        subscription_expires_at,
        profiles (
          id,
          full_name,
          phone,
          governorate,
          avatar_url,
          is_approved
        ),
        branches (
          id,
          name,
          governorate,
          address_text,
          max_daily_capacity,
          is_queue_active
        )
      ''').order('rating_avg', ascending: false);

      if (mounted) {
        setState(() {
          _doctors = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDoctorApproval(String doctorId, bool currentStatus) async {
    try {
      await _client.rpc('admin_toggle_entity_approval', params: {
        'p_id': doctorId,
        'p_is_approved': !currentStatus,
      });

      await _client.from('profiles').update({'is_approved': !currentStatus}).eq('id', doctorId);
      await _client.from('doctors').update({
        'subscription_status': !currentStatus ? 'ACTIVE' : 'SUSPENDED'
      }).eq('id', doctorId);

      await _fetchDoctors();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? '🟢 تم تفعيل واعتماد حساب الطبيب بنجاح' : '⏸️ تم تجميد وإيقاف حساب الطبيب بنجاح'),
            backgroundColor: !currentStatus ? AdminColors.success : AdminColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    }
  }

  Future<void> _extendSubscription(String doctorId, int days) async {
    try {
      final newExpiry = DateTime.now().add(Duration(days: days)).toIso8601String();
      await _client.from('doctors').update({
        'subscription_status': 'ACTIVE',
        'subscription_expires_at': newExpiry,
      }).eq('id', doctorId);

      await _client.from('profiles').update({'is_approved': true}).eq('id', doctorId);

      await _fetchDoctors();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 تم تمديد اشتراك الطبيب لـ $days يوماً بنجاح!'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    }
  }

  void _showDoctorDetailsModal(Map<String, dynamic> doc) {
    final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
    final branches = (doc['branches'] as List?) ?? [];
    final isApproved = (profile['is_approved'] == true) && (doc['subscription_status'] != 'SUSPENDED' && doc['subscription_status'] != 'FROZEN');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Modal Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                      backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                          ? NetworkImage(profile['avatar_url'])
                          : null,
                      child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                          ? const Icon(Icons.person, color: AdminColors.primaryDark, size: 30)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                profile['full_name'] ?? 'طبيب المنظومة',
                                style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isApproved ? AdminColors.accentMintLight : Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isApproved ? 'معتمد 🟢' : 'مجمد / موقوف 🔴',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    color: isApproved ? AdminColors.success : AdminColors.emergency,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            doc['specialty'] ?? 'تخصص عام',
                            style: GoogleFonts.cairo(color: AdminColors.accentCyan, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '📞 ${profile['phone'] ?? 'غير متوفر'} | 📍 ${profile['governorate'] ?? 'مصر'}',
                            style: GoogleFonts.cairo(color: AdminColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),

                // Subscription Details
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminColors.backgroundCanvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdminColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('حالة اشتراك الطبيب في المنظومة:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('الباقة الشهرية (350 ج.م / شهر)', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: doc['subscription_status'] == 'ACTIVE' ? AdminColors.accentMintLight : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          doc['subscription_status'] == 'ACTIVE' ? 'اشتراك نشط ✅' : 'يحتاج تجديد ⏳',
                          style: GoogleFonts.cairo(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: doc['subscription_status'] == 'ACTIVE' ? AdminColors.primaryDark : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Bio
                Text('النبذة والخبرات:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  doc['bio'] != null && doc['bio'] != '' ? doc['bio'] : 'لا توجد نبذة مسجلة',
                  style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                ),
                const SizedBox(height: 18),

                // Branches List
                Text('فروع العيادات المسجلة (${branches.length} فروع):', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (branches.isEmpty)
                  Text('لا توجد فروع مسجلة لهذا الطبيب حالياً', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary))
                else
                  ...branches.map((b) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AdminColors.backgroundCanvas,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdminColors.cardBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b['name'] ?? 'الفرع', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('📍 ${b['governorate']} - ${b['address_text']}', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('السعة: ${b['max_daily_capacity'] ?? 30} كشف/يوم', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AdminColors.primaryDark, fontSize: 12)),
                                Text(b['is_queue_active'] == true ? 'الطابور نشط 🟢' : 'الطابور متوقف ⏸️', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      )),

                const SizedBox(height: 24),

                // Actions Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('إغلاق', style: GoogleFonts.cairo(color: AdminColors.textSecondary)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.accentCyan,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      label: Text('تمديد الاشتراك', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showExtendSubscriptionDialog(doc['id'], profile['full_name'] ?? 'الطبيب');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isApproved ? AdminColors.warning : AdminColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(isApproved ? Icons.pause_circle_rounded : Icons.check_circle_rounded, size: 18),
                      label: Text(isApproved ? 'تجميد الحساب' : 'تفعيل الحساب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _toggleDoctorApproval(doc['id'], isApproved);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExtendSubscriptionDialog(String docId, String doctorName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تمديد اشتراك: $doctorName', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: AdminColors.backgroundCanvas,
              title: Text('تمديد شهر (30 يوماً)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => _extendSubscription(docId, 30),
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: AdminColors.backgroundCanvas,
              title: Text('تمديد 3 أشهر (90 يوماً)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => _extendSubscription(docId, 90),
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: AdminColors.backgroundCanvas,
              title: Text('تمديد سنة كاملة (365 يوماً)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => _extendSubscription(docId, 365),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _doctors.where((d) {
      final profile = d['profiles'] as Map<String, dynamic>? ?? {};
      final name = profile['full_name']?.toString() ?? '';
      final specialty = d['specialty']?.toString() ?? '';
      final gov = profile['governorate']?.toString() ?? '';
      final isApproved = (profile['is_approved'] == true) &&
          (d['subscription_status'] != 'SUSPENDED' && d['subscription_status'] != 'FROZEN');

      final matchGov = _governorateFilter == 'الكل' || gov == _governorateFilter;
      final matchStatus = _statusFilter == 'الكل' ||
          (_statusFilter == 'معتمد' && isApproved) ||
          (_statusFilter == 'مجمد' && !isApproved);

      final matchSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery) ||
          specialty.contains(_searchQuery) ||
          gov.contains(_searchQuery);

      return matchGov && matchStatus && matchSearch;
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
                        child: const Icon(Icons.medical_services_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'مركز حوكمة وإدارة الأطباء والعيادات',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'التحكم الكامل في الأطباء المسجلين، فحص الفروع، تمديد الاشتراكات، والاعتماد والتجميد الفوري',
                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث القائمة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchDoctors,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Filters Bar
          Row(
            children: [
              // Search
              Expanded(
                child: TextField(
                  style: GoogleFonts.cairo(fontSize: 13),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'بحث باسم الطبيب، التخصص، أو المحافظة...',
                    hintStyle: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.textSecondary),
                    filled: true,
                    fillColor: AdminColors.surfaceWhite,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Governorate Filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AdminColors.surfaceWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AdminColors.cardBorder)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _governorateFilter,
                    style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    items: ['الكل', 'القاهرة', 'الجيزة', 'الإسكندرية', 'الدقهلية', 'الغربية', 'الشرقية', 'المنوفية', 'البحيرة'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (val) => setState(() => _governorateFilter = val ?? 'الكل'),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Status Filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AdminColors.surfaceWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AdminColors.cardBorder)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusFilter,
                    style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    items: ['الكل', 'معتمد', 'مجمد'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) => setState(() => _statusFilter = val ?? 'الكل'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Doctors Table / List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                : filtered.isEmpty
                    ? Center(child: Text('لا يوجد أطباء مطابقين للبحث', style: GoogleFonts.cairo(color: AdminColors.textSecondary)))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
                          final branches = (doc['branches'] as List?) ?? [];
                          final isApproved = (profile['is_approved'] == true) &&
                              (doc['subscription_status'] != 'SUSPENDED' && doc['subscription_status'] != 'FROZEN');

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AdminColors.surfaceWhite,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AdminColors.cardBorderMint),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                  backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                                      ? NetworkImage(profile['avatar_url'])
                                      : null,
                                  child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                                      ? const Icon(Icons.person, color: AdminColors.primaryDark)
                                      : null,
                                ),
                                const SizedBox(width: 14),

                                // Info
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            profile['full_name'] ?? 'طبيب المنظومة',
                                            style: GoogleFonts.cairo(fontSize: 14.5, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isApproved ? AdminColors.accentMintLight : Colors.red.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isApproved ? 'معتمد 🟢' : 'مجمد / موقوف 🔴',
                                              style: GoogleFonts.cairo(
                                                fontSize: 11,
                                                color: isApproved ? AdminColors.success : AdminColors.emergency,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${doc['specialty'] ?? 'تخصص عام'} • 📍 ${profile['governorate'] ?? 'مصر'} • 📞 ${profile['phone'] ?? 'بدون هاتف'}',
                                        style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),

                                // Branches Count
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('فروع العيادة:', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                                      Text('${branches.length} فروع مسجلة', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                                    ],
                                  ),
                                ),

                                // Subscription Status
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('اشتراك المنظومة:', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                                      Text(
                                        doc['subscription_status'] == 'ACTIVE' ? 'نشط (350 ج.م)' : 'يحتاج تجديد',
                                        style: GoogleFonts.cairo(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: doc['subscription_status'] == 'ACTIVE' ? AdminColors.success : AdminColors.warning,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Actions
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.visibility_rounded, color: AdminColors.primaryDark, size: 20),
                                      tooltip: 'عرض الملف الكامل وتمديد الاشتراك',
                                      onPressed: () => _showDoctorDetailsModal(doc),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(
                                        isApproved ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                                        color: isApproved ? AdminColors.warning : AdminColors.success,
                                        size: 22,
                                      ),
                                      tooltip: isApproved ? 'تجميد الحساب' : 'تفعيل الحساب',
                                      onPressed: () => _toggleDoctorApproval(doc['id'], isApproved),
                                    ),
                                  ],
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
}
