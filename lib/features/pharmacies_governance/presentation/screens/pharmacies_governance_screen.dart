import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class PharmaciesGovernanceScreen extends StatefulWidget {
  const PharmaciesGovernanceScreen({super.key});

  @override
  State<PharmaciesGovernanceScreen> createState() => _PharmaciesGovernanceScreenState();
}

class _PharmaciesGovernanceScreenState extends State<PharmaciesGovernanceScreen> {
  final _client = AdminSupabaseConfig.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pharmacies = [];
  String _searchQuery = '';
  String _governorateFilter = 'الكل';
  String _statusFilter = 'الكل';

  @override
  void initState() {
    super.initState();
    _fetchPharmacies();
  }

  Future<void> _fetchPharmacies() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.from('pharmacies').select('''
        id,
        name,
        governorate,
        address_text,
        rating_avg,
        rating_count,
        subscription_status,
        has_delivery,
        profiles (
          id,
          full_name,
          phone,
          avatar_url,
          is_approved
        ),
        products (
          id,
          name,
          category,
          price,
          description,
          image_url,
          availability_status
        )
      ''').order('rating_avg', ascending: false);

      if (mounted) {
        setState(() {
          _pharmacies = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePharmacyStatus(String pharmacyId, bool currentStatus) async {
    try {
      await _client.rpc('admin_toggle_entity_approval', params: {
        'p_id': pharmacyId,
        'p_is_approved': !currentStatus,
      });

      await _client.from('profiles').update({'is_approved': !currentStatus}).eq('id', pharmacyId);
      await _client.from('pharmacies').update({
        'subscription_status': !currentStatus ? 'ACTIVE' : 'SUSPENDED'
      }).eq('id', pharmacyId);

      await _fetchPharmacies();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? '🟢 تم تفعيل واعتماد الصيدلية بنجاح' : '⏸️ تم تجميد وإيقاف الصيدلية بنجاح'),
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

  void _inspectProductsModal(Map<String, dynamic> pha) {
    final products = (pha['products'] as List?) ?? [];
    final phaName = pha['name'] ?? 'الصيدلية';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 700,
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AdminColors.accentMintLight, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.inventory_2_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('كتالوج أدوية ومنتجات: $phaName', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w900)),
                          Text('إجمالي الأصناف المسجلة: ${products.length} صنف', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Product List
              Expanded(
                child: products.isEmpty
                    ? Center(child: Text('لا توجد منتجات مسجلة لهذه الصيدلية حالياً', style: GoogleFonts.cairo(color: AdminColors.textSecondary)))
                    : ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final prod = products[index];
                          final isAvailable = prod['availability_status'] == 'AVAILABLE';
                          final isLow = prod['availability_status'] == 'LOW_STOCK';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AdminColors.backgroundCanvas,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminColors.cardBorder),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AdminColors.primaryDark.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.medication_rounded, color: AdminColors.primaryDark, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(prod['name'] ?? 'منتج', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                        Text('الفئة: ${prod['category']} • السعر: ${prod['price']} ج.م', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                                      ],
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isAvailable
                                        ? AdminColors.accentMintLight
                                        : isLow
                                            ? Colors.amber.withValues(alpha: 0.15)
                                            : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isAvailable ? 'متوفر بالمخزون 🟢' : isLow ? 'كمية محدودة ⚠️' : 'غير متوفر 🔴',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isAvailable ? AdminColors.success : isLow ? Colors.amber.shade900 : AdminColors.emergency,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إغلاق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
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
    final filtered = _pharmacies.where((p) {
      final profile = p['profiles'] as Map<String, dynamic>? ?? {};
      final name = p['name']?.toString() ?? profile['full_name']?.toString() ?? '';
      final gov = p['governorate']?.toString() ?? profile['governorate']?.toString() ?? '';
      final isApproved = (profile['is_approved'] == true) &&
          (p['subscription_status'] != 'SUSPENDED' && p['subscription_status'] != 'FROZEN');

      final matchGov = _governorateFilter == 'الكل' || gov == _governorateFilter;
      final matchStatus = _statusFilter == 'الكل' ||
          (_statusFilter == 'معتمد' && isApproved) ||
          (_statusFilter == 'مجمد' && !isApproved);

      final matchSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery) ||
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
                        child: const Icon(Icons.local_pharmacy_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'مركز رقابة وحوكمة الصيدليات ومتاجر الأدوية',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'متابعة الصيدليات المعتمدة، فحص المخزون والروشتات، واعتماد وتجميد الصيدليات فورياً',
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
                onPressed: _fetchPharmacies,
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
                    hintText: 'بحث باسم الصيدلية أو المحافظة...',
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

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                : filtered.isEmpty
                    ? Center(child: Text('لا توجد صيدليات مطابقة للبحث', style: GoogleFonts.cairo(color: AdminColors.textSecondary)))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final pha = filtered[index];
                          final profile = pha['profiles'] as Map<String, dynamic>? ?? {};
                          final products = (pha['products'] as List?) ?? [];
                          final isApproved = (profile['is_approved'] == true) &&
                              (pha['subscription_status'] != 'SUSPENDED' && pha['subscription_status'] != 'FROZEN');

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
                                // Icon
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AdminColors.accentMintLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.local_pharmacy_rounded, color: AdminColors.primaryDark),
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
                                            pha['name'] ?? profile['full_name'] ?? 'صيدلية المنظومة',
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
                                              isApproved ? 'معتمدة 🟢' : 'مجمدة / موقوفة 🔴',
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
                                        '📍 ${pha['governorate'] ?? 'مصر'} - ${pha['address_text'] ?? 'الشارع الرئيسي'} • 📞 ${profile['phone'] ?? 'بدون هاتف'}',
                                        style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),

                                // Products Count
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('كتالوج الأدوية:', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                                      Text('${products.length} صنف مسجل', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                                    ],
                                  ),
                                ),

                                // Delivery Status
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('خدمة التوصيل:', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                                      Text(
                                        pha['has_delivery'] == true ? 'دليفري متوفر 🛵' : 'استلام مباشر',
                                        style: GoogleFonts.cairo(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: pha['has_delivery'] == true ? AdminColors.success : AdminColors.textSecondary,
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
                                      icon: const Icon(Icons.inventory_2_outlined, color: AdminColors.primaryDark, size: 20),
                                      tooltip: 'فحص كتالوج المنتجات والأدوية',
                                      onPressed: () => _inspectProductsModal(pha),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(
                                        isApproved ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                                        color: isApproved ? AdminColors.warning : AdminColors.success,
                                        size: 22,
                                      ),
                                      tooltip: isApproved ? 'تجميد الصيدلية' : 'تفعيل الصيدلية',
                                      onPressed: () => _togglePharmacyStatus(pha['id'], isApproved),
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
