import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

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
  final _docExtraBranchPriceCtrl = TextEditingController(text: '100');

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
    _docExtraBranchPriceCtrl.dispose();
    _pharm1MonthCtrl.dispose();
    _pharm3MonthCtrl.dispose();
    _pharm6MonthCtrl.dispose();
    _pharm12MonthCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings({bool silent = false}) async {
    if (!silent && _paymentMethods.isEmpty) {
      setState(() => _isLoading = true);
    }
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
              _docExtraBranchPriceCtrl.text = (row['extra_branch_monthly_price'] ?? 100).toString();
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
        'extra_branch_monthly_price': double.tryParse(_docExtraBranchPriceCtrl.text.trim()) ?? 100.0,
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

      AdminAuditService.log(
        actionType: 'تعديل أسعار باقات الاشتراكات',
        targetType: 'SYSTEM_SETTINGS',
        targetName: 'أسعار الاشتراكات',
        details: {
          'doctor_1m': _doc1MonthCtrl.text.trim(),
          'pharmacy_1m': _pharm1MonthCtrl.text.trim(),
        },
      );

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

  Future<void> _togglePaymentMethod(String id, bool currentStatus, String name) async {
    final nextStatus = !currentStatus;
    setState(() {
      final index = _paymentMethods.indexWhere((pm) => pm['id'].toString() == id);
      if (index != -1) {
        _paymentMethods[index]['is_active'] = nextStatus;
      }
    });

    try {
      await _client.from('payment_methods').update({'is_active': nextStatus}).eq('id', id);

      AdminAuditService.log(
        actionType: nextStatus ? 'تفعيل وسيلة دفع' : 'إيقاف وسيلة دفع',
        targetType: 'PAYMENT_METHOD',
        targetId: id,
        targetName: name,
        details: {'is_active': nextStatus},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextStatus ? '🟢 تم تفعيل وسيلة الدفع ($name)' : '⏸️ تم إيقاف وسيلة الدفع ($name) مؤقتاً'),
            backgroundColor: nextStatus ? AdminColors.success : AdminColors.warning,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _loadAllSettings(silent: true);
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
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.add_card_rounded, color: AdminColors.primaryDark, size: 24),
              const SizedBox(width: 8),
              Text('إضافة وسيلة دفع جديدة 💳', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('نماذج سريعة جاهزة للاختيار:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildPresetChip('فودافون كاش 📱', 'محفظة فودافون كاش 📱', 'يرجى تحويل المبلغ لرقم المحفظة ورفع لقطة شاشة للإشعار', nameController, instructionsController, setModalState),
                      _buildPresetChip('إنستاباي ⚡', 'حساب إنستاباي الفوري (InstaPay) ⚡', 'التحويل فوري ومجاني عبر تطبيق إنستاباي. يرجى كتابة اسمك في خانة الملاحظات', nameController, instructionsController, setModalState),
                      _buildPresetChip('تحويل بنكي 🏦', 'حساب بنكي مباشر 🏦', 'تحويل بنكي مباشر لحساب المنظومة الرسمي. يرجى إرفاق صورة إيصال التحويل', nameController, instructionsController, setModalState),
                      _buildPresetChip('أورنج كاش 🍊', 'محفظة أورنج كاش 🍊', 'تحويل إلى محفظة أورنج كاش مع إرفاق لقطة شاشة لرسالة التأكيد', nameController, instructionsController, setModalState),
                      _buildPresetChip('اتصالات كاش 🟢', 'محفظة اتصالات كاش 🟢', 'تحويل عبر محفظة اتصالات كاش مع إرفاق إيصال العملية', nameController, instructionsController, setModalState),
                      _buildPresetChip('وي باي 🟣', 'محفظة وي باي (WE Pay) 🟣', 'تحويل عبر محفظة وي باي مع إرفاق صورة إشعار التحويل', nameController, instructionsController, setModalState),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'اسم وسيلة الدفع *',
                      hintText: 'مثال: محفظة فودافون كاش الرسمية',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailsController,
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'بيانات الحساب / رقم المحفظة / عنوان إنستاباي *',
                      hintText: 'مثال: 01012345678 أو shefaa@instapay أو IBAN: EG...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instructionsController,
                    style: GoogleFonts.cairo(fontSize: 13),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'تعليمات وإرشادات التحويل للأطباء والصيدليات',
                      hintText: 'مثال: يرجى كتابة اسم العيادة في وصف التحويل ورفع لقطة شاشة واضحة',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                final details = detailsController.text.trim();
                final instructions = instructionsController.text.trim();
                if (name.isEmpty || details.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى كتابة اسم الوسيلة ورقم الحساب/المحفظة'), backgroundColor: AdminColors.warning),
                  );
                  return;
                }

                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                try {
                  final res = await _client.from('payment_methods').insert({
                    'name': name,
                    'account_details': details,
                    'instructions': instructions,
                    'is_active': true,
                  }).select().single();

                  setState(() {
                    _paymentMethods.add(Map<String, dynamic>.from(res));
                  });

                  AdminAuditService.log(
                    actionType: 'إضافة وسيلة دفع جديدة',
                    targetType: 'PAYMENT_METHOD',
                    targetName: name,
                    details: {'account_details': details, 'instructions': instructions},
                  );

                  _loadAllSettings(silent: true);
                  if (mounted) {
                    messenger.showSnackBar(const SnackBar(content: Text('🎉 تمت إضافة وسيلة الدفع بنجاح!'), backgroundColor: AdminColors.success));
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(SnackBar(content: Text('خطأ أثناء الإضافة: $e'), backgroundColor: AdminColors.emergency));
                  }
                }
              },
              child: Text('حفظ الوسيلة 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPaymentMethodDialog(Map<String, dynamic> pm) {
    final id = pm['id'].toString();
    final nameController = TextEditingController(text: pm['name'] ?? '');
    final detailsController = TextEditingController(text: pm['account_details'] ?? '');
    final instructionsController = TextEditingController(text: pm['instructions'] ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AdminColors.primaryDark, size: 26),
              const SizedBox(width: 8),
              Text('تعديل وسيلة الدفع ✏️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'اسم وسيلة الدفع *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailsController,
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'بيانات الحساب / رقم المحفظة / المعرف *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instructionsController,
                    style: GoogleFonts.cairo(fontSize: 13),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'تعليمات التحويل للأطباء والصيدليات',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final details = detailsController.text.trim();
                      final instructions = instructionsController.text.trim();
                      if (name.isEmpty || details.isEmpty) return;

                      setModalState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final oldPm = Map<String, dynamic>.from(pm);

                      // 1. Optimistic Local Update immediately
                      setState(() {
                        final idx = _paymentMethods.indexWhere((m) => m['id'].toString() == id);
                        if (idx != -1) {
                          _paymentMethods[idx] = {
                            ..._paymentMethods[idx],
                            'name': name,
                            'account_details': details,
                            'instructions': instructions,
                          };
                        }
                      });

                      Navigator.pop(ctx);

                      // 2. Persist to Supabase
                      try {
                        await _client.from('payment_methods').update({
                          'name': name,
                          'account_details': details,
                          'instructions': instructions,
                        }).eq('id', id);

                        AdminAuditService.log(
                          actionType: 'تعديل وسيلة دفع',
                          targetType: 'PAYMENT_METHOD',
                          targetId: id,
                          targetName: name,
                          details: {'account_details': details, 'instructions': instructions},
                        );

                        _loadAllSettings(silent: true);
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('✅ تم حفظ وتحديث بيانات وسيلة الدفع بنجاح!'),
                              backgroundColor: AdminColors.success,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        // Rollback on error
                        if (mounted) {
                          setState(() {
                            final idx = _paymentMethods.indexWhere((m) => m['id'].toString() == id);
                            if (idx != -1) {
                              _paymentMethods[idx] = oldPm;
                            }
                          });
                          messenger.showSnackBar(
                            SnackBar(content: Text('خطأ أثناء التعديل: $e'), backgroundColor: AdminColors.emergency),
                          );
                        }
                      }
                    },
              child: Text(
                isSaving ? 'جارٍ الحفظ...' : 'حفظ التعديلات ✅',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePaymentMethod(Map<String, dynamic> pm) {
    final id = pm['id'].toString();
    final name = pm['name'] as String? ?? 'وسيلة الدفع';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: AdminColors.emergency, size: 26),
            const SizedBox(width: 8),
            Text('تأكيد حذف وسيلة الدفع 🗑️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في حذف "$name" نهائياً؟ لن تظهر للأطباء أو الصيدليات بعد الآن في شاشة السداد.',
          style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.emergency,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final prevList = List<Map<String, dynamic>>.from(_paymentMethods);
              Navigator.pop(ctx);

              setState(() {
                _paymentMethods.removeWhere((m) => m['id'].toString() == id);
              });

              try {
                await _client.from('payment_methods').delete().eq('id', id);

                AdminAuditService.log(
                  actionType: 'حذف وسيلة دفع نهائياً',
                  targetType: 'PAYMENT_METHOD',
                  targetId: id,
                  targetName: name,
                );

                _loadAllSettings(silent: true);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('🗑️ تم حذف وسيلة الدفع ($name) بنجاح'), backgroundColor: AdminColors.emergency),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _paymentMethods = prevList);
                  messenger.showSnackBar(SnackBar(content: Text('خطأ أثناء الحذف: $e'), backgroundColor: AdminColors.emergency));
                }
              }
            },
            child: Text('تأكيد الحذف ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(
    String label,
    String presetName,
    String presetInstructions,
    TextEditingController nameCtrl,
    TextEditingController instrCtrl,
    StateSetter setModalState,
  ) {
    return ActionChip(
      avatar: const Icon(Icons.flash_on_rounded, size: 14, color: AdminColors.primaryDark),
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
      backgroundColor: AdminColors.accentMintLight.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: const BorderSide(color: AdminColors.cardBorderMint),
      onPressed: () {
        setModalState(() {
          nameCtrl.text = presetName;
          instrCtrl.text = presetInstructions;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: AdminTableSkeleton(rows: 6),
      );
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
                          ? const SizedBox(width: 16, height: 16, child: AdminShimmerBox.circular(size: 16))
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildPriceField(
                        '🏥 سعر كل عيادة/فرع إضافي شهرياً (ج.م)',
                        _docExtraBranchPriceCtrl,
                        '100',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          '💡 ملحوظة: الفرع والعيادة الأولى مشمولة مجاناً مع الباقة الأساسية، ويتم تطبيق هذا الرسم الرمزي عن كل عيادة إضافية يسجلها الطبيب.',
                          style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
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
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.credit_card_off_rounded, size: 48, color: AdminColors.textSecondary),
                          const SizedBox(height: 8),
                          Text('لا توجد وسائل دفع مضافة حالياً', style: GoogleFonts.cairo(color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('اضغط على "إضافة وسيلة دفع" بالأعلى لإضافة حسابات فودافون كاش أو إنستاباي أو حسابات بنكية', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                        ],
                      ),
                    ),
                  )
                else
                  ..._paymentMethods.map((pm) {
                    final id = pm['id'] as String;
                    final name = pm['name'] as String? ?? '';
                    final details = pm['account_details'] as String? ?? '';
                    final instructions = pm['instructions'] as String? ?? '';
                    final isActive = pm['is_active'] as bool? ?? true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isActive ? AdminColors.cardBorderMint : Colors.grey.shade300,
                          width: isActive ? 1.2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isActive ? 0.03 : 0.01),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (isActive ? AdminColors.primaryDark : Colors.grey).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.payments_rounded,
                              color: isActive ? AdminColors.primaryDark : Colors.grey.shade600,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                        color: isActive ? AdminColors.textPrimary : Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (isActive ? AdminColors.success : Colors.grey).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isActive ? '🟢 نشطة ومتاحة للسداد' : '⚪ معطلة ومخفية',
                                        style: GoogleFonts.cairo(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isActive ? AdminColors.success : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    SelectableText(
                                      details,
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13.5,
                                        color: isActive ? AdminColors.primaryDark : Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                if (instructions.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    instructions,
                                    style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // زر التعديل
                          IconButton(
                            tooltip: 'تعديل بيانات وسيلة الدفع',
                            icon: const Icon(Icons.edit_note_rounded, color: AdminColors.primaryDark, size: 22),
                            onPressed: () => _showEditPaymentMethodDialog(pm),
                          ),

                          // زر الحذف
                          IconButton(
                            tooltip: 'حذف وسيلة الدفع نهائياً',
                            icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.emergency, size: 20),
                            onPressed: () => _confirmDeletePaymentMethod(pm),
                          ),

                          const SizedBox(width: 4),

                          // زر التبديل والتشغيل
                          Column(
                            children: [
                              Switch(
                                value: isActive,
                                activeTrackColor: AdminColors.success,
                                onChanged: (_) => _togglePaymentMethod(id, isActive, name),
                              ),
                              Text(
                                isActive ? 'مفعلة' : 'معطلة',
                                style: GoogleFonts.cairo(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? AdminColors.success : Colors.grey.shade600,
                                ),
                              ),
                            ],
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
