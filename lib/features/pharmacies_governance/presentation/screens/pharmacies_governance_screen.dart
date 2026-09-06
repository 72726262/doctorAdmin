import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

class PharmaciesGovernanceScreen extends StatefulWidget {
  const PharmaciesGovernanceScreen({super.key});

  @override
  State<PharmaciesGovernanceScreen> createState() => _PharmaciesGovernanceScreenState();
}

class _PharmaciesGovernanceScreenState extends State<PharmaciesGovernanceScreen> {
  final _client = AdminSupabaseConfig.client;
  final _realtimeManager = AdminRealtimeManager();

  static List<Map<String, dynamic>>? _cachedPharmacies;

  bool _isLoading = true;
  List<Map<String, dynamic>> _pharmacies = [];
  String _searchQuery = '';
  String _governorateFilter = 'الكل';
  int _selectedStatusTabIndex = 0; // 0: الكل, 1: معتمد, 2: مجمد

  @override
  void initState() {
    super.initState();
    if (_cachedPharmacies != null && _cachedPharmacies!.isNotEmpty) {
      _pharmacies = _cachedPharmacies!;
      _isLoading = false;
    }
    _fetchPharmacies(silent: _cachedPharmacies != null);
    _realtimeManager.addPartnerListener(_onRealtimePartner);
  }

  void _onRealtimePartner() {
    if (mounted) _fetchPharmacies(silent: true);
  }

  @override
  void dispose() {
    _realtimeManager.removePartnerListener(_onRealtimePartner);
    super.dispose();
  }

