import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:image_picker/image_picker.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PromotionalAdsScreen extends StatefulWidget {
  const PromotionalAdsScreen({super.key});

  @override
  State<PromotionalAdsScreen> createState() => _PromotionalAdsScreenState();
}

class _PromotionalAdsScreenState extends State<PromotionalAdsScreen> {
  final _client = AdminSupabaseConfig.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedTypeFilter = 'ALL'; // ALL, DOCTOR, PHARMACY, GENERAL
  String _selectedGovFilter = 'الكل';

  List<Map<String, dynamic>> _ads = [];
  List<Map<String, dynamic>> _registeredDoctors = [];
  List<Map<String, dynamic>> _registeredPharmacies = [];

  // قائمة المحافظات الـ 27 لجمهورية مصر العربية
  static const List<String> _egyptGovernorates = [
    'القاهرة', 'الجيزة', 'الإسكندرية', 'الدقهلية', 'الشرقية', 'القليوبية',
    'المنوفية', 'الغربية', 'كفر الشيخ', 'البحيرة', 'دمياط', 'بورسعيد',
    'الإسماعيلية', 'السويس', 'شمال سيناء', 'جنوب سيناء', 'بني سويف', 'الفيوم',
    'المنيا', 'أسيوط', 'سوهاج', 'قنا', 'الأقصر', 'أسوان', 'البحر الأحمر',
    'الوادي الجديد', 'مطروح'
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      // 1. تنظيف الإعلانات المنتهية أولاً فورياً عبر RPC
      try {
        await _client.rpc('purge_expired_promotional_ads');
      } catch (_) {}

      // 2. جلب جميع الإعلانات مع ربط الأطباء والصيدليات
      final adsRes = await _client
          .from('promotional_ads')
          .select('''
            id, ad_type, doctor_id, pharmacy_id, title, subtitle, description,
            image_url, target_governorates, action_url, badge_text, priority,
            views_count, clicks_count, starts_at, expires_at, is_active, created_at,
            doctors(id, specialty, rating_avg, profiles(full_name, avatar_url, phone)),
            pharmacies(id, name, governorate, rating_avg, profiles(avatar_url, phone))
          ''')
          .order('priority', ascending: false)
          .order('created_at', ascending: false);

      // 3. جلب الأطباء المسجلين للاختيار منهم عند إنشاء إعلان
      final docsRes = await _client
          .from('doctors')
          .select('id, specialty, rating_avg, profiles(full_name, avatar_url, phone)')
          .limit(200);

      // 4. جلب الصيدليات المسجلة للاختيار منها
      final pharmsRes = await _client
          .from('pharmacies')
          .select('id, name, governorate, address_text, rating_avg, profiles(avatar_url, phone)')
          .limit(200);

      if (mounted) {
        setState(() {
          _ads = List<Map<String, dynamic>>.from(adsRes as List);
          _registeredDoctors = List<Map<String, dynamic>>.from(docsRes as List);
          _registeredPharmacies = List<Map<String, dynamic>>.from(pharmsRes as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAdStatus(String id, bool currentStatus, String title) async {
    try {
      await _client.from('promotional_ads').update({
        'is_active': !currentStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      AdminAuditService.log(
        actionType: currentStatus ? 'إيقاف إعلان ترويجي مؤقتاً' : 'تفعيل إعلان ترويجي',
        targetType: 'PROMOTIONAL_AD',
        targetName: title,
        details: {'ad_id': id, 'new_status': !currentStatus},
      );

      _loadAllData(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentStatus ? 'تم إيقاف الإعلان مؤقتاً ⏸️' : 'تم تفعيل الإعلان وإطلاقه للمرضى 🚀'),
            backgroundColor: currentStatus ? AdminColors.warning : AdminColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تعديل حالة الإعلان: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  Future<void> _deleteAdPermanently(String id, String title, String imageUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: AdminColors.emergency, size: 24),
            const SizedBox(width: 8),
            Text('حذف الإعلان نهائياً 🗑️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف إعلان "$title" نهائياً؟ سيتم حذفه من قاعدة البيانات وحذف صورته من السيرفر والاستورج فوراً.',
          style: GoogleFonts.cairo(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.emergency, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('حذف نهائي الآن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. حذف الصورة من الاستورج إن كانت مخزنة في promotional_ads bucket
      if (imageUrl.contains('/promotional_ads/')) {
        try {
          final fileName = imageUrl.split('/promotional_ads/').last.split('?').first;
          if (fileName.isNotEmpty) {
            await _client.storage.from('promotional_ads').remove([fileName]);
          }
        } catch (_) {}
      }

      // 2. حذف السجل من قاعدة البيانات (يقوم التريجر بحذفها من storage.objects أيضاً)
      await _client.from('promotional_ads').delete().eq('id', id);

      AdminAuditService.log(
        actionType: 'حذف إعلان ترويجي وصورته من الاستورج نهائياً',
        targetType: 'PROMOTIONAL_AD',
        targetName: title,
        details: {'ad_id': id, 'image_url': imageUrl},
      );

      _loadAllData(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الإعلان ومسح صورته من الاستورج بنجاح 🗑️'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredAds = _ads.where((ad) {
      final title = (ad['title'] ?? '').toString().toLowerCase();
      final subtitle = (ad['subtitle'] ?? '').toString().toLowerCase();
      final type = (ad['ad_type'] ?? '').toString();

      final doc = ad['doctors'] as Map<String, dynamic>?;
      final docProfile = doc?['profiles'] as Map<String, dynamic>?;
      final docName = (docProfile?['full_name'] ?? '').toString().toLowerCase();
      final docPhone = (docProfile?['phone'] ?? '').toString().toLowerCase();

      final pharm = ad['pharmacies'] as Map<String, dynamic>?;
      final pharmName = (pharm?['name'] ?? '').toString().toLowerCase();
      final pharmProfile = pharm?['profiles'] as Map<String, dynamic>?;
      final pharmPhone = (pharmProfile?['phone'] ?? '').toString().toLowerCase();

      final matchesQuery = _searchQuery.isEmpty ||
          title.contains(_searchQuery.toLowerCase()) ||
          subtitle.contains(_searchQuery.toLowerCase()) ||
          docName.contains(_searchQuery.toLowerCase()) ||
          docPhone.contains(_searchQuery.toLowerCase()) ||
          pharmName.contains(_searchQuery.toLowerCase()) ||
          pharmPhone.contains(_searchQuery.toLowerCase());

      final matchesType = _selectedTypeFilter == 'ALL' || type == _selectedTypeFilter;

      final targetGovs = List<String>.from(ad['target_governorates'] ?? ['الكل']);
      final matchesGov = _selectedGovFilter == 'الكل' ||
          targetGovs.contains('الكل') ||
          targetGovs.contains(_selectedGovFilter);

      return matchesQuery && matchesType && matchesGov;
    }).toList();

    final activeCount = _ads.where((a) => a['is_active'] == true).length;
    final doctorAdsCount = _ads.where((a) => a['ad_type'] == 'DOCTOR').length;
    final pharmacyAdsCount = _ads.where((a) => a['ad_type'] == 'PHARMACY').length;
    final generalAdsCount = _ads.where((a) => a['ad_type'] == 'GENERAL').length;

    return Container(
      color: AdminColors.backgroundCanvas,
      child: RefreshIndicator(
        onRefresh: () => _loadAllData(),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // 1. شريط العنوان
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
                            color: AdminColors.primaryDark.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.campaign_rounded, color: AdminColors.primaryDark, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'إدارة الإعلانات والبنرات الممولة 📢',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 18, color: AdminColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ترويج وحملات ممولة للأطباء المعتمدين والصيدليات مع الاستهداف الجغرافي ورفع الصور والاستورج النظيف',
                      style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'تحديث فوري وتنظيف الإعلانات المنتهية',
                      icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                      onPressed: () => _loadAllData(),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
                      label: Text(
                        'إطلاق إعلان ممول جديد 🚀',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      onPressed: _showCreateAdDialog,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 2. كروت الإحصائيات الأربعة
            Row(
              children: [
                Expanded(child: _buildMetricCard('الإعلانات النشطة حالياً', '$activeCount', Icons.check_circle_rounded, AdminColors.success, AdminColors.successLight)),
                const SizedBox(width: 14),
                Expanded(child: _buildMetricCard('إعلانات الأطباء المميزة', '$doctorAdsCount', Icons.medical_services_rounded, AdminColors.primaryDark, AdminColors.cardBorderMint)),
                const SizedBox(width: 14),
                Expanded(child: _buildMetricCard('إعلانات الصيدليات والخصومات', '$pharmacyAdsCount', Icons.local_pharmacy_rounded, Colors.teal.shade700, Colors.teal.shade50)),
                const SizedBox(width: 14),
                Expanded(child: _buildMetricCard('الحملات العامة والتوعية', '$generalAdsCount', Icons.stars_rounded, Colors.purple.shade700, Colors.purple.shade50)),
              ],
            ),

            const SizedBox(height: 20),

            // 3. كارت التصفية والبحث
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AdminColors.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.cairo(fontSize: 13),
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: 'ابحث بالعنوان، اسم الطبيب، الصيدلية، أو رقم الهاتف...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.textSecondary),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AdminColors.backgroundCanvas,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AdminColors.backgroundCanvas,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedGovFilter,
                              isExpanded: true,
                              icon: const Icon(Icons.location_on_rounded, color: AdminColors.primaryDark, size: 20),
                              items: ['الكل', ..._egyptGovernorates].map((gov) {
                                return DropdownMenuItem<String>(
                                  value: gov,
                                  child: Text(
                                    gov == 'الكل' ? '📍 كل المحافظات المستهدفة' : '📍 محافظة $gov',
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedGovFilter = val);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('تصفية النوع:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                      const SizedBox(width: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildTypeChip('ALL', 'الكل (${_ads.length})'),
                          _buildTypeChip('DOCTOR', 'أطباء 🩺 ($doctorAdsCount)'),
                          _buildTypeChip('PHARMACY', 'صيدليات 💊 ($pharmacyAdsCount)'),
                          _buildTypeChip('GENERAL', 'حملات عامة 🏷️ ($generalAdsCount)'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 4. قائمة الإعلانات
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: AdminShimmerBox(width: 400, height: 120)),
              )
            else if (filteredAds.isEmpty)
              Container(
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: AdminColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AdminColors.cardBorder),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.campaign_outlined, size: 64, color: AdminColors.textMuted),
                      const SizedBox(height: 12),
                      Text('لا توجد إعلانات تطابق البحث حالياً', style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                      const SizedBox(height: 6),
                      Text('اضغط على "إطلاق إعلان ممول جديد" بالأعلى لإنشاء أول إعلان واستهدافه بالمحافظات', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                    ],
                  ),
                ),
              )
            else
              ...filteredAds.map((ad) => _buildAdCard(ad)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label) {
    final isSelected = _selectedTypeFilter == type;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)),
      selected: isSelected,
      selectedColor: AdminColors.primaryDark,
      labelStyle: TextStyle(color: isSelected ? Colors.white : AdminColors.textPrimary),
      onSelected: (_) => setState(() => _selectedTypeFilter = type),
    );
  }

  Widget _buildAdCard(Map<String, dynamic> ad) {
    final id = ad['id'] as String;
    final adType = ad['ad_type'] as String? ?? 'GENERAL';
    final title = ad['title'] as String? ?? '';
    final subtitle = ad['subtitle'] as String? ?? '';
    final badgeText = ad['badge_text'] as String? ?? 'مميز ⭐';
    final targetGovs = List<String>.from(ad['target_governorates'] ?? ['الكل']);
    final isActive = ad['is_active'] as bool? ?? true;
    final priority = ad['priority'] as int? ?? 0;
    final expiresAtStr = ad['expires_at'] as String?;
    final imageUrl = ad['image_url'] as String? ?? '';

    DateTime? expiresAt;
    if (expiresAtStr != null) {
      expiresAt = DateTime.tryParse(expiresAtStr)?.toLocal();
    }

    String countdownText = 'غير محدد';
    bool isEndingSoon = false;
    if (expiresAt != null) {
      final diff = expiresAt.difference(DateTime.now());
      if (diff.isNegative) {
        countdownText = 'منتهٍ (سيتم حذفه تلقائياً)';
      } else if (diff.inDays > 0) {
        countdownText = 'متبقي ${diff.inDays} يوم و ${diff.inHours % 24} ساعة';
      } else if (diff.inHours > 0) {
        countdownText = 'متبقي ${diff.inHours} ساعة فقط 🔥';
        isEndingSoon = true;
      } else {
        countdownText = 'متبقي ${diff.inMinutes} دقيقة فقط 🔥';
        isEndingSoon = true;
      }
    }

    String? docName;
    String? docSpecialty;
    String? docPhone;
    String? docAvatar;
    if (adType == 'DOCTOR') {
      final doc = ad['doctors'] as Map<String, dynamic>?;
      final docProf = doc?['profiles'] as Map<String, dynamic>?;
      docName = docProf?['full_name'] as String?;
      docSpecialty = doc?['specialty'] as String?;
      docPhone = docProf?['phone'] as String?;
      docAvatar = docProf?['avatar_url'] as String?;
    }

    String? pharmName;
    String? pharmGov;
    String? pharmPhone;
    String? pharmAvatar;
    if (adType == 'PHARMACY') {
      final pharm = ad['pharmacies'] as Map<String, dynamic>?;
      final pharmProf = pharm?['profiles'] as Map<String, dynamic>?;
      pharmName = pharm?['name'] as String?;
      pharmGov = pharm?['governorate'] as String?;
      pharmPhone = pharmProf?['phone'] as String?;
      pharmAvatar = pharmProf?['avatar_url'] as String?;
    }

    Color typeColor;
    String typeLabel;
    IconData typeIcon;
    if (adType == 'DOCTOR') {
      typeColor = AdminColors.primaryDark;
      typeLabel = 'طبيب مسجل 🩺';
      typeIcon = Icons.medical_services_rounded;
    } else if (adType == 'PHARMACY') {
      typeColor = Colors.teal.shade800;
      typeLabel = 'صيدلية مسجلة 💊';
      typeIcon = Icons.local_pharmacy_rounded;
    } else {
      typeColor = Colors.purple.shade700;
      typeLabel = 'إعلان عام / جهة خارجية 🏷️';
      typeIcon = Icons.stars_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AdminColors.cardBorderMint : AdminColors.cardBorder,
          width: isActive ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isActive ? 0.03 : 0.01), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: typeColor.withValues(alpha: 0.1),
                image: (docAvatar != null && docAvatar.isNotEmpty) ||
                        (pharmAvatar != null && pharmAvatar.isNotEmpty) ||
                        imageUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(
                          imageUrl.isNotEmpty
                              ? imageUrl
                              : (docAvatar?.isNotEmpty == true ? docAvatar! : pharmAvatar ?? ''),
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (docAvatar == null || docAvatar.isEmpty) &&
                      (pharmAvatar == null || pharmAvatar.isEmpty) &&
                      imageUrl.isEmpty
                  ? Center(child: Icon(typeIcon, color: typeColor, size: 36))
                  : null,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(typeLabel, style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: typeColor)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                        child: Text(badgeText, style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF92400E))),
                      ),
                      if (priority > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Text('أولوية: $priority', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                        ),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isActive ? AdminColors.success : Colors.grey).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isActive ? '🟢 نشط ويظهر للمرضى' : '⚪ متوقف مؤقتاً',
                          style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: isActive ? AdminColors.success : Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 15, color: AdminColors.textPrimary)),
                  if (docName != null && docName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('👨‍⚕️ د. $docName (${docSpecialty ?? 'استشاري'})', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                        if (docPhone != null && docPhone.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text('📞 $docPhone', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ] else if (pharmName != null && pharmName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('💊 $pharmName (${pharmGov ?? 'محافظة'})', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                        if (pharmPhone != null && pharmPhone.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text('📞 $pharmPhone', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ],
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: AdminColors.textMuted),
                      Text('المحافظات المستهدفة:', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                      ...targetGovs.take(5).map((g) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(color: AdminColors.backgroundCanvas, borderRadius: BorderRadius.circular(4), border: Border.all(color: AdminColors.cardBorder)),
                            child: Text(g == 'الكل' ? '🇪🇬 كل المحافظات' : g, style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                          )),
                      if (targetGovs.length > 5)
                        Text('+ ${targetGovs.length - 5} محافظات أخرى', style: GoogleFonts.cairo(fontSize: 10, color: AdminColors.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 14, color: isEndingSoon ? AdminColors.emergency : AdminColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        'موعد الانتهاء: ${expiresAt != null ? intl.DateFormat('yyyy/MM/dd - hh:mm a').format(expiresAt) : 'غير محدد'}',
                        style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (isEndingSoon ? AdminColors.emergency : AdminColors.primaryDark).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(countdownText, style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: isEndingSoon ? AdminColors.emergency : AdminColors.primaryDark)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Column(
              children: [
                Switch(
                  value: isActive,
                  activeTrackColor: AdminColors.success,
                  onChanged: (_) => _toggleAdStatus(id, isActive, title),
                ),
                Text(isActive ? 'مفعل' : 'متوقف', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? AdminColors.success : Colors.grey)),
                const SizedBox(height: 8),
                IconButton(
                  tooltip: 'حذف الإعلان وصورته نهائياً',
                  icon: const Icon(Icons.delete_forever_rounded, color: AdminColors.emergency, size: 22),
                  onPressed: () => _deleteAdPermanently(id, title, imageUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- نافذة البحث الفوري والفلترة الذكية لاختيار الطبيب ---
  Future<Map<String, dynamic>?> _openDoctorSearchDialog(BuildContext parentContext) async {
    String query = '';
    return showDialog<Map<String, dynamic>>(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (searchCtx, setSearchState) {
          final cleanQuery = query.trim().toLowerCase();
          final filtered = _registeredDoctors.where((doc) {
            final prof = doc['profiles'] as Map<String, dynamic>?;
            final name = (prof?['full_name'] ?? '').toString().toLowerCase();
            final phone = (prof?['phone'] ?? '').toString().toLowerCase();
            final spec = (doc['specialty'] ?? '').toString().toLowerCase();
            return cleanQuery.isEmpty ||
                name.contains(cleanQuery) ||
                phone.contains(cleanQuery) ||
                spec.contains(cleanQuery);
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: AdminColors.surfaceWhite,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.primaryDark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.search_rounded, color: AdminColors.primaryDark, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('بحث واختيار الطبيب المعتمد 🩺', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('ابحث بالاسم الكامل، التخصص الطبي، أو رقم الهاتف', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            content: SizedBox(
              width: 580,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'اكتب اسم الطبيب أو تخصصه أو رقم الموبايل...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => setSearchState(() => query = ''),
                            )
                          : null,
                      filled: true,
                      fillColor: AdminColors.backgroundCanvas,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onChanged: (v) => setSearchState(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('نتائج البحث (${filtered.length} طبيب متاح)', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                      if (query.isNotEmpty)
                        Text('تم الفلترة بكلمة: "$query"', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.primaryDark, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_search_rounded, size: 48, color: AdminColors.textMuted),
                                const SizedBox(height: 8),
                                Text('لا يوجد طبيب مطابق لكلمات البحث', style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                                Text('تأكد من كتابة الاسم أو رقم الهاتف بشكل صحيح', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textMuted)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, index) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final doc = filtered[i];
                              final prof = doc['profiles'] as Map<String, dynamic>?;
                              final name = prof?['full_name'] ?? 'طبيب';
                              final spec = doc['specialty'] ?? 'عام';
                              final phone = prof?['phone'] ?? '';
                              final avatar = prof?['avatar_url'] as String?;
                              final rating = (doc['rating_avg'] as num?)?.toDouble() ?? 0.0;

                              return InkWell(
                                onTap: () => Navigator.pop(ctx, doc),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                        backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                                        child: (avatar == null || avatar.isEmpty) ? const Icon(Icons.person_rounded, color: AdminColors.primaryDark) : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('د. $name', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textPrimary)),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                  decoration: BoxDecoration(color: AdminColors.primaryDark.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                                  child: Text(spec, style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                                                ),
                                                if (phone.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Text('📞 $phone', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary, fontWeight: FontWeight.w600)),
                                                ],
                                                if (rating > 0) ...[
                                                  const SizedBox(width: 8),
                                                  Text('⭐ ${rating.toStringAsFixed(1)}', style: GoogleFonts.cairo(fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AdminColors.primaryDark,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => Navigator.pop(ctx, doc),
                                        child: Text('اختيار الطبيب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- نافذة البحث الفوري والفلترة الذكية لاختيار الصيدلية ---
  Future<Map<String, dynamic>?> _openPharmacySearchDialog(BuildContext parentContext) async {
    String query = '';
    return showDialog<Map<String, dynamic>>(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (searchCtx, setSearchState) {
          final cleanQuery = query.trim().toLowerCase();
          final filtered = _registeredPharmacies.where((pharm) {
            final name = (pharm['name'] ?? '').toString().toLowerCase();
            final gov = (pharm['governorate'] ?? '').toString().toLowerCase();
            final addr = (pharm['address_text'] ?? '').toString().toLowerCase();
            final prof = pharm['profiles'] as Map<String, dynamic>?;
            final phone = (prof?['phone'] ?? '').toString().toLowerCase();
            return cleanQuery.isEmpty ||
                name.contains(cleanQuery) ||
                gov.contains(cleanQuery) ||
                addr.contains(cleanQuery) ||
                phone.contains(cleanQuery);
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: AdminColors.surfaceWhite,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.search_rounded, color: Colors.teal.shade800, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('بحث واختيار الصيدلية المعتمدة 💊', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('ابحث بالاسم، المحافظة، العنوان، أو رقم الهاتف', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            content: SizedBox(
              width: 580,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'اكتب اسم الصيدلية أو المحافظة أو رقم الموبايل...',
                      prefixIcon: Icon(Icons.search_rounded, color: Colors.teal.shade800),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => setSearchState(() => query = ''),
                            )
                          : null,
                      filled: true,
                      fillColor: AdminColors.backgroundCanvas,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onChanged: (v) => setSearchState(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('نتائج البحث (${filtered.length} صيدلية متاحة)', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                      if (query.isNotEmpty)
                        Text('تم الفلترة بكلمة: "$query"', style: GoogleFonts.cairo(fontSize: 11, color: Colors.teal.shade800, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.store_mall_directory_outlined, size: 48, color: AdminColors.textMuted),
                                const SizedBox(height: 8),
                                Text('لا توجد صيدلية مطابقة لكلمات البحث', style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, index) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final pharm = filtered[i];
                              final name = pharm['name'] ?? 'صيدلية';
                              final gov = pharm['governorate'] ?? '';
                              final prof = pharm['profiles'] as Map<String, dynamic>?;
                              final phone = prof?['phone'] ?? '';
                              final avatar = prof?['avatar_url'] as String?;

                              return InkWell(
                                onTap: () => Navigator.pop(ctx, pharm),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: Colors.teal.shade50,
                                        backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                                        child: (avatar == null || avatar.isEmpty) ? Icon(Icons.local_pharmacy_rounded, color: Colors.teal.shade800) : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textPrimary)),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                  decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(4)),
                                                  child: Text(gov, style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                                                ),
                                                if (phone.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Text('📞 $phone', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary, fontWeight: FontWeight.w600)),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal.shade800,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => Navigator.pop(ctx, pharm),
                                        child: Text('اختيار الصيدلية', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- نافذة إنشاء إعلان جديد مع البحث المتقدم ورفع الصور ---
  void _showCreateAdDialog() {
    String adType = 'DOCTOR'; // DOCTOR, PHARMACY, GENERAL
    Map<String, dynamic>? selectedDoctor;
    Map<String, dynamic>? selectedPharmacy;

    Uint8List? pickedImageBytes;
    String? pickedImageName;
    bool isUploadingImage = false;

    final titleCtrl = TextEditingController();
    final subtitleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final actionUrlCtrl = TextEditingController();
    final badgeCtrl = TextEditingController(text: 'طبيب مميز ⭐');
    final priorityCtrl = TextEditingController(text: '10');

    final selectedGovernorates = <String>{'الكل'};
    DateTime selectedExpiry = DateTime.now().add(const Duration(days: 14));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: AdminColors.surfaceWhite,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AdminColors.primaryDark.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_business_rounded, color: AdminColors.primaryDark, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text('إطلاق إعلان ممول جديد 📢', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(dialogCtx)),
              ],
            ),
            content: SizedBox(
              width: 780,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // بنر توضيحي عن الحذف التلقائي وحماية الاستورج
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_delete_rounded, color: Color(0xFF16A34A), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '💡 الحذف التلقائي الشامل مفعل: فور وصول تاريخ الانتهاء، يتم مسح الإعلان من الداتا بيز وحذف صورته نهائياً من الاستورج تلقائياً لتوفير المساحة وعدم التراكم.',
                              style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF14532D)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. اختيار نوع الإعلان
                    Text('1. حدد نوع الجهة المعلنة:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypeSelectOption(
                            label: 'طبيب مسجل 🩺',
                            sub: 'إعلان لطبيب معتمد يفتح بروفايله للكشف',
                            isSelected: adType == 'DOCTOR',
                            color: AdminColors.primaryDark,
                            onTap: () {
                              setDialogState(() {
                                adType = 'DOCTOR';
                                badgeCtrl.text = 'طبيب مميز ⭐';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTypeSelectOption(
                            label: 'صيدلية مسجلة 💊',
                            sub: 'إعلان لصيدلية لطلب الأدوية أونلاين',
                            isSelected: adType == 'PHARMACY',
                            color: Colors.teal.shade800,
                            onTap: () {
                              setDialogState(() {
                                adType = 'PHARMACY';
                                badgeCtrl.text = 'خصم حصري 🔥';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTypeSelectOption(
                            label: 'إعلان عام / خارجي 🏷️',
                            sub: 'عروض مختبرات أو حملات توعية مع رفع صورة',
                            isSelected: adType == 'GENERAL',
                            color: Colors.purple.shade700,
                            onTap: () {
                              setDialogState(() {
                                adType = 'GENERAL';
                                badgeCtrl.text = 'رعاية طبية 🩺';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 2. البحث والفلترة واختيار الطبيب أو الصيدلية
                    if (adType == 'DOCTOR') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('2. اختيار الطبيب المعتمد (بحث متقدم بالاسم أو الهاتف):', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark)),
                          if (selectedDoctor != null)
                            TextButton.icon(
                              icon: const Icon(Icons.sync_rounded, size: 16, color: AdminColors.primaryDark),
                              label: Text('تغيير الطبيب 🔍', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                              onPressed: () async {
                                final doc = await _openDoctorSearchDialog(dialogCtx);
                                if (doc != null) {
                                  setDialogState(() {
                                    selectedDoctor = doc;
                                    final prof = doc['profiles'] as Map<String, dynamic>?;
                                    final name = prof?['full_name'] ?? '';
                                    final spec = doc['specialty'] ?? '';
                                    titleCtrl.text = 'احجز كشفك الآن مع د. $name';
                                    subtitleCtrl.text = 'استشاري $spec - رعاية طبية متكاملة بأحدث التقنيات';
                                  });
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (selectedDoctor == null)
                        InkWell(
                          onTap: () async {
                            final doc = await _openDoctorSearchDialog(dialogCtx);
                            if (doc != null) {
                              setDialogState(() {
                                selectedDoctor = doc;
                                final prof = doc['profiles'] as Map<String, dynamic>?;
                                final name = prof?['full_name'] ?? '';
                                final spec = doc['specialty'] ?? '';
                                titleCtrl.text = 'احجز كشفك الآن مع د. $name';
                                subtitleCtrl.text = 'استشاري $spec - رعاية طبية متكاملة بأحدث التقنيات';
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: AdminColors.backgroundCanvas,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AdminColors.primaryDark, width: 1.2, style: BorderStyle.solid),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_rounded, color: AdminColors.primaryDark, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  'اضغط هنا للبحث واختيار الطبيب (بالاسم الكامل، التخصص، أو رقم الموبايل) 🔍',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        // بطاقة الطبيب المختار
                        Builder(builder: (_) {
                          final prof = selectedDoctor!['profiles'] as Map<String, dynamic>?;
                          final name = prof?['full_name'] ?? 'طبيب';
                          final spec = selectedDoctor!['specialty'] ?? 'عام';
                          final phone = prof?['phone'] ?? '';
                          final avatar = prof?['avatar_url'] as String?;
                          final rating = (selectedDoctor!['rating_avg'] as num?)?.toDouble() ?? 0.0;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AdminColors.cardBorderMint.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AdminColors.primaryDark, width: 1.2),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.15),
                                  backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                                  child: (avatar == null || avatar.isEmpty) ? const Icon(Icons.person_rounded, size: 30, color: AdminColors.primaryDark) : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('د. $name', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14, color: AdminColors.textPrimary)),
                                      Row(
                                        children: [
                                          Text('التخصص: $spec', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                                          if (phone.isNotEmpty) ...[
                                            const SizedBox(width: 12),
                                            Text('📞 الهاتف: $phone', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                                          ],
                                          if (rating > 0) ...[
                                            const SizedBox(width: 12),
                                            Text('⭐ $rating', style: GoogleFonts.cairo(fontSize: 11.5, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: AdminColors.primaryDark, side: const BorderSide(color: AdminColors.primaryDark)),
                                  icon: const Icon(Icons.search_rounded, size: 16),
                                  label: Text('تغيير 🔄', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    final doc = await _openDoctorSearchDialog(dialogCtx);
                                    if (doc != null) {
                                      setDialogState(() {
                                        selectedDoctor = doc;
                                        final prof2 = doc['profiles'] as Map<String, dynamic>?;
                                        final name2 = prof2?['full_name'] ?? '';
                                        final spec2 = doc['specialty'] ?? '';
                                        titleCtrl.text = 'احجز كشفك الآن مع د. $name2';
                                        subtitleCtrl.text = 'استشاري $spec2 - رعاية طبية متكاملة بأحدث التقنيات';
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 18),
                    ] else if (adType == 'PHARMACY') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('2. اختيار الصيدلية المعتمدة (بحث متقدم بالاسم أو المحافظة أو الهاتف):', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade800)),
                          if (selectedPharmacy != null)
                            TextButton.icon(
                              icon: Icon(Icons.sync_rounded, size: 16, color: Colors.teal.shade800),
                              label: Text('تغيير الصيدلية 🔍', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                              onPressed: () async {
                                final pharm = await _openPharmacySearchDialog(dialogCtx);
                                if (pharm != null) {
                                  setDialogState(() {
                                    selectedPharmacy = pharm;
                                    final name = pharm['name'] ?? '';
                                    final gov = pharm['governorate'] ?? '';
                                    titleCtrl.text = 'خصم خاص وتوصيل فوري من $name';
                                    subtitleCtrl.text = 'اطلب جميع أدويتك ومستلزماتك أونلاين - $gov';
                                  });
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (selectedPharmacy == null)
                        InkWell(
                          onTap: () async {
                            final pharm = await _openPharmacySearchDialog(dialogCtx);
                            if (pharm != null) {
                              setDialogState(() {
                                selectedPharmacy = pharm;
                                final name = pharm['name'] ?? '';
                                final gov = pharm['governorate'] ?? '';
                                titleCtrl.text = 'خصم خاص وتوصيل فوري من $name';
                                subtitleCtrl.text = 'اطلب جميع أدويتك ومستلزماتك أونلاين - $gov';
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: AdminColors.backgroundCanvas,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.teal.shade800, width: 1.2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_rounded, color: Colors.teal.shade800, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  'اضغط هنا للبحث واختيار الصيدلية (بالاسم، المحافظة، أو رقم الموبايل) 🔍',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade800),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Builder(builder: (_) {
                          final name = selectedPharmacy!['name'] ?? 'صيدلية';
                          final gov = selectedPharmacy!['governorate'] ?? '';
                          final prof = selectedPharmacy!['profiles'] as Map<String, dynamic>?;
                          final phone = prof?['phone'] ?? '';
                          final avatar = prof?['avatar_url'] as String?;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.teal.shade800, width: 1.2),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.teal.shade100,
                                  backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                                  child: (avatar == null || avatar.isEmpty) ? Icon(Icons.local_pharmacy_rounded, size: 30, color: Colors.teal.shade800) : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14, color: AdminColors.textPrimary)),
                                      Row(
                                        children: [
                                          Text('المحافظة: $gov', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                                          if (phone.isNotEmpty) ...[
                                            const SizedBox(width: 12),
                                            Text('📞 الهاتف: $phone', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.teal.shade800, side: BorderSide(color: Colors.teal.shade800)),
                                  icon: const Icon(Icons.search_rounded, size: 16),
                                  label: Text('تغيير 🔄', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    final pharm = await _openPharmacySearchDialog(dialogCtx);
                                    if (pharm != null) {
                                      setDialogState(() {
                                        selectedPharmacy = pharm;
                                        final name2 = pharm['name'] ?? '';
                                        final gov2 = pharm['governorate'] ?? '';
                                        titleCtrl.text = 'خصم خاص وتوصيل فوري من $name2';
                                        subtitleCtrl.text = 'اطلب جميع أدويتك ومستلزماتك أونلاين - $gov2';
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 18),
                    ],

                    // 3. رفع صورة البنر الإعلاني من الجهاز (Upload Banner Image)
                    Text(
                      adType == 'GENERAL' ? '2. رفع صورة البنر الإعلاني من جهازك 🖼️:' : 'صورة مخصصة للبنر (اختياري - أو تترك لاستخدام البروفايل تلقائياً):',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminColors.backgroundCanvas,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AdminColors.cardBorder, width: 1.2),
                      ),
                      child: Column(
                        children: [
                          if (pickedImageBytes != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                pickedImageBytes!,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: AdminColors.success, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      'تم اختيار: ${pickedImageName ?? "صورة البنر"} (${(pickedImageBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB)',
                                      style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: AdminColors.emergency),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                  label: Text('حذف الصورة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                  onPressed: () {
                                    setDialogState(() {
                                      pickedImageBytes = null;
                                      pickedImageName = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ] else ...[
                            InkWell(
                              onTap: () async {
                                final picker = ImagePicker();
                                final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                                if (file != null) {
                                  final bytes = await file.readAsBytes();
                                  setDialogState(() {
                                    pickedImageBytes = bytes;
                                    pickedImageName = file.name;
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AdminColors.primaryDark.withValues(alpha: 0.5), style: BorderStyle.solid),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: AdminColors.primaryDark.withValues(alpha: 0.1), shape: BoxShape.circle),
                                      child: const Icon(Icons.cloud_upload_rounded, color: AdminColors.primaryDark, size: 32),
                                    ),
                                    const SizedBox(height: 10),
                                    Text('انقر هنا لاختيار ورفع صورة البنر الإعلاني من جهازك 🖼️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark)),
                                    const SizedBox(height: 4),
                                    Text('يدعم صيغ JPG, PNG, WebP (سيتم حفظها في الاستورج ومسحها تلقائياً عند انتهاء الإعلان)', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textMuted)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 4. الاستهداف الجغرافي بالمحافظات
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('3. الاستهداف الجغرافي بالمحافظات 📍:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark)),
                        TextButton.icon(
                          icon: Icon(
                            selectedGovernorates.contains('الكل') ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 18,
                            color: AdminColors.primaryDark,
                          ),
                          label: Text(
                            'تحديد كل المحافظات 🇪🇬',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.primaryDark),
                          ),
                          onPressed: () {
                            setDialogState(() {
                              if (selectedGovernorates.contains('الكل')) {
                                selectedGovernorates.clear();
                              } else {
                                selectedGovernorates.clear();
                                selectedGovernorates.add('الكل');
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'اختر المحافظات التي سيظهر فيها هذا الإعلان للمرضى، أو اختر "الكل" ليظهر في جميع أنحاء مصر:',
                      style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminColors.backgroundCanvas,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.cardBorder),
                      ),
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            FilterChip(
                              label: Text('🇪🇬 كل المحافظات', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                              selected: selectedGovernorates.contains('الكل'),
                              selectedColor: AdminColors.primaryDark,
                              labelStyle: TextStyle(color: selectedGovernorates.contains('الكل') ? Colors.white : AdminColors.textPrimary),
                              onSelected: (val) {
                                setDialogState(() {
                                  if (val) {
                                    selectedGovernorates.clear();
                                    selectedGovernorates.add('الكل');
                                  } else {
                                    selectedGovernorates.remove('الكل');
                                  }
                                });
                              },
                            ),
                            ..._egyptGovernorates.map((gov) {
                              final isSelected = selectedGovernorates.contains(gov);
                              return FilterChip(
                                label: Text(gov, style: GoogleFonts.cairo(fontSize: 11)),
                                selected: isSelected,
                                selectedColor: AdminColors.primaryDark,
                                labelStyle: TextStyle(color: isSelected ? Colors.white : AdminColors.textPrimary),
                                onSelected: (val) {
                                  setDialogState(() {
                                    selectedGovernorates.remove('الكل');
                                    if (val) {
                                      selectedGovernorates.add(gov);
                                    } else {
                                      selectedGovernorates.remove(gov);
                                    }
                                    if (selectedGovernorates.isEmpty) {
                                      selectedGovernorates.add('الكل');
                                    }
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 5. محتوى ونصوص الإعلان
                    Text('4. محتوى ونصوص الإعلان:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDialogTextField(
                            label: 'عنوان الإعلان الرئيسي 🏷️',
                            hint: 'مثال: خصم 20% على الكشف الطبي',
                            controller: titleCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDialogTextField(
                            label: 'الشارة التسويقية ⭐',
                            hint: 'طبيب مميز ⭐, خصم خاص 🔥',
                            controller: badgeCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDialogTextField(
                            label: 'أولوية الظهور 🔢',
                            hint: '10',
                            controller: priorityCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildDialogTextField(
                      label: 'العنوان الفرعي والنبذة المختصرة',
                      hint: 'تفاصيل مشجعة تظهر أسفل العنوان الرئيسي في البنر...',
                      controller: subtitleCtrl,
                    ),
                    if (adType == 'GENERAL') ...[
                      const SizedBox(height: 10),
                      _buildDialogTextField(
                        label: 'الوصف التفصيلي للعرض (يظهر عند ضغط المريض على الإعلان)',
                        hint: 'اكتب تفاصيل العرض الكاملة، الشروط، وأرقام التواصل...',
                        controller: descCtrl,
                      ),
                    ],
                    const SizedBox(height: 18),

                    // 6. موعد الانتهاء الصارم
                    Text('5. موعد انتهاء الإعلان والمسح التلقائي ⏱️:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildDurationQuickBtn(
                          label: 'أسبوع (7 أيام)',
                          isSelected: selectedExpiry.difference(DateTime.now()).inDays == 7,
                          onTap: () => setDialogState(() => selectedExpiry = DateTime.now().add(const Duration(days: 7))),
                        ),
                        const SizedBox(width: 8),
                        _buildDurationQuickBtn(
                          label: 'أسبوعان (14 يوماً)',
                          isSelected: selectedExpiry.difference(DateTime.now()).inDays == 14,
                          onTap: () => setDialogState(() => selectedExpiry = DateTime.now().add(const Duration(days: 14))),
                        ),
                        const SizedBox(width: 8),
                        _buildDurationQuickBtn(
                          label: 'شهر كامل (30 يوماً)',
                          isSelected: selectedExpiry.difference(DateTime.now()).inDays == 30,
                          onTap: () => setDialogState(() => selectedExpiry = DateTime.now().add(const Duration(days: 30))),
                        ),
                        const SizedBox(width: 8),
                        _buildDurationQuickBtn(
                          label: '3 أشهر (90 يوماً)',
                          isSelected: selectedExpiry.difference(DateTime.now()).inDays == 90,
                          onTap: () => setDialogState(() => selectedExpiry = DateTime.now().add(const Duration(days: 90))),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.backgroundCanvas,
                            foregroundColor: AdminColors.primaryDark,
                            elevation: 0,
                            side: const BorderSide(color: AdminColors.primaryDark),
                          ),
                          icon: const Icon(Icons.calendar_month_rounded, size: 16),
                          label: Text('تاريخ مخصص', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: dialogCtx,
                              initialDate: selectedExpiry,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              if (!dialogCtx.mounted) return;
                              final time = await showTimePicker(
                                context: dialogCtx,
                                initialTime: TimeOfDay.fromDateTime(selectedExpiry),
                              );
                              if (time != null) {
                                setDialogState(() {
                                  selectedExpiry = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AdminColors.backgroundCanvas, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm_on_rounded, size: 18, color: AdminColors.primaryDark),
                          const SizedBox(width: 8),
                          Text(
                            'تاريخ الانتهاء والمسح النهائي: ${intl.DateFormat('yyyy/MM/dd - hh:mm a').format(selectedExpiry)}',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isUploadingImage
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.rocket_launch_rounded, size: 18),
                label: Text(isUploadingImage ? 'جارٍ رفع الصورة ونشر الإعلان...' : 'نشر وبث الإعلان فوراً 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: isUploadingImage
                    ? null
                    : () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('يرجى كتابة عنوان الإعلان أولاً'), backgroundColor: AdminColors.warning),
                          );
                          return;
                        }

                        if (adType == 'DOCTOR' && selectedDoctor == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('يرجى اختيار الطبيب المراد الترويج له من البحث'), backgroundColor: AdminColors.warning),
                          );
                          return;
                        }

                        if (adType == 'PHARMACY' && selectedPharmacy == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('يرجى اختيار الصيدلية المراد الترويج لها من البحث'), backgroundColor: AdminColors.warning),
                          );
                          return;
                        }

                        setDialogState(() => isUploadingImage = true);

                        try {
                          String finalImageUrl = '';

                          // رفع الصورة إلى Supabase Storage في bucket 'promotional_ads'
                          if (pickedImageBytes != null) {
                            final ext = pickedImageName?.split('.').last.toLowerCase() ?? 'jpg';
                            final cleanExt = (ext == 'png' || ext == 'webp') ? ext : 'jpg';
                            final fileName = 'promo_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}.$cleanExt';

                            await _client.storage.from('promotional_ads').uploadBinary(
                              fileName,
                              pickedImageBytes!,
                              fileOptions: FileOptions(contentType: 'image/$cleanExt', upsert: true),
                            );

                            finalImageUrl = _client.storage.from('promotional_ads').getPublicUrl(fileName);
                          } else if (adType == 'DOCTOR') {
                            final prof = selectedDoctor!['profiles'] as Map<String, dynamic>?;
                            finalImageUrl = prof?['avatar_url'] as String? ?? '';
                          } else if (adType == 'PHARMACY') {
                            final prof = selectedPharmacy!['profiles'] as Map<String, dynamic>?;
                            finalImageUrl = prof?['avatar_url'] as String? ?? '';
                          }

                          final payload = {
                            'ad_type': adType,
                            'doctor_id': adType == 'DOCTOR' ? selectedDoctor!['id'] : null,
                            'pharmacy_id': adType == 'PHARMACY' ? selectedPharmacy!['id'] : null,
                            'title': title,
                            'subtitle': subtitleCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'image_url': finalImageUrl,
                            'target_governorates': selectedGovernorates.toList(),
                            'action_url': actionUrlCtrl.text.trim(),
                            'badge_text': badgeCtrl.text.trim().isEmpty ? 'مميز ⭐' : badgeCtrl.text.trim(),
                            'priority': int.tryParse(priorityCtrl.text.trim()) ?? 0,
                            'expires_at': selectedExpiry.toUtc().toIso8601String(),
                            'is_active': true,
                            'created_at': DateTime.now().toUtc().toIso8601String(),
                          };

                          await _client.from('promotional_ads').insert(payload);

                          AdminAuditService.log(
                            actionType: 'إطلاق إعلان ممول مع رفع صورة بالاستورج',
                            targetType: 'PROMOTIONAL_AD',
                            targetName: title,
                            details: {
                              'ad_type': adType,
                              'doctor_id': selectedDoctor?['id'],
                              'pharmacy_id': selectedPharmacy?['id'],
                              'image_url': finalImageUrl,
                              'governorates': selectedGovernorates.toList(),
                              'expires_at': selectedExpiry.toIso8601String(),
                            },
                          );

                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }
                          await _loadAllData(silent: true);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🎉 تم إطلاق وبث الإعلان بنجاح ورفع صورته للاستورج! 🚀'),
                                backgroundColor: AdminColors.success,
                                duration: Duration(seconds: 4),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isUploadingImage = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('فشل نشر الإعلان: $e'), backgroundColor: AdminColors.emergency),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTypeSelectOption({
    required String label,
    required String sub,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : AdminColors.backgroundCanvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : AdminColors.cardBorder, width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: isSelected ? color : AdminColors.textMuted, size: 18),
                const SizedBox(width: 8),
                Text(label, style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: isSelected ? color : AdminColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(sub, style: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.cairo(fontSize: 12.5),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AdminColors.backgroundCanvas,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.cardBorder)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildDurationQuickBtn({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primaryDark : AdminColors.backgroundCanvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AdminColors.primaryDark : AdminColors.cardBorder),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AdminColors.textPrimary),
        ),
      ),
    );
  }
}
