import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
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
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
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
      }
    } catch (e) {
      debugPrint('Error fetching subscription requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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
        final expiresAt = (exactExpiryDate ?? DateTime.now().add(Duration(days: days))).toIso8601String();
        await _client.from('subscription_requests').update({
          'status': 'APPROVED',
          'reviewed_at': DateTime.now().toIso8601String(),
          'start_date': DateTime.now().toIso8601String(),
          'end_date': expiresAt,
          'notes': adminNotes,
        }).eq('id', reqId);

        await _client.from('doctors').update({
          'subscription_status': 'ACTIVE',
          'subscription_expires_at': expiresAt,
        }).eq('id', userId);

        await _client.from('pharmacies').update({
          'subscription_status': 'ACTIVE',
          'subscription_expires_at': expiresAt,
        }).eq('id', userId);

        await _client.from('profiles').update({'is_approved': true}).eq('id', userId);
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
  void _showApproveDurationDialog(Map<String, dynamic> req) {
    final reqId = req['id'] as String;
    final userId = req['user_id'] as String;
    final profile = req['profiles'] as Map<String, dynamic>? ?? {};
    final fullName = profile['full_name'] ?? 'الطبيب / الصيدلي';
    final requestedMonths = req['months'] ?? 1;
    final amount = req['amount'] ?? req['amount_paid'] ?? 350;

    int selectedDays = (requestedMonths as int) * 30;
    DateTime calculatedExpiryDate = DateTime.now().add(Duration(days: selectedDays));
    final daysCtrl = TextEditingController(text: selectedDays.toString());
    final notesCtrl = TextEditingController();

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
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // بيانات الطبيب والطلب
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AdminColors.accentMintLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminColors.primaryDark.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_rounded, color: AdminColors.primaryDark, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fullName, style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14, color: AdminColors.primaryDark)),
                              Text('المبلغ المسدد: $amount ج.م • المدة المطلوبة: $requestedMonths شهر', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade800)),
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
                  Text('1. خيارات المدد السريعة للتمديد:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildDurationChip('شهر واحد (+30 يوم)', 30, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                          calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                        });
                      }),
                      _buildDurationChip('شهرين (+60 يوم)', 60, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                          calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                        });
                      }),
                      _buildDurationChip('3 أشهر (+90 يوم)', 90, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                          calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                        });
                      }),
                      _buildDurationChip('6 أشهر (+180 يوم)', 180, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                          calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                        });
                      }),
                      _buildDurationChip('سنة كاملة (+365 يوم)', 365, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                          calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                        });
                      }),
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
                  if ((req['extra_branches_count'] as int? ?? 0) > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminColors.accentMintLight.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AdminColors.cardBorderMint),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.storefront_rounded, size: 18, color: AdminColors.primaryDark),
                              const SizedBox(width: 6),
                              Text('تفاصيل الفروع الإضافية في هذا الطلب:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'المبلغ يشمل ${req['extra_branches_count']} فرع إضافي مسجل (+${req['extra_branches_amount']} ج.م). في حال كان المبلغ المحول في الوصل للباقة الأساسية فقط، يمكنك اختيار "اعتماد للفرع الأساسي فقط".',
                            style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textPrimary),
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
            if ((req['extra_branches_count'] as int? ?? 0) > 0)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber.shade900,
                  side: BorderSide(color: Colors.amber.shade700),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: Text('اعتماد للفرع الأساسي فقط وتعطيل الباقي ⚠️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _approveSubscriptionWithDays(
                    reqId: reqId,
                    userId: userId,
                    days: selectedDays,
                    exactExpiryDate: calculatedExpiryDate,
                    adminNotes: notesCtrl.text.trim().isNotEmpty
                        ? notesCtrl.text.trim()
                        : 'تم اعتماد الباقة الأساسية فقط وتعطيل الفروع الإضافية لعدم اكتمال سداد رسومها',
                    mainBranchOnly: true,
                  );
                },
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
              onPressed: () {
                Navigator.pop(ctx);
                final branchIds = (req['selected_branch_ids'] as List?)?.map((e) => e.toString()).toList();
                _approveSubscriptionWithDays(
                  reqId: reqId,
                  userId: userId,
                  days: selectedDays,
                  exactExpiryDate: calculatedExpiryDate,
                  adminNotes: notesCtrl.text.trim(),
                  mainBranchOnly: false,
                  activeBranchIds: branchIds,
                );
              },
              child: Text(
                'تأكيد الاعتماد لكافة الفروع 🚀',
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
                await _client.from('subscription_requests').update({
                  'status': 'REJECTED',
                  'rejection_reason': reason,
                  'reviewed_at': DateTime.now().toIso8601String(),
                }).eq('id', reqId);

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
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final profile = r['profiles'] as Map<String, dynamic>? ?? {};
      final name = (profile['full_name'] as String? ?? '').toLowerCase();
      final phone = (profile['phone'] as String? ?? '').toLowerCase();
      final sender = (r['sender_number'] as String? ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q) || sender.contains(q);
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
                        decoration: BoxDecoration(color: AdminColors.primaryDark.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.receipt_long_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text('إدارة الاشتراكات والمدفوعات البنكية 💳', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('تدقيق إيصالات سداد الأطباء والصيدليات (فودافون كاش، إنستاباي) وتمديد الباقات والتحكم بالمدد', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث الإيصالات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchRequests,
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.cardBorderMint),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.cairo(fontSize: 13),
              decoration: InputDecoration(
                hintText: '🔍 ابحث باسم الطبيب، رقم الهاتف، أو رقم المحفظة المحول منها...',
                prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Tabs
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AdminColors.primaryDark,
              unselectedLabelColor: Colors.grey.shade600,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
              ),
              tabs: const [
                Tab(text: 'إيصالات قيد المراجعة ⏳'),
                Tab(text: 'إيصالات معتمدة ✅'),
                Tab(text: 'إيصالات مرفوضة ❌'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // List
          Expanded(
            child: _isLoading && _requests.isEmpty
                ? const SingleChildScrollView(
                    child: AdminTableSkeleton(rows: 6),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Text('لا توجد طلبات اشتراك في هذا القسم حالياً', style: GoogleFonts.cairo(fontSize: 14, color: AdminColors.textSecondary)),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final req = filtered[index];
                          return _buildRequestCard(req);
                        },
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
    final paymentMethod = req['payment_method'] ?? 'تحويل إلكتروني';
    final senderNumber = req['sender_number'] as String?;
    final dateStr = req['created_at'] as String?;
    final status = (req['status'] as String? ?? 'PENDING').toUpperCase();
    final isPending = status == 'PENDING';

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
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isDoctor ? AdminColors.primaryDark.withValues(alpha: 0.1) : Colors.teal.shade50,
                    child: Icon(isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded, color: isDoctor ? AdminColors.primaryDark : Colors.teal),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fullName, style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 15)),
                      Text('$phone • $gov', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AdminColors.accentMintLight, borderRadius: BorderRadius.circular(8)),
                child: Text('$amount ج.م ($months شهر)', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13, color: AdminColors.primaryDark)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('طريقة الدفع: $paymentMethod ${senderNumber != null && senderNumber.isNotEmpty ? "• من رقم: $senderNumber" : ""}', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade800)),
          if ((req['extra_branches_count'] as int? ?? 0) > 0) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 14, color: AdminColors.primaryDark),
                const SizedBox(width: 4),
                Text(
                  'يشمل ${req['extra_branches_count']} فرع إضافي (+${req['extra_branches_amount']} ج.م)',
                  style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                ),
              ],
            ),
          ],
          if (req['start_date'] != null && req['end_date'] != null) ...[
            Builder(builder: (context) {
              final s = DateTime.tryParse(req['start_date'])?.toLocal();
              final e = DateTime.tryParse(req['end_date'])?.toLocal();
              if (s != null && e != null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'الفترة المعتمدة: من ${intl.DateFormat('yyyy/MM/dd').format(s)} إلى ${intl.DateFormat('yyyy/MM/dd').format(e)}',
                    style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
          Text('تاريخ الإرسال: $formattedDate', style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.image_search_rounded, size: 18),
                label: Text('معاينة صورة الإيصال 📷', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                onPressed: () => _showReceiptInspectorModal(req),
              ),
              if (isPending)
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AdminColors.emergency, side: const BorderSide(color: AdminColors.emergency)),
                      icon: const Icon(Icons.cancel_rounded, size: 16),
                      label: Text('رفض ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _showRejectDialog(req),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AdminColors.success, foregroundColor: Colors.white),
                      icon: const Icon(Icons.verified_rounded, size: 16),
                      label: Text('اعتماد وتمديد المدة 🌟', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
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