  Future<void> _fetchPharmacies({bool silent = false}) async {
    if (!silent && _pharmacies.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await _client.from('pharmacies').select('''
        id,
        name,
        governorate,
        address_text,
        rating_avg,
        rating_count,
        subscription_status,
        subscription_expires_at,
        grace_period_ends_at,
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
        final list = List<Map<String, dynamic>>.from(res as List);
        setState(() {
          _pharmacies = list;
          _cachedPharmacies = list;
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

      await _fetchPharmacies(silent: true);

      AdminAuditService.log(
        actionType: !currentStatus ? 'تفعيل حساب صيدلية' : 'تجميد حساب صيدلية',
        targetType: 'PHARMACY',
        targetId: pharmacyId,
        targetName: 'صيدلية $pharmacyId',
        details: {'is_approved': !currentStatus},
      );

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

  Map<String, dynamic> _getSubscriptionInfo(Map<String, dynamic> pha) {
    final status = (pha['subscription_status'] as String? ?? 'INACTIVE').toUpperCase();
    final expiresAtStr = pha['subscription_expires_at'] as String?;

    if (expiresAtStr == null) {
      return {
        'status': status,
        'label': 'غير محدد ⚪',
        'badgeColor': Colors.grey.shade100,
        'textColor': Colors.grey.shade700,
        'borderColor': Colors.grey.shade300,
        'expiryText': 'لا يوجد تاريخ مسجل',
        'fullExpiryText': 'غير محدد',
        'days': 0,
        'isExpired': true,
        'isExpiringSoon': false,
      };
    }

    try {
      final expiry = DateTime.parse(expiresAtStr).toLocal();
      final now = DateTime.now();
      final diff = expiry.difference(now);
      final diffDays = diff.inDays;
      final formattedDate = intl.DateFormat('yyyy/MM/dd').format(expiry);
      final fullDateText = intl.DateFormat('EEEE d MMMM yyyy - hh:mm a', 'ar').format(expiry);

      if (status == 'SUSPENDED' || status == 'FROZEN') {
        return {
          'status': status,
          'label': 'مجمد / موقوف ⏸️',
          'badgeColor': Colors.red.shade50,
          'textColor': AdminColors.emergency,
          'borderColor': Colors.red.shade200,
          'expiryText': formattedDate,
          'fullExpiryText': fullDateText,
          'days': diffDays,
          'isExpired': true,
          'isExpiringSoon': false,
        };
      }

      if (diff.isNegative) {
        final passedDays = diffDays.abs();
        return {
          'status': 'EXPIRED',
          'label': 'منتهي منذ $passedDays يوم 🔴',
          'badgeColor': Colors.red.shade50,
          'textColor': AdminColors.emergency,
          'borderColor': Colors.red.shade200,
          'expiryText': formattedDate,
          'fullExpiryText': fullDateText,
          'days': diffDays,
          'isExpired': true,
          'isExpiringSoon': false,
        };
      } else if (diffDays <= 5) {
        return {
          'status': 'EXPIRING_SOON',
          'label': 'ينتهي خلال $diffDays يوم ⚠️',
          'badgeColor': Colors.amber.shade50,
          'textColor': Colors.amber.shade900,
          'borderColor': Colors.amber.shade300,
          'expiryText': formattedDate,
          'fullExpiryText': fullDateText,
          'days': diffDays,
          'isExpired': false,
          'isExpiringSoon': true,
        };
      } else {
        return {
          'status': 'ACTIVE',
          'label': 'متبقي $diffDays يوم 🟢',
          'badgeColor': AdminColors.accentMintLight.withValues(alpha: 0.6),
          'textColor': AdminColors.primaryDark,
          'borderColor': AdminColors.cardBorderMint,
          'expiryText': formattedDate,
          'fullExpiryText': fullDateText,
          'days': diffDays,
          'isExpired': false,
          'isExpiringSoon': false,
        };
      }
    } catch (_) {
      return {
        'status': status,
        'label': status,
        'badgeColor': Colors.grey.shade100,
        'textColor': Colors.grey.shade700,
        'borderColor': Colors.grey.shade300,
        'expiryText': expiresAtStr,
        'fullExpiryText': expiresAtStr,
        'days': 0,
        'isExpired': false,
        'isExpiringSoon': false,
      };
    }
  }

  /// تمديد اشتراك الصيدلية مع توثيق العملية فوراً
  Future<void> _extendSubscription(String pharmacyId, int days, {DateTime? exactExpiryDate, String? notes}) async {
    try {
      final currentPha = _pharmacies.firstWhere(
        (p) => p['id'] == pharmacyId,
        orElse: () => {'subscription_expires_at': null},
      );
      final currentExpiryStr = currentPha['subscription_expires_at'] as String?;
      DateTime startDate = DateTime.now();

      if (currentExpiryStr != null) {
        final parsed = DateTime.tryParse(currentExpiryStr)?.toLocal();
        if (parsed != null && parsed.isAfter(DateTime.now())) {
          startDate = parsed;
        }
      }
      final newExpiry = exactExpiryDate ?? startDate.add(Duration(days: days));

      final monthsCount = (days / 30).round() == 0 ? 1 : (days / 30).round();
      final adminNote = notes?.trim().isNotEmpty == true
          ? notes!.trim()
          : 'تمديد إداري استثنائي مباشر لصيدلية ($days يوم)';

      await _client.from('subscription_requests').insert({
        'user_id': pharmacyId,
        'role': 'PHARMACY',
        'plan_name': 'باقة الصيدليات الاحترافية',
        'amount': 0,
        'amount_paid': 0,
        'months': monthsCount,
        'payment_method': 'منحة / تمديد إداري 🛡️',
        'status': 'APPROVED',
        'start_date': startDate.toIso8601String(),
        'end_date': newExpiry.toIso8601String(),
        'reviewed_at': DateTime.now().toIso8601String(),
        'notes': adminNote,
      });

      await _client.from('pharmacies').update({
        'subscription_status': 'ACTIVE',
        'subscription_expires_at': newExpiry.toIso8601String(),
        'grace_period_ends_at': newExpiry.add(const Duration(days: 3)).toIso8601String(),
      }).eq('id', pharmacyId);

      await _client.from('profiles').update({'is_approved': true}).eq('id', pharmacyId);

      AdminAuditService.log(
        actionType: 'تمديد اشتراك صيدلية',
        targetType: 'PHARMACY',
        targetId: pharmacyId,
        targetName: 'صيدلية $pharmacyId',
        details: {
          'days': days,
          'start_date': startDate.toIso8601String(),
          'end_date': newExpiry.toIso8601String(),
          'notes': adminNote,
        },
      );

      await _fetchPharmacies(silent: true);

      if (mounted) {
        final formattedNewExpiry = intl.DateFormat('yyyy/MM/dd').format(newExpiry);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 تم تمديد اشتراك الصيدلية لـ $days يوماً بنجاح حتى ($formattedNewExpiry)!'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء التمديد: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  /// نافذة منبثقة لتعديل بيانات وحساب الصيدلية بالكامل (استبدال الصيدلي / نقل ملكية الصيدلية)
  void _showEditPharmacyAccountDialog(Map<String, dynamic> pha) {
    final profile = pha['profiles'] as Map<String, dynamic>? ?? {};
    final pharmacyId = pha['id'] as String;
    final initialName = (pha['name'] as String?) ?? (profile['full_name'] as String?) ?? '';
    final initialPhone = (profile['phone'] as String?) ?? '';
    final initialGov = (pha['governorate'] as String?) ?? (profile['governorate'] as String?) ?? 'القاهرة';
    final initialAddress = (pha['address_text'] as String?) ?? '';
    bool hasDelivery = pha['has_delivery'] == true;

    final nameController = TextEditingController(text: initialName);
    final phoneController = TextEditingController(text: initialPhone);
    final addressController = TextEditingController(text: initialAddress);
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    const governorates = [
      'القاهرة',
      'الجيزة',
      'الإسكندرية',
      'الدقهلية',
      'الغربية',
      'الشرقية',
      'المنوفية',
      'البحيرة',
      'كفر الشيخ',
      'دمياط',
      'بورسعيد',
      'الإسماعيلية',
      'السويس',
      'القليوبية',
      'بني سويف',
      'الفيوم',
      'المنيا',
      'أسيوط',
      'سوهاج',
      'قنا',
      'الأقصر',
      'أسوان',
      'البحر الأحمر',
      'الوادي الجديد',
      'مطروح',
      'شمال سيناء',
      'جنوب سيناء',
    ];

    String selectedGov = governorates.contains(initialGov) ? initialGov : governorates.first;
    bool obscurePassword = true;
    bool isSaving = false;
    bool isLoadingSecurity = true;
    bool hasRequestedSecurity = false;

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            // Lazy load email on open
            if (!hasRequestedSecurity) {
              hasRequestedSecurity = true;
              _client.rpc('admin_get_account_security_info', params: {'p_user_id': pharmacyId}).then((res) {
                if (dialogCtx.mounted) {
                  setModalState(() {
                    isLoadingSecurity = false;
                    if (res != null && res is Map && res['email'] != null) {
                      emailController.text = res['email'].toString();
                    }
                  });
                }
              }).catchError((_) {
                if (dialogCtx.mounted) {
                  setModalState(() {
                    isLoadingSecurity = false;
                  });
                }
              });
            }

            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(dialogCtx);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                width: 680,
                constraints: const BoxConstraints(maxHeight: 780),
                decoration: BoxDecoration(
                  color: AdminColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: const BoxDecoration(
                        color: AdminColors.primaryDark,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.local_pharmacy_rounded, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تعديل بيانات وحساب الصيدلية (استبدال / نقل ملكية) 💊',
                                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                                  ),
                                  Text(
                                    'تحديث اسم الصيدلية، الهاتف، العنوان، أو تعيين مسؤول جديد',
                                    style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: isSaving ? null : () => navigator.pop(),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Notice banner
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '💡 ملحوظة نقل ملكية وإدارة الصيدلية: في حال تولى صيدلي أو مدير جديد إدارة الصيدلية، يمكنك تعديل اسم الصيدلية، رقم الهاتف، العنوان وتعيين كلمة مرور جديدة فوراً مع الحفاظ الكامل على كتالوج الأدوية وسجل الطلبات.',
                                        style: GoogleFonts.cairo(
                                          fontSize: 11.5,
                                          height: 1.5,
                                          color: const Color(0xFF1E40AF),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Section: Pharmacy Info
                              Text(
                                'البيانات الأساسية للصيدلية',
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                              ),
                              const SizedBox(height: 10),

                              // Name & Phone Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: nameController,
                                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'اسم الصيدلية *',
                                        labelStyle: GoogleFonts.cairo(fontSize: 12),
                                        prefixIcon: const Icon(Icons.local_pharmacy_rounded, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم الصيدلية مطلوب' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: phoneController,
                                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                      keyboardType: TextInputType.phone,
                                      decoration: InputDecoration(
                                        labelText: 'رقم الهاتف *',
                                        labelStyle: GoogleFonts.cairo(fontSize: 12),
                                        prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Governorate & Delivery Row
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: selectedGov,
                                      style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textPrimary, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'المحافظة',
                                        labelStyle: GoogleFonts.cairo(fontSize: 12),
                                        prefixIcon: const Icon(Icons.location_on_rounded, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                      items: governorates.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                      onChanged: (val) {
                                        if (val != null) setModalState(() => selectedGov = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade400),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'خدمة توصيل 🛵',
                                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          Switch(
                                            value: hasDelivery,
                                            activeThumbColor: AdminColors.primaryDark,
                                            onChanged: (val) => setModalState(() => hasDelivery = val),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Detailed Address
                              TextFormField(
                                controller: addressController,
                                style: GoogleFonts.cairo(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'العنوان التفصيلي للصيدلية',
                                  labelStyle: GoogleFonts.cairo(fontSize: 12),
                                  prefixIcon: const Icon(Icons.map_rounded, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Section: Security & Login Credentials
                              Row(
                                children: [
                                  const Icon(Icons.lock_person_rounded, color: AdminColors.primaryDark, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'بيانات تسجيل الدخول والأمان (حساب الصيدلية)',
                                    style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                                  ),
                                  if (isLoadingSecurity) ...[
                                    const SizedBox(width: 8),
                                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Email & Password Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: GoogleFonts.cairo(fontSize: 12.5),
                                      decoration: InputDecoration(
                                        labelText: 'البريد الإلكتروني لتسجيل الدخول',
                                        labelStyle: GoogleFonts.cairo(fontSize: 12),
                                        prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        helperText: 'يستخدمه الصيدلي لتسجيل الدخول بالتطبيق',
                                        helperStyle: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textSecondary),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: passwordController,
                                      obscureText: obscurePassword,
                                      style: GoogleFonts.cairo(fontSize: 12.5),
                                      decoration: InputDecoration(
                                        labelText: 'كلمة مرور جديدة (اختياري)',
                                        labelStyle: GoogleFonts.cairo(fontSize: 12),
                                        prefixIcon: const Icon(Icons.password_rounded, size: 20),
                                        suffixIcon: IconButton(
                                          icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                                          onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                                        ),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        helperText: 'اتركه فارغاً للإبقاء على كلمة المرور الحالية',
                                        helperStyle: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textSecondary),
                                      ),
                                      validator: (v) {
                                        if (v != null && v.trim().isNotEmpty && v.trim().length < 6) {
                                          return 'كلمة المرور يجب ألا تقل عن 6 أحرف';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Footer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: AdminColors.backgroundCanvas,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSaving ? null : () => navigator.pop(),
                            child: Text('إلغاء', style: GoogleFonts.cairo(color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminColors.primaryDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: isSaving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check_circle_rounded, size: 18),
                            label: Text(
                              isSaving ? 'جارٍ الحفظ والتحديث...' : 'حفظ التحديثات والبيانات',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) return;

                                    setModalState(() => isSaving = true);
                                    try {
                                      final finalName = nameController.text.trim();
                                      final finalPhone = phoneController.text.trim();
                                      final finalGov = selectedGov;
                                      final finalAddress = addressController.text.trim();
                                      final finalEmail = emailController.text.trim().isEmpty ? null : emailController.text.trim();
                                      final finalPass = passwordController.text.trim().isEmpty ? null : passwordController.text.trim();

                                      final rpcRes = await _client.rpc('admin_update_pharmacy_account', params: {
                                        'p_pharmacy_id': pharmacyId,
                                        'p_name': finalName,
                                        'p_phone': finalPhone,
                                        'p_governorate': finalGov,
                                        'p_address_text': finalAddress,
                                        'p_has_delivery': hasDelivery,
                                        'p_email': finalEmail,
                                        'p_new_password': finalPass,
                                      });

                                      if (rpcRes != null && rpcRes is Map && rpcRes['success'] == false) {
                                        throw rpcRes['message'] ?? 'فشل تحديث البيانات';
                                      }

                                      await AdminAuditService.log(
                                        actionType: 'UPDATE_PHARMACY_ACCOUNT',
                                        targetType: 'PHARMACY',
                                        targetName: finalName,
                                        targetId: pharmacyId,
                                        details: {
                                          'pharmacy_id': pharmacyId,
                                          'name': finalName,
                                          'phone': finalPhone,
                                          'governorate': finalGov,
                                          'has_delivery': hasDelivery,
                                          'password_changed': finalPass != null,
                                        },
                                      );

                                      navigator.pop();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('🟢 تم تحديث بيانات وحساب صيدلية $finalName بنجاح', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                                          backgroundColor: AdminColors.success,
                                        ),
                                      );
                                      _fetchPharmacies(silent: true);
                                    } catch (e) {
                                      setModalState(() => isSaving = false);
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('خطأ: $e', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)), backgroundColor: AdminColors.emergency),
                                      );
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showExtendSubscriptionDialog(String phaId, String pharmacyName) {
    final currentPha = _pharmacies.firstWhere(
      (p) => p['id'] == phaId,
      orElse: () => {'subscription_expires_at': null},
    );
    final currentExpiryStr = currentPha['subscription_expires_at'] as String?;
    DateTime baseStartDate = DateTime.now();
    if (currentExpiryStr != null) {
      final parsed = DateTime.tryParse(currentExpiryStr)?.toLocal();
      if (parsed != null && parsed.isAfter(DateTime.now())) {
        baseStartDate = parsed;
      }
    }

    int selectedDays = 30;
    DateTime calculatedExpiryDate = baseStartDate.add(Duration(days: selectedDays));
    final customDaysCtrl = TextEditingController(text: '30');
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final gracePeriodEnd = calculatedExpiryDate.add(const Duration(days: 3));

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.primaryDark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_card_rounded, color: AdminColors.primaryDark, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تمديد وتخصيص اشتراك: $pharmacyName 💳',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // كارت المعاينة الزمني الحي
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F4C3A), Color(0xFF1E6B55)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'تاريخ انتهاء اشتراك الصيدلية الجديد:',
                                style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11.5),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AdminColors.accentMint,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+$selectedDays يوم',
                                  style: GoogleFonts.cairo(
                                    color: AdminColors.primaryDark,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            intl.DateFormat('EEEE d MMMM yyyy', 'ar').format(calculatedExpiryDate),
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '🛡️ فترة سماح إضافية (+3 أيام) حتى: ${intl.DateFormat('yyyy/MM/dd').format(gracePeriodEnd)}',
                            style: GoogleFonts.cairo(color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    Text('خيارات التمديد السريع:', style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildDurationChoiceChip('14 يوم', 14, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            customDaysCtrl.text = d.toString();
                            calculatedExpiryDate = baseStartDate.add(Duration(days: d));
                          });
                        }),
                        _buildDurationChoiceChip('30 يوم ⭐', 30, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            customDaysCtrl.text = d.toString();
                            calculatedExpiryDate = baseStartDate.add(Duration(days: d));
                          });
                        }),
                        _buildDurationChoiceChip('60 يوم', 60, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            customDaysCtrl.text = d.toString();
                            calculatedExpiryDate = baseStartDate.add(Duration(days: d));
                          });
                        }),
                        _buildDurationChoiceChip('90 يوم (3 أشهر)', 90, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            customDaysCtrl.text = d.toString();
                            calculatedExpiryDate = baseStartDate.add(Duration(days: d));
                          });
                        }),
                        _buildDurationChoiceChip('180 يوم (6 أشهر)', 180, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            customDaysCtrl.text = d.toString();
                            calculatedExpiryDate = baseStartDate.add(Duration(days: d));
                          });
                        }),
                        _buildDurationChoiceChip('365 يوم (سنة) 👑', 365, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            customDaysCtrl.text = d.toString();
                            calculatedExpiryDate = baseStartDate.add(Duration(days: d));
                          });
                        }),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Text('أو حدد عدد الأيام أو تاريخ الانتهاء بحرية:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customDaysCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              final parsed = int.tryParse(val.trim());
                              if (parsed != null && parsed > 0) {
                                setDialogState(() {
                                  selectedDays = parsed;
                                  calculatedExpiryDate = baseStartDate.add(Duration(days: parsed));
                                });
                              }
                            },
                            decoration: InputDecoration(
                              suffixText: 'يوم',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month_rounded, size: 16, color: AdminColors.primaryDark),
                          label: Text('من التقويم', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: calculatedExpiryDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                            );
                            if (picked != null) {
                              final diff = picked.difference(baseStartDate).inDays + 1;
                              setDialogState(() {
                                calculatedExpiryDate = picked;
                                selectedDays = diff > 0 ? diff : 1;
                                customDaysCtrl.text = selectedDays.toString();
                              });
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Text('ملاحظات التمديد الإداري (اختياري):', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        hintText: 'مثال: تسوية يدوية / منحة ترويجية افتتاحية...',
                        hintStyle: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _extendSubscription(
                    phaId,
                    selectedDays,
                    exactExpiryDate: calculatedExpiryDate,
                    notes: notesCtrl.text.trim(),
                  );
                },
                child: Text('تأكيد التمديد ($selectedDays يوم) ✅', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDurationChoiceChip(String label, int days, int currentDays, Function(int) onSelect) {
    final isSelected = currentDays == days;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AdminColors.primaryDark,
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (_) => onSelect(days),
    );
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
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.primaryDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.manage_accounts_rounded, size: 16),
                        label: Text('تعديل الحساب والصيدلية ⚙️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditPharmacyAccountDialog(pha);
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
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
    int activeCount = 0;
    int frozenCount = 0;
    int deliveryCount = 0;

    for (final p in _pharmacies) {
      final profile = p['profiles'] as Map<String, dynamic>? ?? {};
      final isApproved = (profile['is_approved'] == true) &&
          (p['subscription_status'] != 'SUSPENDED' && p['subscription_status'] != 'FROZEN');
      if (isApproved) {
        activeCount++;
      } else {
        frozenCount++;
      }
      if (p['has_delivery'] == true) {
        deliveryCount++;
      }
    }

    final filtered = _pharmacies.where((p) {
      final profile = p['profiles'] as Map<String, dynamic>? ?? {};
      final name = p['name']?.toString() ?? profile['full_name']?.toString() ?? '';
      final gov = p['governorate']?.toString() ?? profile['governorate']?.toString() ?? '';
      final isApproved = (profile['is_approved'] == true) &&
          (p['subscription_status'] != 'SUSPENDED' && p['subscription_status'] != 'FROZEN');

      final matchGov = _governorateFilter == 'الكل' || gov == _governorateFilter;
      bool matchStatus = true;
      if (_selectedStatusTabIndex == 1) {
        matchStatus = isApproved;
      } else if (_selectedStatusTabIndex == 2) {
        matchStatus = !isApproved;
      }

      final matchSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery) ||
          gov.contains(_searchQuery);

      return matchGov && matchStatus && matchSearch;
    }).toList();

    return SingleChildScrollView(
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث القائمة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchPharmacies,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // كروت المؤشرات العلوية (KPI Metric Summary Cards)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'إجمالي الصيدليات',
                  count: _pharmacies.length,
                  subtitle: 'موزعة في مختلف المحافظات',
                  icon: Icons.local_pharmacy_rounded,
                  color: AdminColors.primaryDark,
                  bgColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'معتمدة ونشطة 🟢',
                  count: activeCount,
                  subtitle: 'جاهزة لصرف الروشتات للمرضى',
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'خدمة التوصيل 🛵',
                  count: deliveryCount,
                  subtitle: 'توفر توصيل الدواء للمنازل',
                  icon: Icons.delivery_dining_rounded,
                  color: const Color(0xFF0EA5E9),
                  bgColor: const Color(0xFFF0F9FF),
                  borderColor: const Color(0xFFBAE6FD),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'مجمدة أو موقوفة ⏸️',
                  count: frozenCount,
                  subtitle: 'حسابات غير مفعلة حالياً',
                  icon: Icons.pause_circle_filled_rounded,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFECACA),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Search & Filters Bar
          Row(
            children: [
              // Search
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: TextField(
                    style: GoogleFonts.cairo(fontSize: 13),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: '🔍 بحث باسم الصيدلية أو المحافظة...',
                      hintStyle: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.textSecondary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Governorate Filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _governorateFilter,
                    style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    items: ['الكل', 'القاهرة', 'الجيزة', 'الإسكندرية', 'الدقهلية', 'الغربية', 'الشرقية', 'المنوفية', 'البحيرة'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (val) => setState(() => _governorateFilter = val ?? 'الكل'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // تابات الحالة العصرية (Segmented Modern Tab Bar)
          AdminModernTabBar(
            tabs: [
              AdminTabItem(label: 'الكل', icon: Icons.store_rounded, count: _pharmacies.length),
              AdminTabItem(label: 'معتمدة ونشطة 🟢', icon: Icons.check_circle_rounded, count: activeCount, badgeColor: const Color(0xFF10B981)),
              AdminTabItem(label: 'مجمدة أو موقوفة ⏸️', icon: Icons.pause_circle_filled_rounded, count: frozenCount, badgeColor: const Color(0xFFEF4444)),
            ],
            selectedIndex: _selectedStatusTabIndex,
            onTabSelected: (idx) => setState(() => _selectedStatusTabIndex = idx),
          ),

          const SizedBox(height: 16),

          // List
          if (_isLoading && _pharmacies.isEmpty)
            const AdminTableSkeleton(rows: 8)
          else if (filtered.isEmpty)
            AdminEmptyStateCard(
              title: _searchQuery.isNotEmpty
                  ? 'لا توجد صيدليات مطابقة لبحث "$_searchQuery"'
                  : 'لا توجد صيدليات في هذا القسم حالياً',
              description: _searchQuery.isNotEmpty
                  ? 'تأكد من كتابة الاسم أو المحافظة بشكل صحيح، أو أعد ضبط خيارات البحث.'
                  : 'جميع بيانات الصيدليات ومخزون الأدوية محدثة وجاهزة للرقابة.',
              icon: Icons.local_pharmacy_outlined,
              onRefresh: _fetchPharmacies,
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
                                          const SizedBox(width: 6),
                                          Builder(
                                            builder: (context) {
                                              final subInfo = _getSubscriptionInfo(pha);
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: subInfo['badgeColor'],
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: subInfo['borderColor']),
                                                ),
                                                child: Text(
                                                  subInfo['label'],
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: subInfo['textColor'],
                                                  ),
                                                ),
                                              );
                                            },
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
                                      icon: const Icon(Icons.manage_accounts_rounded, color: AdminColors.primaryDark, size: 20),
                                      tooltip: 'تعديل بيانات وحساب الصيدلية (نقل ملكية / استبدال) ⚙️',
                                      onPressed: () => _showEditPharmacyAccountDialog(pha),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.add_card_rounded, color: AdminColors.primaryDark, size: 20),
                                      tooltip: 'تمديد وتخصيص اشتراك الصيدلية 💳',
                                      onPressed: () => _showExtendSubscriptionDialog(pha['id'], pha['name'] ?? profile['full_name'] ?? 'الصيدلية'),
                                    ),
                                    const SizedBox(width: 4),
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
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      '$count',
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AdminColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        count > 0 ? 'نشط' : '0',
                        style: GoogleFonts.cairo(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
