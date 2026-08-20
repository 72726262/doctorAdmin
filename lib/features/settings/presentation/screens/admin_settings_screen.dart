import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _client = AdminSupabaseConfig.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _paymentMethods = [];

  @override
  void initState() {
    super.initState();
    _fetchPaymentMethods();
  }

  Future<void> _fetchPaymentMethods() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.from('payment_methods').select().order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _paymentMethods = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePaymentMethod(String id, bool currentStatus) async {
    try {
      await _client.from('payment_methods').update({'is_active': !currentStatus}).eq('id', id);
      _fetchPaymentMethods();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    }
  }

  void _showAddPaymentMethodDialog() {
    final nameController = TextEditingController();
    final detailsController = TextEditingController();
    final instructionsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('إضافة وسيلة دفع جديدة 💳', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: GoogleFonts.cairo(fontSize: 13),
                decoration: const InputDecoration(labelText: 'اسم وسيلة الدفع (مثال: محفظة فودافون كاش، إنستاباي)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailsController,
                style: GoogleFonts.cairo(fontSize: 13),
                decoration: const InputDecoration(labelText: 'بيانات الحساب / رقم المحفظة / المعرف'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: instructionsController,
                style: GoogleFonts.cairo(fontSize: 13),
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'تعليمات التحويل للأطباء'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameController.text.trim();
              final details = detailsController.text.trim();
              if (name.isEmpty || details.isEmpty) return;

              Navigator.pop(ctx);
              try {
                await _client.from('payment_methods').insert({
                  'name': name,
                  'account_details': details,
                  'instructions': instructionsController.text.trim(),
                  'is_active': true,
                });
                _fetchPaymentMethods();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 تمت إضافة وسيلة الدفع بنجاح!'), backgroundColor: AdminColors.success));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
                }
              }
            },
            child: Text('حفظ الوسيلة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AdminColors.primaryDark.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.settings_rounded, color: AdminColors.primaryDark, size: 24),
              ),
              const SizedBox(width: 10),
              Text('إعدادات المنظومة وطرق السداد المالي', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('إدارة وسائل الدفع المعتمدة لاستقبال اشتراكات الأطباء ومراقبة حالة البنية التحتية والسيرفر', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),

          const SizedBox(height: 24),

          // Infrastructure Info Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.cardBorderMint),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('معلومات البنية التحتية والسيرفر ⚙️', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 12),
                _buildSystemInfoRow('قاعدة البيانات الرئيسية:', 'PostgreSQL 17 (Supabase Enterprise Managed)'),
                const SizedBox(height: 6),
                _buildSystemInfoRow('نطاق السيرفر (Supabase URL):', 'https://ztpqokvytjmlgyxhuhrv.supabase.co'),
                const SizedBox(height: 6),
                _buildSystemInfoRow('نظام المصادقة والتسجيل:', 'Firebase Phone Auth + Supabase Master Auth'),
                const SizedBox(height: 6),
                _buildSystemInfoRow('قنوات البث والتحديث اللحظي:', 'Supabase Realtime WebSockets Enabled 🟢'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Payment Methods Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('حسابات الدفع وتلقي اشتراكات الأطباء:', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.textPrimary)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('إضافة وسيلة دفع جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: _showAddPaymentMethodDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
          else if (_paymentMethods.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AdminColors.surfaceWhite, borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text('لا توجد طرق دفع مسجلة حالياً. اضغط على الزر أعلاه لإضافة فودافون كاش أو إنستاباي.', style: GoogleFonts.cairo(color: AdminColors.textSecondary))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _paymentMethods.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final m = _paymentMethods[index];
                final isActive = m['is_active'] as bool? ?? true;

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isActive ? AdminColors.cardBorderMint : Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AdminColors.primaryDark.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['name'] ?? '', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 14)),
                            Text('رقم الحساب / المحفظة: ${m['account_details'] ?? ''}', style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                            if (m['instructions'] != null && m['instructions'] != '')
                              Text('التعليمات: ${m['instructions']}', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                          ],
                        ),
                      ),
                      Switch(
                        value: isActive,
                        activeTrackColor: AdminColors.success,
                        onChanged: (val) => _togglePaymentMethod(m['id'], isActive),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSystemInfoRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
