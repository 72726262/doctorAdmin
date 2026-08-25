import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class SubscriptionRequestsScreen extends StatefulWidget {
  const SubscriptionRequestsScreen({super.key});

  @override
  State<SubscriptionRequestsScreen> createState() => _SubscriptionRequestsScreenState();
}

class _SubscriptionRequestsScreenState extends State<SubscriptionRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _client = AdminSupabaseConfig.client;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _fetchRequests();
      }
    });
    _fetchRequests();
  }

  @override
  void dispose() {
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

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
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
        setState(() {
          _requests = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching subscription requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// اعتماد فوري وتمديد الاشتراك بعدد الأيام المحددة
  Future<void> _approveSubscriptionWithDays(String reqId, String userId, int days, String? adminNotes) async {
    // 1. تحديث لحظي في الذاكرة فوراً لسرعة وسلاسة الواجهة
    final previousList = List<Map<String, dynamic>>.from(_requests);
    setState(() {
      _requests.removeWhere((r) => r['id'] == reqId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎉 تم اعتماد الإيصال وتمديد اشتراك الحساب لـ $days يوماً بنجاح!'),
        backgroundColor: AdminColors.success,
        duration: const Duration(seconds: 2),
      ),
    );

    // 2. المزامنة مع السيرفر عبر الـ RPC
    try {
      final res = await _client.rpc('admin_approve_subscription_with_custom_days', params: {
        'p_request_id': reqId,
        'p_days': days,
        'p_admin_notes': adminNotes,
      });
      debugPrint('Approval result: $res');
    } catch (e) {
      debugPrint('Fallback manual update: $e');
      try {
        final expiresAt = DateTime.now().add(Duration(days: days)).toIso8601String();
        await _client.from('subscription_requests').update({
          'status': 'APPROVED',
          'reviewed_at': DateTime.now().toIso8601String(),
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

  /// حوار اعتماد وتحديد مدة التمديد
  void _showApproveDurationDialog(Map<String, dynamic> req) {
    final reqId = req['id'] as String;
    final userId = req['user_id'] as String;
    final profile = req['profiles'] as Map<String, dynamic>? ?? {};
    final fullName = profile['full_name'] ?? 'الطبيب / الصيدلي';
    final requestedMonths = req['months'] ?? 1;
    final amount = req['amount'] ?? req['amount_paid'] ?? 350;

    int selectedDays = (requestedMonths as int) * 30;
    final daysCtrl = TextEditingController(text: selectedDays.toString());
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AdminColors.success, size: 24),
              const SizedBox(width: 8),
              Text('اعتماد إيصال السداد وتمديد الاشتراك 🌟', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AdminColors.accentMintLight, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.person_rounded, color: AdminColors.primaryDark, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$fullName • المبلغ: $amount ج.م (طلب $requestedMonths شهر)',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primaryDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('حدد عدد الأيام المراد تمديدها للحساب:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildDurationChip('30 يوماً (شهر)', 30, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                        });
                      }),
                      _buildDurationChip('60 يوماً (شهرين)', 60, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                        });
                      }),
                      _buildDurationChip('90 يوماً (3 أشهر)', 90, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                        });
                      }),
                      _buildDurationChip('180 يوماً (6 أشهر)', 180, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                        });
                      }),
                      _buildDurationChip('365 يوماً (سنة)', 365, selectedDays, (d) {
                        setDialogState(() {
                          selectedDays = d;
                          daysCtrl.text = d.toString();
                        });
                      }),
                    ],
                  ),

                  const SizedBox(height: 14),
                  TextField(
                    controller: daysCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed > 0) {
                        setDialogState(() => selectedDays = parsed);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'أو اكتب عدد الأيام يدوياً',
                      suffixText: 'يوم',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات الإدارة (اختياري)',
                      hintText: 'مثال: تم التأكد من وصول الحوالة عبر فودافون كاش',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.success, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                _approveSubscriptionWithDays(reqId, userId, selectedDays, notesCtrl.text.trim());
              },
              child: Text('تأكيد الاعتماد والتمديد ($selectedDays يوم) 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم رفض الإيصال وحفظ السبب'), backgroundColor: AdminColors.emergency),
                );
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
                      errorBuilder: (_, __, ___) => Container(
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
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
