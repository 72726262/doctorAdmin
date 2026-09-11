import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

class SubscriptionRequestsScreen extends StatefulWidget {
  const SubscriptionRequestsScreen({super.key});

  @override
  State<SubscriptionRequestsScreen> createState() => _SubscriptionRequestsScreenState();
}

class _SubscriptionRequestsScreenState extends State<SubscriptionRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _client = AdminSupabaseConfig.client;
  final _realtimeManager = AdminRealtimeManager();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  static final Map<String, List<Map<String, dynamic>>> _cache = {};

  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRoleFilter = 'الكل';
  Map<String, int> _counts = {'PENDING': 0, 'APPROVED': 0, 'REJECTED': 0};
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        _onFilterChanged();
      }
    });

    _realtimeManager.addSubscriptionListener(_onRealtimeSubscription);
    _onFilterChanged();
  }

  void _onFilterChanged() {
    if (_cache.containsKey(_currentStatusTab) && _cache[_currentStatusTab]!.isNotEmpty) {
      setState(() {
        _requests = _cache[_currentStatusTab]!;
        _isLoading = false;
      });
      _fetchRequests(silent: true);
    } else {
      _fetchRequests(silent: false);
    }
  }

  void _onRealtimeSubscription() {
    if (mounted) {
      _fetchRequests(silent: true);
    }
  }

  @override
  void dispose() {
    _realtimeManager.removeSubscriptionListener(_onRealtimeSubscription);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _currentStatusTab {
    switch (_tabController.index) {
      case 0:
        return 'PENDING';
      case 1:
        return 'APPROVED';
      case 2:
        return 'REJECTED';
      default:
        return 'PENDING';
    }
  }

  Future<void> _fetchRequests({bool silent = false}) async {
    if (!silent && _requests.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await _client.from('subscription_requests').select('''
        id,
        user_id,
        amount,
        amount_paid,
        months,
        target_month,
        sender_number,
        transaction_reference,
        payment_method,
        receipt_image_url,
        status,
        start_date,
        end_date,
        extra_branches_count,
        extra_branches_amount,
        selected_branch_ids,
        notes,
        rejection_reason,
        created_at,
        reviewed_at,
        role,
        plan_name,
        profiles (
          full_name,
          phone,
          governorate,
          role
        )
      ''').eq('status', _currentStatusTab).order('created_at', ascending: false);

      if (mounted) {
        final list = List<Map<String, dynamic>>.from(res as List);
        setState(() {
          _requests = list;
          _cache[_currentStatusTab] = list;
          _isLoading = false;
        });

        // Also fetch live counts for all status tabs
        _fetchStatusCounts();
      }
    } catch (e) {
      debugPrint('Error fetching subscription requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchStatusCounts() async {
    try {
      final res = await _client.from('subscription_requests').select('status');
      final list = List<Map<String, dynamic>>.from(res as List);
      final newCounts = {'PENDING': 0, 'APPROVED': 0, 'REJECTED': 0};
      for (final r in list) {
        final s = (r['status'] as String? ?? '').toUpperCase();
        if (newCounts.containsKey(s)) {
          newCounts[s] = (newCounts[s] ?? 0) + 1;
        }
      }
      if (mounted) {
        setState(() => _counts = newCounts);
      }
    } catch (_) {}
  }

  /// اعتماد فوري وتمديد الاشتراك بعدد الأيام المحددة أو التاريخ المحدد
  Future<void> _approveSubscriptionWithDays({
    required String reqId,
    required String userId,
    required int days,
    DateTime? exactExpiryDate,
    String? adminNotes,
    bool mainBranchOnly = false,
    List<String>? activeBranchIds,
  }) async {
    // 1. تحديث لحظي في الذاكرة فوراً لسرعة وسلاسة الواجهة
    final previousList = List<Map<String, dynamic>>.from(_requests);
    setState(() {
      _requests.removeWhere((r) => r['id'] == reqId);
    });

    final targetDateStr = exactExpiryDate != null
        ? intl.DateFormat('yyyy/MM/dd').format(exactExpiryDate)
        : intl.DateFormat('yyyy/MM/dd').format(DateTime.now().add(Duration(days: days)));

    final successMsg = mainBranchOnly
        ? '⚠️ تم اعتماد الباقة للفرع الأساسي فقط وتعطيل الفروع الإضافية حتى ($targetDateStr)'
        : '🎉 تم اعتماد الإيصال وتمديد الاشتراك حتى ($targetDateStr) بنجاح!';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMsg),
        backgroundColor: mainBranchOnly ? AdminColors.warning : AdminColors.success,
        duration: const Duration(seconds: 4),
      ),
    );

    // 2. المزامنة مع السيرفر عبر الـ RPC
    try {
      final res = await _client.rpc('admin_approve_subscription_with_custom_days', params: {
        'p_request_id': reqId,
        'p_days': days,
        'p_admin_notes': adminNotes,
        'p_exact_expiry_date': exactExpiryDate?.toIso8601String(),
        'p_active_branch_ids': activeBranchIds,
        'p_main_branch_only': mainBranchOnly,
      });
      debugPrint('Approval result: $res');

      AdminAuditService.log(
        actionType: 'اعتماد سداد وتمديد اشتراك',
        targetType: 'SUBSCRIPTION',
        targetId: reqId,
        targetName: 'اشتراك $userId',
        details: {
          'days': days,
          'expiry': targetDateStr,
          'notes': adminNotes,
        },
      );
    } catch (e) {
      debugPrint('Fallback manual update: $e');
      try {
        final req = previousList.firstWhere((r) => r['id'] == reqId, orElse: () => <String, dynamic>{});
        await _client.rpc('approve_subscription_request', params: {
          'p_request_id': reqId,
          'p_partner_id': userId,
          'p_role': req['role'] ?? 'DOCTOR',
          'p_months': (days / 30).round() == 0 ? 1 : (days / 30).round(),
        });
      } catch (err) {
        if (mounted) {
          setState(() => _requests = previousList);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر اعتماد الطلب: $err'), backgroundColor: AdminColors.emergency),
          );
        }
      }
    }
  }

  /// حوار اعتماد وتحديد تاريخ ومدة الانتهاء بدقة
  void _showApproveDurationDialog(Map<String, dynamic> req) async {
    final reqId = req['id'] as String;
    final userId = req['user_id'] as String;
    final profile = req['profiles'] as Map<String, dynamic>? ?? {};
    final fullName = profile['full_name'] ?? 'الطبيب / الصيدلي';
    final phone = profile['phone'] ?? '';
    final gov = profile['governorate'] ?? 'مصر';
    final role = (req['role'] ?? profile['role'] ?? 'DOCTOR').toString().toUpperCase();
    final isDoctor = role == 'DOCTOR';
    final amount = req['amount'] ?? req['amount_paid'] ?? 350;
    final planName = (req['plan_name'] as String? ?? '').trim();
    final paymentMethod = req['payment_method'] ?? 'تحويل إلكتروني';
    final senderNumber = req['sender_number'] as String?;

    // جلب كافة فروع الطبيب في حال كان المشترك طبيباً
    List<Map<String, dynamic>> doctorBranches = [];
    if (isDoctor) {
      try {
        final res = await _client
            .from('branches')
            .select('id, name, governorate, address_text, is_main, is_active')
            .eq('doctor_id', userId)
            .order('is_main', ascending: false);
        doctorBranches = List<Map<String, dynamic>>.from(res as List);
      } catch (_) {}
    }

    // تحديد الفروع المبدئية المختارة
    Set<String> selectedBranchIds = {};
    final reqBranchIds = (req['selected_branch_ids'] as List?)?.map((e) => e.toString()).toSet();
    if (reqBranchIds != null && reqBranchIds.isNotEmpty) {
      selectedBranchIds = Set.from(reqBranchIds);
    } else if (doctorBranches.isNotEmpty) {
      selectedBranchIds = doctorBranches.map((b) => b['id'].toString()).toSet();
    }

    // استخراج عدد الأشهر الأصلي الذي حدده المشترك بدقة فائقة
    int requestedMonths = 1;
    if (planName.contains('12') || (planName.contains('سنوية') && !planName.contains('نصف') && !planName.contains('ربع'))) {
      requestedMonths = 12;
    } else if (planName.contains('6') || planName.contains('نصف سنوي')) {
      requestedMonths = 6;
    } else if (planName.contains('3') || planName.contains('ربع سنوي')) {
      requestedMonths = 3;
    } else if (planName.contains('1') || planName.contains('شهر واحد') || planName.contains('شهرية')) {
      requestedMonths = 1;
    } else if (req['months'] != null) {
      requestedMonths = (req['months'] as num).toInt();
    }

    int selectedDays = requestedMonths == 12 ? 365 : (requestedMonths * 30);
    DateTime calculatedExpiryDate = DateTime.now().add(Duration(days: selectedDays));
    final daysCtrl = TextEditingController(text: selectedDays.toString());
    final notesCtrl = TextEditingController();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: AdminColors.success, size: 26),
              const SizedBox(width: 8),
              Text('اعتماد وتحديد تاريخ انتهاء الاشتراك 🗓️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // بيانات الطبيب / الصيدلي والطلب الأصلي المقدم
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AdminColors.accentMintLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.cardBorderMint),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                              child: Icon(
                                isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded,
                                color: AdminColors.primaryDark,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        fullName,
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14.5, color: AdminColors.primaryDark),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AdminColors.cardBorderMint),
                                        ),
                                        child: Text(
                                          isDoctor ? 'طبيب 🩺' : 'صيدلية 💊',
                                          style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '📞 $phone • 📍 $gov • $paymentMethod ${senderNumber != null && senderNumber.isNotEmpty ? "($senderNumber)" : ""}',
                                    style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // كارت بيانات الباقة والمدة الأولية التي حددها المشترك
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AdminColors.primaryDark.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.bookmark_added_rounded, size: 16, color: AdminColors.primaryDark),
                                        const SizedBox(width: 4),
                                        Text(
                                          'الباقة والمدة التي طلبها المشترك:',
                                          style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          planName.isNotEmpty ? planName : 'باقة $requestedMonths شهر',
                                          style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13.5, color: AdminColors.primaryDark),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AdminColors.accentMintLight,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AdminColors.cardBorderMint),
                                          ),
                                          child: Text(
                                            'المدة: $requestedMonths شهر (${requestedMonths == 12 ? 365 : requestedMonths * 30} يوم)',
                                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('المبلغ المسدد:', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                                  Text(
                                    '$amount ج.م',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16, color: const Color(0xFF047857)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // كارت معاينة تاريخ الانتهاء الجديد الحي
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
                            Text('تاريخ انتهاء الاشتراك الجديد المحدد:', style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11.5)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AdminColors.accentMint, borderRadius: BorderRadius.circular(6)),
                              child: Text('+$selectedDays يوم', style: GoogleFonts.cairo(color: AdminColors.primaryDark, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          intl.DateFormat('EEEE d MMMM yyyy', 'ar').format(calculatedExpiryDate),
                          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text('1. خيارات المدد السريعة للتمديد (يمكنك التعديل أو إبقاء اختيار المشترك):', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildDurationChip(
                        'شهر واحد (+30 يوم)${requestedMonths == 1 ? " ⭐️ طلب المشترك" : ""}',
                        30,
                        selectedDays,
                        (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        },
                      ),
                      _buildDurationChip(
                        'شهرين (+60 يوم)${requestedMonths == 2 ? " ⭐️ طلب المشترك" : ""}',
                        60,
                        selectedDays,
                        (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        },
                      ),
                      _buildDurationChip(
                        '3 أشهر (+90 يوم)${requestedMonths == 3 ? " ⭐️ طلب المشترك" : ""}',
                        90,
                        selectedDays,
                        (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        },
                      ),
                      _buildDurationChip(
                        '6 أشهر (+180 يوم)${requestedMonths == 6 ? " ⭐️ طلب المشترك" : ""}',
                        180,
                        selectedDays,
                        (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        },
                      ),
                      _buildDurationChip(
                        'سنة كاملة (+365 يوم)${requestedMonths == 12 ? " ⭐️ طلب المشترك" : ""}',
                        365,
                        selectedDays,
                        (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: daysCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null && parsed > 0) {
                              setDialogState(() {
                                selectedDays = parsed;
                                calculatedExpiryDate = DateTime.now().add(Duration(days: parsed));
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'أو اكتب عدد الأيام يدوياً',
                            suffixText: 'يوم',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month_rounded, size: 18, color: AdminColors.primaryDark),
                        label: Text('اختيار تاريخ', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: calculatedExpiryDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (picked != null) {
                            final diff = picked.difference(DateTime.now()).inDays + 1;
                            setDialogState(() {
                              calculatedExpiryDate = picked;
                              selectedDays = diff > 0 ? diff : 1;
                              daysCtrl.text = selectedDays.toString();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات الإدارة (اختياري)',
                      hintText: 'مثال: تم التأكد من التحويل واعتماد التجديد بنجاح',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  // قسم اختيار وتحديد الفروع المراد تشغيلها وتفعيلها للاشتراك
                  if (isDoctor && doctorBranches.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.primaryDark.withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.storefront_rounded, size: 20, color: AdminColors.primaryDark),
                                  const SizedBox(width: 8),
                                  Text(
                                    'تحديد العيادات المشمولة في هذا الاشتراك:',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13, color: AdminColors.textPrimary),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: selectedBranchIds.isNotEmpty ? AdminColors.accentMintLight : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'محدد: ${selectedBranchIds.length} من أصل ${doctorBranches.length} عيادة',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: selectedBranchIds.isNotEmpty ? AdminColors.primaryDark : AdminColors.emergency,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // أزرار تحديد سريعة
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    selectedBranchIds = doctorBranches.map((b) => b['id'].toString()).toSet();
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: selectedBranchIds.length == doctorBranches.length ? AdminColors.primaryDark : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'تحديد كافة العيادات (الكل) 🏢',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: selectedBranchIds.length == doctorBranches.length ? Colors.white : Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    final main = doctorBranches.firstWhere((b) => b['is_main'] == true, orElse: () => doctorBranches.first);
                                    selectedBranchIds = {main['id'].toString()};
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (selectedBranchIds.length == 1 &&
                                            doctorBranches.any((b) => b['is_main'] == true && selectedBranchIds.contains(b['id'].toString())))
                                        ? const Color(0xFFB78103)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'الفرع الرئيسي فقط ⭐️',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: (selectedBranchIds.length == 1 &&
                                              doctorBranches.any((b) => b['is_main'] == true && selectedBranchIds.contains(b['id'].toString())))
                                          ? Colors.white
                                          : Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // قائمة الفروع مع Checkboxes
                          ...doctorBranches.map((b) {
                            final bId = b['id'].toString();
                            final isChecked = selectedBranchIds.contains(bId);
                            final isMain = b['is_main'] == true;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isChecked ? AdminColors.accentMintLight.withValues(alpha: 0.35) : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isChecked ? AdminColors.primaryDark.withValues(alpha: 0.3) : Colors.grey.shade200,
                                  width: isChecked ? 1.3 : 1,
                                ),
                              ),
                              child: CheckboxListTile(
                                value: isChecked,
                                activeColor: AdminColors.primaryDark,
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        b['name'] ?? 'الفرع',
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: isChecked ? AdminColors.textPrimary : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    if (isMain) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF8E1),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(color: const Color(0xFFFFB300)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 12),
                                            const SizedBox(width: 3),
                                            Text(
                                              'المقر الرئيسي',
                                              style: GoogleFonts.cairo(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFFB78103)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  '📍 ${b['governorate'] ?? ''} - ${b['address_text'] ?? ''}',
                                  style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
                                ),
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      selectedBranchIds.add(bId);
                                    } else {
                                      if (selectedBranchIds.length > 1) {
                                        selectedBranchIds.remove(bId);
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('يجب الإبقاء على عيادة واحدة على الأقل للاشتراك'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  });
                                },
                              ),
                            );
                          }),
                          const SizedBox(height: 6),
                          Text(
                            '💡 تنبيه الحوكمة: العيادات المحددة ستعمل فورياً وتنتهي في موعد الانتهاء الموحد (${intl.DateFormat('yyyy/MM/dd').format(calculatedExpiryDate)}). أي عيادة غير محددة ستظل معطلة في المنظومة حتى يتم تجديدها لاحقاً.',
                            style: GoogleFonts.cairo(fontSize: 11, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: (isDoctor && selectedBranchIds.isEmpty) ? Colors.grey : AdminColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: (isDoctor && selectedBranchIds.isEmpty)
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      final isMainOnly = isDoctor &&
                          selectedBranchIds.length == 1 &&
                          doctorBranches.any((b) => b['is_main'] == true && selectedBranchIds.contains(b['id'].toString()));

                      _approveSubscriptionWithDays(
                        reqId: reqId,
                        userId: userId,
                        days: selectedDays,
                        exactExpiryDate: calculatedExpiryDate,
                        adminNotes: notesCtrl.text.trim(),
                        mainBranchOnly: isMainOnly,
                        activeBranchIds: isDoctor ? selectedBranchIds.toList() : null,
                      );
                    },
              child: Text(
                isDoctor && doctorBranches.length > 1
                    ? 'تأكيد اعتماد الاشتراك (${selectedBranchIds.length} عيادة محددة) 🚀'
                    : 'تأكيد الاعتماد وتمديد المدة 🚀',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(String label, int days, int currentDays, Function(int) onSelect) {
    final isSelected = currentDays == days;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AdminColors.primaryDark,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      onSelected: (_) => onSelect(days),
    );
  }

  /// حوار الرفض مع كتابة السبب
  void _showRejectDialog(Map<String, dynamic> req) {
    final reqId = req['id'] as String;
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('رفض إيصال السداد ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('يرجى توضيح سبب الرفض ليظهر للطبيب في حسابه:', style: GoogleFonts.cairo(fontSize: 12.5)),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'مثال: صورة الإيصال غير واضحة أو المبلغ المحول غير مكتمل...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.emergency, foregroundColor: Colors.white),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);

              final previousList = List<Map<String, dynamic>>.from(_requests);
              setState(() => _requests.removeWhere((r) => r['id'] == reqId));

              try {
                await _client.rpc('reject_subscription_request', params: {
                  'p_request_id': reqId,
                  'p_reason': reason,
                });

                AdminAuditService.log(
                  actionType: 'رفض إيصال سداد اشتراك',
                  targetType: 'SUBSCRIPTION',
                  targetId: reqId,
                  targetName: 'طلب اشتراك $reqId',
                  status: 'REJECTED',
                  details: {'reason': reason},
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم رفض الإيصال وحفظ السبب'), backgroundColor: AdminColors.emergency),
                  );
                }
              } catch (e) {
                if (mounted) setState(() => _requests = previousList);
              }
            },
            child: Text('تأكيد الرفض', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showReceiptInspectorModal(Map<String, dynamic> req) {
    final profile = req['profiles'] as Map<String, dynamic>? ?? {};
    final receiptUrl = req['receipt_image_url'] as String?;
    final fullName = profile['full_name'] ?? 'الشريك';
    final amount = req['amount'] ?? req['amount_paid'] ?? 350;
    final months = req['months'] ?? 1;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 650,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('معاينة إيصال سداد: $fullName', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                Text('المبلغ: $amount ج.م • المدة: $months شهر', style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary)),
                const SizedBox(height: 16),
                if (receiptUrl != null && receiptUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      receiptUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, stack) => Container(
                        padding: const EdgeInsets.all(40),
                        color: Colors.grey.shade100,
                        child: const Center(child: Text('تعذر تحميل الصورة')),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(30),
                    color: Colors.grey.shade100,
                    child: const Center(child: Text('لا توجد صورة إيصال مرفقة')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _requests.where((r) {
      final role = (r['role'] ?? '').toString().toUpperCase();
      if (_selectedRoleFilter == 'أطباء' && role != 'DOCTOR') return false;
      if (_selectedRoleFilter == 'صيدليات' && role != 'PHARMACY') return false;

      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final profile = r['profiles'] as Map<String, dynamic>? ?? {};
      final name = (profile['full_name'] as String? ?? '').toLowerCase();
      final phone = (profile['phone'] as String? ?? '').toLowerCase();
      final sender = (r['sender_number'] as String? ?? '').toLowerCase();
      final ref = (r['transaction_reference'] as String? ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q) || sender.contains(q) || ref.contains(q);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Refresh Action
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AdminColors.primaryDark.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'إدارة الاشتراكات والمدفوعات البنكية',
                        style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تدقيق إيصالات سداد الأطباء والصيدليات (فودافون كاش، إنستاباي، بنك) وتمديد الباقات والتحكم بالمدد',
                    style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث الإيصالات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: _fetchRequests,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 1. Top KPI Summary Strip
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'طلبات قيد المراجعة',
                  count: _counts['PENDING'] ?? 0,
                  icon: Icons.hourglass_top_rounded,
                  color: const Color(0xFFF59E0B), // Amber
                  bgColor: const Color(0xFFFFFBEB),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  title: 'إيصالات معتمدة',
                  count: _counts['APPROVED'] ?? 0,
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF10B981), // Emerald
                  bgColor: const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  title: 'إيصالات مرفوضة',
                  count: _counts['REJECTED'] ?? 0,
                  icon: Icons.cancel_rounded,
                  color: const Color(0xFFEF4444), // Red
                  bgColor: const Color(0xFFFEF2F2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 2. Toolbar: Search Bar & Role Filters
          Row(
            children: [
              // Search Bar
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم الطبيب، رقم الهاتف، رقم المعاملة، أو رقم المحفظة...',
                      hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Role Filter Chips
              AdminFilterChips(
                options: const ['الكل', 'أطباء', 'صيدليات'],
                selectedOption: _selectedRoleFilter,
                onSelected: (val) => setState(() => _selectedRoleFilter = val),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 3. Modern Segmented Tab Bar with Badges
          AdminModernTabBar(
            selectedIndex: _tabController.index,
            onTabSelected: (index) {
              _tabController.animateTo(index);
            },
            tabs: [
              AdminTabItem(
                label: 'إيصالات قيد المراجعة',
                icon: Icons.hourglass_top_rounded,
                count: _counts['PENDING'] ?? 0,
                badgeColor: const Color(0xFFF59E0B),
              ),
              AdminTabItem(
                label: 'إيصالات معتمدة',
                icon: Icons.verified_rounded,
                count: _counts['APPROVED'] ?? 0,
                badgeColor: const Color(0xFF10B981),
              ),
              AdminTabItem(
                label: 'إيصالات مرفوضة',
                icon: Icons.cancel_outlined,
                count: _counts['REJECTED'] ?? 0,
                badgeColor: const Color(0xFFEF4444),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 4. List of Requests / Empty State
          if (_isLoading && _requests.isEmpty)
            const AdminTableSkeleton(rows: 6)
          else if (filtered.isEmpty)
            AdminEmptyStateCard(
              title: 'لا توجد إيصالات في هذا القسم',
              description: _searchQuery.isNotEmpty
                  ? 'لم نتمكن من العثور على أي نتائج مطابقة لكلمة البحث "$_searchQuery".'
                  : 'لا توجد طلبات اشتراك مسجلة بحالة "${_currentStatusTab == 'PENDING' ? 'قيد المراجعة' : (_currentStatusTab == 'APPROVED' ? 'معتمدة' : 'مرفوضة')}" حالياً.',
              icon: Icons.receipt_long_outlined,
              onRefresh: _fetchRequests,
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final req = filtered[index];
                return _buildRequestCard(req);
              },
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
              color: bgColor,
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
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  '$count',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AdminColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final profile = req['profiles'] as Map<String, dynamic>? ?? {};
    final fullName = profile['full_name'] ?? 'طبيب المنظومة';
    final phone = profile['phone'] ?? '';
    final gov = profile['governorate'] ?? 'مصر';
    final role = (req['role'] ?? profile['role'] ?? 'DOCTOR').toString().toUpperCase();
    final isDoctor = role == 'DOCTOR';
    final amount = req['amount'] ?? req['amount_paid'] ?? 350;
    final months = req['months'] ?? 1;
    final planName = req['plan_name'] ?? '$months شهر';
    final paymentMethod = req['payment_method'] ?? 'تحويل إلكتروني';
    final senderNumber = req['sender_number'] as String?;
    final dateStr = req['created_at'] as String?;
    final status = (req['status'] as String? ?? 'PENDING').toUpperCase();
    final isPending = status == 'PENDING';
    final receiptUrl = req['receipt_image_url'] as String?;

    String formattedDate = '';
    if (dateStr != null) {
      try {
        formattedDate = intl.DateFormat('yyyy/MM/dd - hh:mm a').format(DateTime.parse(dateStr));
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending ? const Color(0xFFFED7AA) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Avatar, Info & Price Tag
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDoctor
                        ? [const Color(0xFF0F766E), const Color(0xFF14B8A6)]
                        : [const Color(0xFF0284C7), const Color(0xFF38BDF8)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // Name & Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fullName,
                            style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 15.5, color: AdminColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDoctor ? const Color(0xFFCCFBF1) : const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isDoctor ? 'طبيب' : 'صيدلية',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDoctor ? const Color(0xFF0F766E) : const Color(0xFF0369A1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 13, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(phone, style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF64748B)),
                        const SizedBox(width: 3),
                        Text(gov, style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF64748B))),
                      ],
                    ),
                  ],
                ),
              ),

              // Price Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$amount ج.م',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16, color: const Color(0xFF065F46)),
                    ),
                    Text(
                      planName,
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF047857)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Metadata Chips Row (Payment method, extra branches, dates)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Payment Method
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Color(0xFF475569)),
                    const SizedBox(width: 5),
                    Text(
                      '$paymentMethod ${senderNumber != null && senderNumber.isNotEmpty ? "($senderNumber)" : ""}',
                      style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                    ),
                  ],
                ),
              ),

              // Extra Branches tag
              if ((req['extra_branches_count'] as int? ?? 0) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 15, color: Color(0xFFD97706)),
                      const SizedBox(width: 4),
                      Text(
                        'يشمل المقر الرئيسي + ${req['extra_branches_count']} فروع إضافية (+${req['extra_branches_amount']} ج.م)',
                        style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFFB45309)),
                      ),
                    ],
                  ),
                ),

              // Date
              Text(
                'تاريخ الإرسال: $formattedDate',
                style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),

          if (req['start_date'] != null && req['end_date'] != null) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final s = DateTime.tryParse(req['start_date'])?.toLocal();
              final e = DateTime.tryParse(req['end_date'])?.toLocal();
              if (s != null && e != null) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Text(
                    'الفترة المعتمدة: من ${intl.DateFormat('yyyy/MM/dd').format(s)} إلى ${intl.DateFormat('yyyy/MM/dd').format(e)}',
                    style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],

          if (req['rejection_reason'] != null && (req['rejection_reason'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                'سبب الرفض: ${req['rejection_reason']}',
                style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFFB91C1C)),
              ),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          // Bottom Actions Row with Interactive Receipt Thumbnail
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Receipt Preview Button with Mini Thumbnail
              InkWell(
                onTap: () => _showReceiptInspectorModal(req),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (receiptUrl != null && receiptUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            receiptUrl,
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => const Icon(Icons.receipt_rounded, size: 18, color: AdminColors.primaryDark),
                          ),
                        )
                      else
                        const Icon(Icons.receipt_rounded, size: 18, color: AdminColors.primaryDark),
                      const SizedBox(width: 8),
                      Text(
                        'معاينة وتكبير صورة الإيصال 🔍',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.primaryDark),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              if (isPending)
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: Text('رفض الطلب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _showRejectDialog(req),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text('اعتماد وتمديد المدة ⚡', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      onPressed: () => _showApproveDurationDialog(req),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

