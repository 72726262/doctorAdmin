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
  final TextEditingController _searchController = TextEditingController();

  String _selectedRoleFilter = 'ALL'; // 'ALL', 'doctor', 'pharmacy'
  String _searchQuery = '';
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
    _searchController.dispose();
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
        national_id_front_url,
        national_id_back_url,
        syndicate_card_url,
        practice_license_url,
        commercial_register_url,
        tax_card_url,
        status,
        rejection_reason,
        created_at,
        reviewed_at,
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

      if (mounted) {
        setState(() {
          _verificationsList = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching verifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// اعتماد فوري لحظي (Optimistic Instant Update)
  Future<void> _approvePartner(Map<String, dynamic> item) async {
    final verificationId = item['id'] as String;
    final userId = item['user_id'] as String;
    final fullName = item['full_name'] as String? ?? 'الشريك';

    // 1. تحديث لحظي في الذاكرة فوراً لسرعة وسلاسة الواجهة
    final previousList = List<Map<String, dynamic>>.from(_verificationsList);
    setState(() {
      _verificationsList.removeWhere((v) => v['id'] == verificationId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '🎉 تم اعتماد وتفعيل حساب $fullName بنجاح!',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: AdminColors.success,
        duration: const Duration(seconds: 2),
      ),
    );

    // 2. مزامنة الباك إند في الخلفية
    try {
      await _client.from('partner_verifications').update({
        'status': 'APPROVED',
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', verificationId);

      await _client.from('profiles').update({'is_approved': true}).eq('id', userId);

      final role = (item['role'] as String? ?? '').toUpperCase();
      if (role == 'DOCTOR') {
        await _client.from('doctors').update({'subscription_status': 'ACTIVE'}).eq('id', userId);
      } else if (role == 'PHARMACY') {
        await _client.from('pharmacies').update({'subscription_status': 'ACTIVE'}).eq('id', userId);
      }
    } catch (e) {
      // في حالة الفشل نرجع الحالة السابقة
      if (mounted) {
        setState(() => _verificationsList = previousList);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إتمام العملية: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  /// رفض فوري لحظي (Optimistic Instant Rejection)
  void _showRejectDialog(Map<String, dynamic> item) {
    final verificationId = item['id'] as String;
    final userId = item['user_id'] as String;
    final fullName = item['full_name'] as String? ?? 'الشريك';
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: AdminColors.emergency, size: 24),
            const SizedBox(width: 8),
            Text('رفض طلب الانضمام ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('يرجى توضيح سبب الرفض للشريك ($fullName):', style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textPrimary)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              style: GoogleFonts.cairo(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'مثال: صورة ترخيص المزاولة غير واضحة، يرجى إعادة رفعها بدقة أعلى...',
                hintStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade500),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.emergency,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('يرجى كتابة سبب الرفض', style: GoogleFonts.cairo())),
                );
                return;
              }
              Navigator.pop(ctx);

              // تحديث لحظي فوري في الذاكرة
              final previousList = List<Map<String, dynamic>>.from(_verificationsList);
              setState(() {
                _verificationsList.removeWhere((v) => v['id'] == verificationId);
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تم رفض الطلب وحفظ السبب للشريك $fullName'),
                  backgroundColor: AdminColors.emergency,
                  duration: const Duration(seconds: 2),
                ),
              );

              try {
                await _client.from('partner_verifications').update({
                  'status': 'REJECTED',
                  'rejection_reason': reason,
                  'reviewed_at': DateTime.now().toIso8601String(),
                }).eq('id', verificationId);

                await _client.from('profiles').update({'is_approved': false}).eq('id', userId);
              } catch (e) {
                if (mounted) {
                  setState(() => _verificationsList = previousList);
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
    if (url.trim().isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 850, maxHeight: 650),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: AdminColors.primaryDark,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.image_search_rounded, color: AdminColors.accentMint, size: 20),
                        const SizedBox(width: 8),
                        Text(title, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
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
    // تصفية حية وفورية بناءً على نص البحث بالاسم أو رقم الهاتف
    final filteredList = _verificationsList.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final query = _searchQuery.trim().toLowerCase();
      final name = (item['full_name'] as String? ?? '').toLowerCase();
      final phone = (item['phone'] as String? ?? '').toLowerCase();
      final specialty = (item['specialty'] as String? ?? '').toLowerCase();
      final gov = (item['governorate'] as String? ?? '').toLowerCase();
      return name.contains(query) || phone.contains(query) || specialty.contains(query) || gov.contains(query);
    }).toList();

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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث الطلبات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchVerifications,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // شريط البحث المباشر (Search Bar by Name & Phone)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.cardBorderMint),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: GoogleFonts.cairo(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: '🔍 ابحث فوراً باسم الطبيب، الصيدلية، التخصص، المحافظة، أو رقم الهاتف...',
                hintStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // التابات وفلاتر الدور
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // فلاتر التصنيف (طبيب / صيدلية)
              Row(
                children: [
                  Text('التصنيف:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textPrimary)),
                  const SizedBox(width: 8),
                  _buildRoleChip('الكل 🌐', 'ALL'),
                  const SizedBox(width: 6),
                  _buildRoleChip('أطباء 🩺', 'doctor'),
                  const SizedBox(width: 6),
                  _buildRoleChip('صيدليات 💊', 'pharmacy'),
                ],
              ),

              // تابات الحالة (معلقة، معتمدة، مرفوضة)
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AdminColors.primaryDark,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                  tabs: const [
                    Tab(text: 'طلبات معلقة ⏳'),
                    Tab(text: 'معتمدة ✅'),
                    Tab(text: 'مرفوضة ❌'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // محتوى القائمة
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredList.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          final item = filteredList[index];
                          return _buildVerificationCard(item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChip(String label, String roleKey) {
    final isSelected = _selectedRoleFilter == roleKey;
    return InkWell(
      onTap: () {
        setState(() => _selectedRoleFilter = roleKey);
        _fetchVerifications();
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminColors.accentMintLight.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline_rounded, color: AdminColors.primaryDark, size: 48),
          ),
          const SizedBox(height: 14),
          Text(
            _searchQuery.isNotEmpty ? 'لا توجد نتائج تطابق بحثك "$_searchQuery"' : 'لا توجد طلبات في هذا القسم حالياً',
            style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isNotEmpty ? 'جرب البحث باسم آخر أو تأكد من رقم الهاتف' : 'ستظهر هنا أي طلبات توثيق جديدة للمراجعة والتدقيق.',
            style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(Map<String, dynamic> item) {
    final role = (item['role'] as String? ?? 'doctor').toLowerCase();
    final isDoctor = role.contains('doc');
    final fullName = item['full_name'] as String? ?? 'غير محدد';
    final phone = item['phone'] as String? ?? 'لا يوجد';
    final governorate = item['governorate'] as String? ?? 'مصر';
    final specialty = item['specialty'] as String? ?? (isDoctor ? 'طب عام' : 'صيدلية');
    final bio = item['bio'] as String? ?? '';
    final status = item['status'] as String? ?? 'PENDING';
    final rejectionReason = item['rejection_reason'] as String?;

    // روابط الصور
    final frontUrl = item['id_front_url'] as String? ?? item['national_id_front_url'] as String? ?? '';
    final backUrl = item['id_back_url'] as String? ?? item['national_id_back_url'] as String? ?? '';
    final syndicateUrl = item['syndicate_card_url'] as String? ?? '';
    final licenseUrl = item['practice_license_url'] as String? ?? item['commercial_register_url'] as String? ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorderMint),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الهيدر والبيانات الأساسية
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: isDoctor ? AdminColors.primaryDark.withValues(alpha: 0.1) : AdminColors.accentMint.withValues(alpha: 0.15),
                      child: Icon(
                        isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded,
                        color: isDoctor ? AdminColors.primaryDark : AdminColors.accentMint,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              fullName,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16, color: AdminColors.textPrimary),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDoctor ? AdminColors.primaryDark.withValues(alpha: 0.1) : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isDoctor ? 'طبيب 🩺' : 'صيدلية 💊',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDoctor ? AdminColors.primaryDark : Colors.teal.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$specialty • $governorate',
                          style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),

                // تفاصيل التواصل
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_iphone_rounded, size: 16, color: AdminColors.primaryDark),
                      const SizedBox(width: 6),
                      Text(phone, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),

            if (bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('📝 النبذة / العنوان: $bio', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade800)),
              ),
            ],

            if (status == 'REJECTED' && rejectionReason != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('سبب الرفض: $rejectionReason', style: GoogleFonts.cairo(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // معرض صور المستندات والبطاقات (KYC Document Previews)
            Text('المستندات ووثائق الهوية المرفقة (اضغط للتكبير والفحص):', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
            const SizedBox(height: 10),

            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                if (frontUrl.isNotEmpty)
                  _buildDocThumbnail(frontUrl, 'بطاقة الرقم القومي (الوجه الأمامي)'),
                if (backUrl.isNotEmpty)
                  _buildDocThumbnail(backUrl, 'بطاقة الرقم القومي (الوجه الخلفي)'),
                if (syndicateUrl.isNotEmpty)
                  _buildDocThumbnail(syndicateUrl, 'كارنيه النقابة الساري'),
                if (licenseUrl.isNotEmpty)
                  _buildDocThumbnail(licenseUrl, isDoctor ? 'تصريح مزاولة المهنة' : 'السجل التجاري والبطاقة الضريبية'),
                if (frontUrl.isEmpty && backUrl.isEmpty && syndicateUrl.isEmpty && licenseUrl.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('⚠️ لم يتم إرفاق صور مستندات ورقية مع هذا الطلب', style: GoogleFonts.cairo(fontSize: 12, color: Colors.amber.shade900)),
                  ),
              ],
            ),

            if (status == 'PENDING') ...[
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // أزرار اتخاذ القرار السريعة (Approve / Reject Action Buttons)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.emergency,
                      side: const BorderSide(color: AdminColors.emergency),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    label: Text('رفض الطلب ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => _showRejectDialog(item),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text('اعتماد وقبول فوري 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => _approvePartner(item),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocThumbnail(String url, String title) {
    return InkWell(
      onTap: () => _showFullImage(url, title),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 140,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image_rounded, color: Colors.grey.shade400, size: 30),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                color: Colors.black.withValues(alpha: 0.65),
                child: Text(
                  title,
                  style: GoogleFonts.cairo(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
