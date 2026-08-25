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
  bool _isSavingPrices = false;
  List<Map<String, dynamic>> _paymentMethods = [];

  // وحدات تحكم أسعار الأطباء
  final _doc1MonthCtrl = TextEditingController(text: '350');
  final _doc3MonthCtrl = TextEditingController(text: '950');
  final _doc6MonthCtrl = TextEditingController(text: '1800');
  final _doc12MonthCtrl = TextEditingController(text: '3200');

  // وحدات تحكم أسعار الصيدليات
  final _pharm1MonthCtrl = TextEditingController(text: '350');
  final _pharm3MonthCtrl = TextEditingController(text: '950');
  final _pharm6MonthCtrl = TextEditingController(text: '1800');
  final _pharm12MonthCtrl = TextEditingController(text: '3200');

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  @override
  void dispose() {
    _doc1MonthCtrl.dispose();
    _doc3MonthCtrl.dispose();
    _doc6MonthCtrl.dispose();
    _doc12MonthCtrl.dispose();
    _pharm1MonthCtrl.dispose();
    _pharm3MonthCtrl.dispose();
    _pharm6MonthCtrl.dispose();
    _pharm12MonthCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    setState(() => _isLoading = true);
    try {
      final methodsRes = await _client.from('payment_methods').select().order('created_at', ascending: true);
      final pricingRes = await _client.from('subscription_pricing_config').select();

      if (mounted) {
        setState(() {
          _paymentMethods = List<Map<String, dynamic>>.from(methodsRes as List);

          for (final row in (pricingRes as List)) {
            final id = row['id'] as String?;
            if (id == 'doctor_pricing') {
              _doc1MonthCtrl.text = (row['monthly_price'] ?? 350).toString();
              _doc3MonthCtrl.text = (row['three_months_price'] ?? 950).toString();
              _doc6MonthCtrl.text = (row['six_months_price'] ?? 1800).toString();
              _doc12MonthCtrl.text = (row['twelve_months_price'] ?? 3200).toString();
            } else if (id == 'pharmacy_pricing') {
              _pharm1MonthCtrl.text = (row['monthly_price'] ?? 350).toString();
              _pharm3MonthCtrl.text = (row['three_months_price'] ?? 950).toString();
              _pharm6MonthCtrl.text = (row['six_months_price'] ?? 1800).toString();
              _pharm12MonthCtrl.text = (row['twelve_months_price'] ?? 3200).toString();
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSubscriptionPricing() async {
    setState(() => _isSavingPrices = true);
    try {
      // 1. تحديث أسعار باقة الأطباء
      await _client.from('subscription_pricing_config').upsert({
        'id': 'doctor_pricing',
        'title': 'باقة اشتراك العيادات والأطباء 🩺',
        'role': 'DOCTOR',
        'monthly_price': double.tryParse(_doc1MonthCtrl.text.trim()) ?? 350.0,
        'three_months_price': double.tryParse(_doc3MonthCtrl.text.trim()) ?? 950.0,
        'six_months_price': double.tryParse(_doc6MonthCtrl.text.trim()) ?? 1800.0,
        'twelve_months_price': double.tryParse(_doc12MonthCtrl.text.trim()) ?? 3200.0,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 2. تحديث أسعار باقة الصيدليات
      await _client.from('subscription_pricing_config').upsert({
        'id': 'pharmacy_pricing',
        'title': 'باقة اشتراك الصيدليات الشاملة 💊',
        'role': 'PHARMACY',
        'monthly_price': double.tryParse(_pharm1MonthCtrl.text.trim()) ?? 350.0,
        'three_months_price': double.tryParse(_pharm3MonthCtrl.text.trim()) ?? 950.0,
        'six_months_price': double.tryParse(_pharm6MonthCtrl.text.trim()) ?? 1800.0,
        'twelve_months_price': double.tryParse(_pharm12MonthCtrl.text.trim()) ?? 3200.0,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 تم حفظ وتحديث أسعار الاشتراكات بنجاح وتطبيقها في المنظومة فوراً!'),
            backgroundColor: AdminColors.success,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء حفظ الأسعار: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPrices = false);
    }
  }

  Future<void> _togglePaymentMethod(String id, bool currentStatus) async {
    try {
      await _client.from('payment_methods').update({'is_active': !currentStatus}).eq('id', id);
      _loadAllSettings();
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
                _loadAllSettings();
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
                child: const Icon(Icons.tune_rounded, color: AdminColors.primaryDark, size: 24),
              ),
              const SizedBox(width: 10),
              Text('إعدادات المنظومة وتسعير الاشتراكات 🏷️', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('التحكم الكامل في أسعار الاشتراكات الشهرية والسنوية للأطباء والصيدليات ووسائل التحويل المالي المعتمدة', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),

          const SizedBox(height: 24),

          // 1. كارت تسعير باقات الاشتراكات (الأطباء والصيدليات)
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.price_change_rounded, color: AdminColors.primaryDark, size: 22),
                        const SizedBox(width: 8),
                        Text('تسعير باقات الاشتراكات (ج.م) 🏷️', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: _isSavingPrices ? null : _saveSubscriptionPricing,
                      icon: _isSavingPrices
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text('حفظ وتطبيق الأسعار الجديدة 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('يمكنك تغيير سعر الشهر الواحد أو الباقات الأخرى في أي وقت، وسيتم تطبيقها مباشرة في تطبيق الموبايل لكافة الأطباء والصيدليات.', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                const SizedBox(height: 18),

                // أ. باقة الأطباء والعيادات
                Text('🩺 باقة اشتراك العيادات والأطباء:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: AdminColors.primaryDark)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildPriceField('سعر شهر واحد (شهرياً)', _doc1MonthCtrl, '350')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPriceField('سعر 3 أشهر (ربع سنوي)', _doc3MonthCtrl, '950')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPriceField('سعر 6 أشهر (نصف سنوي)', _doc6MonthCtrl, '1800')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPriceField('سعر سنة كاملة (سنوي)', _doc12MonthCtrl, '3200')),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 14),

                // ب. باقة الصيدليات
                Text('💊 باقة اشتراك الصيدليات الشاملة:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal.shade800)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildPriceField('سعر شهر واحد (شهرياً)', _pharm1MonthCtrl, '350')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPriceField('سعر 3 أشهر (ربع سنوي)', _pharm3MonthCtrl, '950')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPriceField('سعر 6 أشهر (نصف سنوي)', _pharm6MonthCtrl, '1800')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPriceField('سعر سنة كاملة (سنوي)', _pharm12MonthCtrl, '3200')),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 2. وسائل الدفع المعتمدة
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, color: AdminColors.primaryDark, size: 22),
                        const SizedBox(width: 8),
                        Text('وسائل التحويل المالي المعتمدة 💳', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('إضافة وسيلة دفع', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _showAddPaymentMethodDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (_paymentMethods.isEmpty)
                  Center(child: Text('لا توجد وسائل دفع مضافة حالياً', style: GoogleFonts.cairo(color: AdminColors.textSecondary)))
                else
                  ..._paymentMethods.map((pm) {
                    final id = pm['id'] as String;
                    final name = pm['name'] as String? ?? '';
                    final details = pm['account_details'] as String? ?? '';
                    final instructions = pm['instructions'] as String? ?? '';
                    final isActive = pm['is_active'] as bool? ?? true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: AdminColors.accentMintLight, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.payments_rounded, color: AdminColors.primaryDark, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('الرقم / الحساب: $details', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark)),
                                if (instructions.isNotEmpty)
                                  Text(instructions, style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                              ],
                            ),
                          ),
                          Switch(
                            value: isActive,
                            activeThumbColor: AdminColors.success,
                            onChanged: (_) => _togglePaymentMethod(id, isActive),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: 'ج.م',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}
