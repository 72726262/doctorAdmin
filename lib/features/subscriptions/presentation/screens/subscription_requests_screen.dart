import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class SubscriptionRequestsScreen extends StatefulWidget {
  const SubscriptionRequestsScreen({super.key});

  @override
  State<SubscriptionRequestsScreen> createState() => _SubscriptionRequestsScreenState();
}

class _SubscriptionRequestsScreenState extends State<SubscriptionRequestsScreen> {
  final _client = AdminSupabaseConfig.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.from('subscription_requests').select('''
        id,
        user_id,
        payment_method_id,
        amount,
        sender_number,
        transaction_reference,
        receipt_image_url,
        status,
        notes,
        created_at,
        profiles (
          full_name,
          phone,
          governorate,
          role
        ),
        payment_methods (
          name
        )
      ''').order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveSubscription(String reqId, String userId) async {
    try {
      // 1. Update request status to APPROVED
      await _client.from('subscription_requests').update({'status': 'APPROVED'}).eq('id', reqId);

      // 2. Extend doctor subscription 30 days
      final expiresAt = DateTime.now().add(const Duration(days: 30)).toIso8601String();
      await _client.from('doctors').update({
        'subscription_status': 'ACTIVE',
        'subscription_expires_at': expiresAt,
      }).eq('id', userId);

      _fetchRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 تم اعتماد إيصال السداد وتفعيل اشتراك الطبيب لـ 30 يوماً بنجاح!'),
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

  Future<void> _rejectSubscription(String reqId) async {
    try {
      await _client.from('subscription_requests').update({'status': 'REJECTED'}).eq('id', reqId);
      _fetchRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفض الإيصال'), backgroundColor: AdminColors.emergency),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    }
  }

  void _showReceiptInspectorModal(Map<String, dynamic> req) {
    final profile = req['profiles'] as Map<String, dynamic>? ?? {};
    final paymentMethod = req['payment_methods'] as Map<String, dynamic>? ?? {};
    final receiptUrl = req['receipt_image_url'] as String?;
    final isPending = req['status'] == 'PENDING';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 650,
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
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
                          child: const Icon(Icons.receipt_long_rounded, color: AdminColors.primaryDark, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('فحص إيصال السداد المالي', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w900)),
                            Text('مقدم الطلب: ${profile['full_name'] ?? 'طبيب'}', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Info Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem('طريقة الدفع', paymentMethod['name'] ?? 'فودافون كاش / إنستاباي'),
                    ),
                    Expanded(
                      child: _buildInfoItem('المبلغ المحول', '${req['amount'] ?? 500} ج.م'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem('رقم هاتف المحول', req['sender_number'] ?? profile['phone'] ?? 'غير متوفر'),
                    ),
                    Expanded(
                      child: _buildInfoItem('الرقم المرجعي للعملية', req['transaction_reference'] ?? 'تحويل مباشر'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Receipt Image Preview
                Text('صورة الإيصال المرفوعة:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 260,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AdminColors.cardBorder),
                  ),
                  child: (receiptUrl != null && receiptUrl.isNotEmpty)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            receiptUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                            ),
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.image_not_supported_rounded, size: 44, color: Colors.grey),
                              const SizedBox(height: 6),
                              Text('لم يتم إرفاق صورة إيصال', style: GoogleFonts.cairo(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                ),

                const SizedBox(height: 24),

                // Action Buttons
                if (isPending)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.emergency,
                          side: const BorderSide(color: AdminColors.emergency),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: Text('رفض الإيصال', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _rejectSubscription(req['id']);
                        },
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: Text('اعتماد وتفعيل 30 يوماً', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _approveSubscription(req['id'], req['user_id']);
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

  Widget _buildInfoItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AdminColors.backgroundCanvas, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
          Text(value, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
        ],
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
                        decoration: BoxDecoration(color: AdminColors.accentMintLight, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.receipt_long_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text('إدارة الاشتراكات وإيصالات السداد المالي', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('مراجعة إيصالات التحويل البنكي، فودافون كاش، وإنستاباي وتفعيل باقات الأطباء بضغطة زر', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث الطلبات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchRequests,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Requests List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                : _requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(color: AdminColors.accentMintLight, shape: BoxShape.circle),
                              child: const Icon(Icons.check_circle_outline_rounded, size: 48, color: AdminColors.success),
                            ),
                            const SizedBox(height: 16),
                            Text('لا توجد طلبات اشتراك أو إيصالات سداد حالياً', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('عندما يقوم أي طبيب بتحويل رسوم الاشتراك ورفع الإيصال، سيظهر هنا فوراً', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _requests.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final req = _requests[index];
                          final profile = req['profiles'] as Map<String, dynamic>? ?? {};
                          final paymentMethod = req['payment_methods'] as Map<String, dynamic>? ?? {};
                          final status = req['status'] ?? 'PENDING';
                          final isApproved = status == 'APPROVED';
                          final isPending = status == 'PENDING';

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AdminColors.surfaceWhite,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isPending ? AdminColors.accentCyan.withValues(alpha: 0.5) : AdminColors.cardBorderMint),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Icon
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isApproved
                                        ? AdminColors.accentMintLight
                                        : isPending
                                            ? Colors.amber.withValues(alpha: 0.12)
                                            : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isApproved
                                        ? Icons.check_circle_rounded
                                        : isPending
                                            ? Icons.hourglass_top_rounded
                                            : Icons.cancel_rounded,
                                    color: isApproved
                                        ? AdminColors.success
                                        : isPending
                                            ? Colors.amber.shade900
                                            : AdminColors.emergency,
                                    size: 24,
                                  ),
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
                                            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isApproved
                                                  ? AdminColors.accentMintLight
                                                  : isPending
                                                      ? Colors.amber.withValues(alpha: 0.15)
                                                      : Colors.red.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isApproved ? 'معتمد ومفعل 🟢' : isPending ? 'قيد المراجعة ⏳' : 'مرفوض 🔴',
                                              style: GoogleFonts.cairo(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: isApproved
                                                    ? AdminColors.success
                                                    : isPending
                                                        ? Colors.amber.shade900
                                                        : AdminColors.emergency,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'طريقة التحويل: ${paymentMethod['name'] ?? 'فودافون كاش / إنستاباي'} | المبلغ: ${req['amount'] ?? 500} ج.م',
                                        style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),

                                // Inspect Receipt Button
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AdminColors.primaryDark,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.receipt_rounded, size: 16),
                                  label: Text('فحص الإيصال', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () => _showReceiptInspectorModal(req),
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
