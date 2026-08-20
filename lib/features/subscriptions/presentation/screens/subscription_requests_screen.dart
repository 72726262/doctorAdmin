import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class SubscriptionRequestsScreen extends StatefulWidget {
  const SubscriptionRequestsScreen({super.key});

  @override
  State<SubscriptionRequestsScreen> createState() => _SubscriptionRequestsScreenState();
}

class _SubscriptionRequestsScreenState extends State<SubscriptionRequestsScreen> {
  final _client = AdminSupabaseConfig.client;

  Future<List<Map<String, dynamic>>> _fetchSubscriptionRequests() async {
    final res = await _client.from('subscription_requests').select('''
      id,
      doctor_id,
      amount_paid,
      receipt_image_url,
      status,
      created_at,
      profiles!inner(full_name, phone, governorate)
    ''').order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> _approveSubscription(String reqId, String doctorId) async {
    // 1. Update request status to APPROVED
    await _client.from('subscription_requests').update({'status': 'APPROVED'}).eq('id', reqId);

    // 2. Extend doctor subscription
    final expiresAt = DateTime.now().add(const Duration(days: 30)).toIso8601String();
    await _client.from('doctors').update({
      'subscription_status': 'ACTIVE',
      'subscription_expires_at': expiresAt,
    }).eq('id', doctorId);

    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 تم اعتماد إيصال السداد وتفعيل اشتراك الطبيب لـ 30 يوماً!'),
          backgroundColor: AdminColors.success,
        ),
      );
    }
  }

  Future<void> _rejectSubscription(String reqId) async {
    await _client.from('subscription_requests').update({'status': 'REJECTED'}).eq('id', reqId);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم رفض الإيصال'),
          backgroundColor: AdminColors.emergency,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchSubscriptionRequests(),
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
                  child: const Icon(Icons.receipt_long_rounded, size: 64, color: AdminColors.primaryDark),
                ),
                const SizedBox(height: 20),
                const Text(
                  'لا توجد طلبات اشتراك أو إيصالات سداد معلقة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'عند قيام أي طبيب برفع إيصال تحويل فودافون كاش أو فوري، سيظهر هنا فوراً للفحص والتفعيل',
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
            final item = list[index];
            final profile = item['profiles'] as Map<String, dynamic>? ?? {};
            final status = item['status'] as String? ?? 'PENDING';
            final isPending = status == 'PENDING';

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AdminColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AdminColors.cardBorderMint),
              ),
              child: Row(
                children: [
                  // صورة مصغرة للإيصال قابلة للنقر للتكبير
                  InkWell(
                    onTap: () => _showReceiptZoomDialog(context, item['receipt_image_url']),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 70,
                        height: 70,
                        color: AdminColors.accentMintLight,
                        child: item['receipt_image_url'] != null
                            ? Image.network(item['receipt_image_url']!, fit: BoxFit.cover)
                            : const Icon(Icons.receipt_rounded, color: AdminColors.primaryDark),
                      ),
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
                              'د. ${profile['full_name'] ?? 'طبيب'}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const SizedBox(width: 10),
                            _buildStatusBadge(status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'المبلغ المحول: ${item['amount_paid'] ?? 200} ج.م • هاتف: +20 ${profile['phone'] ?? ''}',
                          style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'تاريخ الرفع: ${(item['created_at'] as String?)?.split('T').first ?? ''}',
                          style: const TextStyle(fontSize: 11.5, color: AdminColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (isPending)
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _approveSubscription(item['id'], item['doctor_id']),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('تأكيد السداد وتفعيل الباقة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _rejectSubscription(item['id']),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AdminColors.emergency),
                            foregroundColor: AdminColors.emergency,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          child: const Text('رفض'),
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

  Widget _buildStatusBadge(String status) {
    Color bg = AdminColors.warningLight;
    Color fg = AdminColors.warning;
    String text = 'قيد المراجعة';

    if (status == 'APPROVED') {
      bg = AdminColors.successLight;
      fg = AdminColors.success;
      text = 'تم الاعتماد والتفعيل ✅';
    } else if (status == 'REJECTED') {
      bg = AdminColors.emergencyLight;
      fg = AdminColors.emergency;
      text = 'مرفوض ❌';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _showReceiptZoomDialog(BuildContext context, String? imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 550,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'معاينة إيصال السداد والتحويل',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.contain, height: 400)
                    : Container(
                        height: 200,
                        color: AdminColors.accentMintLight,
                        alignment: Alignment.center,
                        child: const Text('لم ترفق صورة إيصال'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
