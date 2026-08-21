import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen>
    with SingleTickerProviderStateMixin {
  final _client = AdminSupabaseConfig.client;
  late TabController _tabController;
  String _selectedRoleFilter = 'ALL'; // 'ALL', 'doctor', 'pharmacy'
  bool _isLoading = true;
  List<Map<String, dynamic>> _verificationsList = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _fetchVerifications();
      }
    });
    _fetchVerifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentStatusTab {
    switch (_tabController.index) {
      case 0:
        return 'PENDING';
      case 1:
        return 'APPROVED';
      case 2:
        return 'REJECTED';
      default:
        return 'PENDING';
    }
  }

  Future<void> _fetchVerifications() async {
    setState(() => _isLoading = true);
    try {
      // 1. محاولة جلب البيانات من جدول partner_verifications
      var query = _client.from('partner_verifications').select('''
        id,
        user_id,
        role,
        full_name,
        phone,
        governorate,
        specialty,
        bio,
        id_front_url,
        id_back_url,
        status,
        rejection_reason,
        created_at,
        profiles (
          is_approved,
          fcm_token
        )
      ''');

      if (_currentStatusTab != 'ALL') {
        query = query.eq('status', _currentStatusTab);
      }
      if (_selectedRoleFilter != 'ALL') {
        query = query.eq('role', _selectedRoleFilter);
      }

      final res = await query.order('created_at', ascending: false);
      List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(res as List);

      // 2. إذا كان قسم PENDING وفارغاً، نفحص جدول profiles القديم للتوافق
      if (list.isEmpty && _currentStatusTab == 'PENDING') {
        final legacyRes = await _client
            .from('profiles')
            .select('''
              id,
              full_name,
              phone,
              role,
              governorate,
              created_at,
              doctors (specialty, bio),
              pharmacies (name, address_text)
            ''')
            .eq('is_approved', false)
            .order('created_at', ascending: false);

        for (var p in legacyRes) {
          final isDoc = (p['role'] as String? ?? '').toLowerCase().contains('doc');
          final doc = p['doctors'] as Map<String, dynamic>?;
          final pha = p['pharmacies'] as Map<String, dynamic>?;
          list.add({
            'id': p['id'],
            'user_id': p['id'],
            'role': isDoc ? 'doctor' : 'pharmacy',
            'full_name': p['full_name'] ?? (isDoc ? 'طبيب' : 'صيدلية'),
            'phone': p['phone'] ?? '',
            'governorate': p['governorate'] ?? 'مصر',
            'specialty': doc?['specialty'],
            'bio': doc?['bio'] ?? pha?['address_text'],
            'id_front_url': '',
            'id_back_url': '',
            'status': 'PENDING',
            'created_at': p['created_at'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _verificationsList = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approvePartner(Map<String, dynamic> item) async {
    final verificationId = item['id'] as String;
    final userId = item['user_id'] as String;
    final fullName = item['full_name'] as String? ?? 'الشريك';

    try {
      // 1. تحديث جدول partner_verifications
      await _client.from('partner_verifications').update({
        'status': 'APPROVED',
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', verificationId);

      // 2. تحديث جدول profiles
      await _client.from('profiles').update({'is_approved': true}).eq('id', userId);

      _fetchVerifications();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 تم اعتماد وتفعيل حساب $fullName بنجاح!'),
            backgroundColor: AdminColors.success,
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

  void _showRejectDialog(Map<String, dynamic> item) {
    final verificationId = item['id'] as String;
    final userId = item['user_id'] as String;
    final fullName = item['full_name'] as String? ?? 'الشريك';
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('رفض طلب الانضمام ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('يرجى توضيح سبب الرفض للشريك ($fullName):', style: GoogleFonts.cairo(fontSize: 12.5)),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'مثال: صورة كارنيه النقابة أو الترخيص غير واضحة، يرجى إعادة تصويرها...',
                hintStyle: GoogleFonts.cairo(fontSize: 11.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.emergency),
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('يرجى كتابة سبب الرفض', style: GoogleFonts.cairo())),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await _client.from('partner_verifications').update({
                  'status': 'REJECTED',
                  'rejection_reason': reasonCtrl.text.trim(),
                  'reviewed_at': DateTime.now().toIso8601String(),
                }).eq('id', verificationId);

                _fetchVerifications();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم رفض الطلب وحفظ السبب للشريك $fullName'),
                      backgroundColor: AdminColors.emergency,
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
            },
            child: Text('تأكيد الرفض', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showFullImage(String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 650),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AdminColors.primaryDark,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, __, ___) => Center(
                        child: Text('تعذر تحميل الصورة بدقة كاملة', style: GoogleFonts.cairo()),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس الصفحة
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
                          color: AdminColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: AdminColors.warning, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'لوحة تدقيق الهوية والاعتماد (KYC)',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'فحص مستندات الأطباء والصيدليات (البطاقة وترخيص المزاولة والسجل التجاري) واعتمادها',
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
                label: Text('تحديث الطلبات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchVerifications,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // شريط التبويبات (معلقة / معتمدة / مرفوضة) وفلترة الشركاء
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 360,
                decoration: BoxDecoration(
                  color: AdminColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AdminColors.cardBorderMint),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AdminColors.primaryDark,
                  unselectedLabelColor: AdminColors.textSecondary,
                  indicatorColor: AdminColors.accentMint,
                  indicatorWeight: 3,
                  labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 12),
                  tabs: const [
                    Tab(text: 'طلبات معلقة ⏳'),
                    Tab(text: 'معتمدة ✅'),
                    Tab(text: 'مرفوضة ❌'),
                  ],
                ),
              ),

              // فلتر الدور
              Row(
                children: [
                  Text('التصنيف:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 8),
                  _buildFilterChip('ALL', 'الكل 🌐'),
                  const SizedBox(width: 6),
                  _buildFilterChip('doctor', 'أطباء 🩺'),
                  const SizedBox(width: 6),
                  _buildFilterChip('pharmacy', 'صيدليات 💊'),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // قائمة الطلبات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                : _verificationsList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: const BoxDecoration(color: AdminColors.accentMintLight, shape: BoxShape.circle),
                              child: const Icon(Icons.check_circle_outline_rounded, size: 56, color: AdminColors.success),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'لا توجد طلبات في هذا القسم حالياً',
                              style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ستظهر هنا أي طلبات توثيق جديدة للمراجعة والتدقيق.',
                              style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _verificationsList.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final item = _verificationsList[index];
                          return _buildVerificationCard(item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedRoleFilter == key;
    return InkWell(
      onTap: () {
        setState(() => _selectedRoleFilter = key);
        _fetchVerifications();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primaryDark : AdminColors.surfaceWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AdminColors.primaryDark : AdminColors.cardBorderMint),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
            color: isSelected ? Colors.white : AdminColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationCard(Map<String, dynamic> item) {
    final role = (item['role'] as String? ?? 'doctor').toLowerCase();
    final isDoctor = role.contains('doc');
    final fullName = item['full_name'] as String? ?? 'الشريك';
    final phone = item['phone'] as String? ?? '';
    final governorate = item['governorate'] as String? ?? 'مصر';
    final specialty = item['specialty'] as String?;
    final bio = item['bio'] as String?;
    final frontUrl = item['id_front_url'] as String? ?? '';
    final backUrl = item['id_back_url'] as String? ?? '';
    final status = item['status'] as String? ?? 'PENDING';
    final rejectionReason = item['rejection_reason'] as String?;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'APPROVED'
              ? Colors.green.shade300
              : (status == 'REJECTED' ? Colors.red.shade300 : Colors.amber.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // أيقونة الدور
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isDoctor ? AdminColors.primaryDark.withValues(alpha: 0.1) : AdminColors.accentMintLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded,
              color: isDoctor ? AdminColors.primaryDark : AdminColors.accentMint,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),

          // البيانات الأساسية
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      fullName,
                      style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDoctor ? AdminColors.primaryDark.withValues(alpha: 0.1) : Colors.lightBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isDoctor ? 'طبيب / عيادة 🩺' : 'صيدلية معتمدة 💊',
                        style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: isDoctor ? AdminColors.primaryDark : Colors.blue.shade800),
                      ),
                    ),
                  ],
                ),
                if (specialty != null && specialty.isNotEmpty)
                  Text('التخصص: $specialty', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.accentCyan, fontWeight: FontWeight.bold)),
                if (bio != null && bio.isNotEmpty)
                  Text('النبذة / العنوان: $bio', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                Text(
                  '📞 الهاتف: $phone | 📍 المحافظة: $governorate',
                  style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                ),
                if (status == 'REJECTED' && rejectionReason != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
                    child: Text('سبب الرفض: $rejectionReason', style: GoogleFonts.cairo(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),

          // وثائق الهوية والترخيص (KYC Documents Preview)
          if (frontUrl.isNotEmpty || backUrl.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(
              children: [
                if (frontUrl.isNotEmpty)
                  _buildKycDocThumbnail('وجه البطاقة / الترخيص', frontUrl),
                if (backUrl.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildKycDocThumbnail('ظهر البطاقة / السجل', backUrl),
                ],
              ],
            ),
          ],

          const SizedBox(width: 14),

          // أزرار القرار
          if (status == 'PENDING') ...[
            Column(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: Text('اعتماد وتفعيل', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => _approvePartner(item),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.emergency,
                    side: const BorderSide(color: AdminColors.emergency),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('رفض الطلب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => _showRejectDialog(item),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: status == 'APPROVED' ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: status == 'APPROVED' ? Colors.green.shade300 : Colors.red.shade300),
              ),
              child: Text(
                status == 'APPROVED' ? 'تم الاعتماد ✅' : 'مرفوض ❌',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: status == 'APPROVED' ? Colors.green.shade900 : Colors.red.shade900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKycDocThumbnail(String title, String url) {
    return InkWell(
      onTap: () => _showFullImage(url, title),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 85,
        height: 65,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminColors.cardBorderMint),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, size: 18, color: Colors.grey),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white, size: 10),
                      const SizedBox(width: 2),
                      Text('تكبير', style: GoogleFonts.cairo(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
