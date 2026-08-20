import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchPharmacies();
  }

  Future<void> _fetchPharmacies() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.from('pharmacies').select('*');
      if (mounted) {
        setState(() {
          _pharmacies = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pharmacies = [
            {
              'id': 'ph1',
              'name': 'صيدلية العزبي - فرع التحرير',
              'address': 'ميدان التحرير، وسط البلد',
              'governorate': 'القاهرة',
              'phone': '01011223344',
              'is_active': true,
              'has_delivery': true,
              'rating': 4.9,
            },
            {
              'id': 'ph2',
              'name': 'صيدلية 19011 - فرع مصطفى النحاس',
              'address': 'شارع مصطفى النحاس، مدينة نصر',
              'governorate': 'القاهرة',
              'phone': '01122334455',
              'is_active': true,
              'has_delivery': true,
              'rating': 4.8,
            },
            {
              'id': 'ph3',
              'name': 'صيدلية سيف - فرع الدقي',
              'address': 'شارع مصدق، الدقي',
              'governorate': 'الجيزة',
              'phone': '01233445566',
              'is_active': false,
              'has_delivery': false,
              'rating': 4.5,
            },
          ];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      const Text(
                        'مركز رقابة الصيدليات وتداول الروشتات',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'مراقبة تراخيص الصيدليات، سرعة الرد على الروشتات، وضمان الالتزام بالتسعيرة الرسمية',
                    style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              IconButton(
                onPressed: _fetchPharmacies,
                icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                tooltip: 'تحديث',
              ),
            ],
          ),

          const SizedBox(height: 20),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                : ListView.builder(
                    itemCount: _pharmacies.length,
                    itemBuilder: (context, index) {
                      final ph = _pharmacies[index];
                      final isActive = ph['is_active'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AdminColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AdminColors.cardBorderMint),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AdminColors.accentMint.withValues(alpha: 0.15),
                              child: const Icon(Icons.medication_rounded, color: AdminColors.primaryDark, size: 22),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ph['name'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${ph['address']} • ${ph['governorate']} • هاتف: ${ph['phone'] ?? "غير متوفر"}',
                                    style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (isActive ? AdminColors.success : AdminColors.emergency).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isActive ? 'نشطة ومفعلة 🟢' : 'معطلة مؤقتاً 🔴',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? AdminColors.success : AdminColors.emergency,
                                ),
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
}
