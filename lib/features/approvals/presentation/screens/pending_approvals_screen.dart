import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final _client = AdminSupabaseConfig.client;

  Future<List<Map<String, dynamic>>> _fetchPendingProfiles() async {
    final res = await _client
        .from('profiles')
        .select()
        .eq('is_approved', false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> _approveUser(String userId) async {
    await _client.from('profiles').update({'is_approved': true}).eq('id', userId);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 تم اعتماد الحساب وتفعيله بنجاح!'),
          backgroundColor: AdminColors.success,
        ),
      );
    }
  }

  Future<void> _rejectUser(String userId) async {
    await _client.from('profiles').delete().eq('id', userId);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم رفض الطلب وحذف البيانات'),
          backgroundColor: AdminColors.emergency,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchPendingProfiles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark));
        }

        final list = snapshot.data ?? [];

        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AdminColors.accentMintLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_outline_rounded, size: 64, color: AdminColors.success),
                ),
                const SizedBox(height: 20),
                const Text(
                  'رائع! لا توجد طلبات اعتماد معلقة حالياً',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'جميع الأطباء والصيدليات المسجلين تم مراجعتهم واعتمادهم',
                  style: TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final user = list[index];
            final role = user['role'] as String? ?? 'DOCTOR';
            final isDoctor = role == 'DOCTOR';

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AdminColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AdminColors.cardBorderMint),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: isDoctor ? AdminColors.primaryDark : AdminColors.accentCyan,
                    child: Icon(
                      isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              user['full_name'] as String? ?? 'بدون اسم',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDoctor ? AdminColors.accentMintLight : const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isDoctor ? 'طبيب جديد' : 'صيدلية جديدة',
                                style: TextStyle(
                                  color: isDoctor ? AdminColors.primaryDark : const Color(0xFF0369A1),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'المحافظة: ${user['governorate'] ?? 'غير محدد'} • هاتف: +20 ${user['phone'] ?? ''}',
                          style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _approveUser(user['id'] as String),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('موافقة واعتماد'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _rejectUser(user['id'] as String),
                        icon: const Icon(Icons.close_rounded, size: 18, color: AdminColors.emergency),
                        label: const Text('رفض', style: TextStyle(color: AdminColors.emergency)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AdminColors.emergency),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
