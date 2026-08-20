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
      await _client.from('profiles').update({'is_approved': !currentStatus}).eq('id', pharmacyId);
      _fetchPharmacies();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? '🟢 تم تفعيل واعتماد الصيدلية' : '⏸️ تم تجميد الصيدلية'),
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
                          final avail = prod['availability_status'] ?? 'AVAILABLE';
                          final isAvail = avail == 'AVAILABLE';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AdminColors.backgroundCanvas,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AdminColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    prod['image_url'] ?? 'https://images.unsplash.com/photo-1584308666744-24d5c474f2ae?w=100',
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 44,
                                      height: 44,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.medication_rounded, color: Colors.grey),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(prod['name'] ?? '', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text(
                                        'الفئة: ${_translateCategory(prod['category'] ?? '')} | ${prod['description'] ?? ''}',
                                        style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // Price & Status
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${prod['price']} ج.م', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, color: AdminColors.primaryDark, fontSize: 14)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isAvail ? AdminColors.accentMintLight : Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isAvail ? 'متوفر بالمخزون' : 'غير متوفر',
                                        style: GoogleFonts.cairo(fontSize: 10, color: isAvail ? AdminColors.success : AdminColors.emergency, fontWeight: FontWeight.bold),
                                      ),
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
        ),
      ),
    );
  }

  String _translateCategory(String cat) {
    switch (cat) {
      case 'MEDICINES':
        return 'أدوية ومسكنات';
      case 'VITAMINS':
        return 'فيتامينات ومكملات';
      case 'SKINCARE':
        return 'عناية بالبشرة';
      case 'EQUIPMENT':
        return 'أجهزة ومستلزمات';
      case 'BABY_CARE':
        return 'أمومة ورعاية أطفال';
      default:
        return cat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _pharmacies.where((p) {
      final name = p['name']?.toString() ?? '';
      final gov = p['governorate']?.toString() ?? '';

      final matchGov = _governorateFilter == 'الكل' || gov == _governorateFilter;
      final matchSearch = _searchQuery.isEmpty || name.contains(_searchQuery) || gov.contains(_searchQuery);

      return matchGov && matchSearch;
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
                          color: AdminColors.accentMint.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.local_pharmacy_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'مركز رقابة الصيدليات وتداول الروشتات والمخزون',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'مراقبة سلاسل الصيدليات المعتمدة، فحص كتالوج الأدوية والمستلزمات، والتأكد من توافر المخزون',
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
                label: Text('تحديث الصيدليات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchPharmacies,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Search & Filter
          Row(
            children: [
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AdminColors.surfaceWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AdminColors.cardBorder)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _governorateFilter,
                    style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    items: ['الكل', 'القاهرة', 'الجيزة', 'الإسكندرية', 'الدقهلية', 'الغربية'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (val) => setState(() => _governorateFilter = val ?? 'الكل'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Pharmacies List
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
                          final isApproved = profile['is_approved'] as bool? ?? true;

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
                                // Icon / Avatar
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AdminColors.accentMint.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.local_pharmacy_rounded, color: AdminColors.primaryDark, size: 26),
                                ),
                                const SizedBox(width: 14),

                                // Pharmacy Info
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            pha['name'] ?? 'الصيدلية',
                                            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isApproved ? AdminColors.accentMintLight : Colors.red.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isApproved ? 'معتمدة 🟢' : 'مجمدة 🔴',
                                              style: GoogleFonts.cairo(
                                                fontSize: 10.5,
                                                color: isApproved ? AdminColors.success : AdminColors.emergency,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '📍 ${pha['governorate']} - ${pha['address_text']}',
                                        style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                                      ),
                                      Text(
                                        '📦 عدد الأصناف والمنتجات: ${products.length} صنف | 📞 هاتف الصيدلية: ${profile['phone'] ?? 'غير متوفر'}',
                                        style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.primaryDark, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),

                                // Rating
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${pha['rating_avg'] ?? 4.8}',
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900),
                                      ),
                                      Text(
                                        ' (${pha['rating_count'] ?? 0})',
                                        style: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Inspect Catalog Button
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AdminColors.primaryDark,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.inventory_2_rounded, size: 16),
                                  label: Text('فحص الأدوية (${products.length})', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () => _inspectProductsModal(pha),
                                ),
                                const SizedBox(width: 8),

                                // Toggle Status Button
                                IconButton(
                                  tooltip: isApproved ? 'تجميد الصيدلية' : 'تفعيل الصيدلية',
                                  icon: Icon(
                                    isApproved ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                                    color: isApproved ? AdminColors.warning : AdminColors.success,
                                    size: 22,
                                  ),
                                  onPressed: () => _togglePharmacyStatus(pha['id'], isApproved),
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
