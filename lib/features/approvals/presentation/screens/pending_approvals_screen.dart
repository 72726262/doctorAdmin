import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final _client = AdminSupabaseConfig.client;
  final _realtimeManager = AdminRealtimeManager();
  final TextEditingController _searchController = TextEditingController();

  static final Map<String, List<Map<String, dynamic>>> _cache = {};

  int _selectedTabIndex = 0; // 0: PENDING, 1: APPROVED, 2: REJECTED
  String _selectedRoleFilter = 'ALL'; // 'ALL', 'doctor', 'pharmacy'
  String _searchQuery = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _verificationsList = [];

  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;

  @override
  void initState() {
    super.initState();
    _realtimeManager.addPartnerListener(_onRealtimePartner);
    _onFilterChanged();
    _fetchStatusCounts();
  }

  void _onFilterChanged() {
    final cacheKey = '${_currentStatusTab}_$_selectedRoleFilter';
    if (_cache.containsKey(cacheKey) && _cache[cacheKey]!.isNotEmpty) {
      setState(() {
        _verificationsList = _cache[cacheKey]!;
        _isLoading = false;
      });
      _fetchVerifications(silent: true);
    } else {
      _fetchVerifications(silent: false);
    }
  }

  void _onRealtimePartner() {
    if (mounted) {
      _fetchVerifications(silent: true);
      _fetchStatusCounts();
    }
  }

  @override
  void dispose() {
    _realtimeManager.removePartnerListener(_onRealtimePartner);
    _searchController.dispose();
    super.dispose();
  }

  String get _currentStatusTab {
    switch (_selectedTabIndex) {
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

  Future<void> _fetchStatusCounts() async {
    try {
      final res = await _client.from('partner_verifications').select('status');
      int pending = 0;
      int approved = 0;
      int rejected = 0;
      for (final row in (res as List)) {
        final st = (row['status'] as String? ?? '').toUpperCase();
        if (st == 'PENDING') {
          pending++;
        } else if (st == 'APPROVED') {
          approved++;
        } else if (st == 'REJECTED') {
          rejected++;
        }
      }
      if (mounted) {
        setState(() {
          _pendingCount = pending;
          _approvedCount = approved;
          _rejectedCount = rejected;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchVerifications({bool silent = false}) async {
    final cacheKey = '${_currentStatusTab}_$_selectedRoleFilter';
    if (!silent && _verificationsList.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      var query = _client.from('partner_verifications').select('''
        id,
        user_id,
        role,
        full_name,
        phone,
        governorate,
        specialty,
        bio,
        id_front_url,
        id_back_url,
        national_id_front_url,
        national_id_back_url,
        syndicate_card_url,
        practice_license_url,
        commercial_register_url,
        tax_card_url,
        status,
        rejection_reason,
        created_at,
        reviewed_at,
        profiles (
          is_approved,
          fcm_token
        )
      ''');

      if (_currentStatusTab != 'ALL') {
        query = query.eq('status', _currentStatusTab);
      }
      if (_selectedRoleFilter != 'ALL') {
        query = query.eq('role', _selectedRoleFilter);
      }

      final res = await query.order('created_at', ascending: false);
      List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(res as List);

      if (mounted) {
        setState(() {
          _verificationsList = list;
          _cache[cacheKey] = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching verifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// حوار تحديد وتخصيص فترة الاشتراك واعتماد حساب الشريك (Doctor / Pharmacy Onboarding Duration)
  void _showApproveDurationDialog(Map<String, dynamic> item) {
    final fullName = item['full_name'] as String? ?? 'الشريك الجديد';
    final role = (item['role'] as String? ?? 'DOCTOR').toUpperCase();
    final isDoctor = role == 'DOCTOR';
    final specialty = item['specialty'] as String? ?? (isDoctor ? 'تخصص عام' : 'صيدلية مجتمعية');
    final governorate = item['governorate'] as String? ?? 'مصر';
    final phone = item['phone'] as String? ?? 'غير متوفر';

    int selectedDays = 30; // 30 يوماً كخيار افتراضي قياسي موصى به
    DateTime calculatedExpiryDate = DateTime.now().add(Duration(days: selectedDays));
    final daysCtrl = TextEditingController(text: selectedDays.toString());
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final gracePeriodEnd = calculatedExpiryDate.add(const Duration(days: 3));

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdminColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified_user_rounded, color: AdminColors.success, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اعتماد الحساب وتحديد فترة الاشتراك 🗓️',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16.5, color: AdminColors.textPrimary),
                      ),
                      Text(
                        'حدد مدة الاشتراك الأولي أو التجريبي لهذا الحساب بحرية كاملة',
                        style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // كارت هوية الطبيب / الصيدلي
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminColors.backgroundCanvas,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.cardBorderMint),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                            child: Icon(
                              isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded,
                              color: AdminColors.primaryDark,
                              size: 20,
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
                                      style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13.5, color: AdminColors.textPrimary),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDoctor ? AdminColors.accentMintLight : Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isDoctor ? AdminColors.cardBorderMint : Colors.teal.shade200),
                                      ),
                                      child: Text(
                                        isDoctor ? 'طبيب جديد 🩺' : 'صيدلية جديدة 💊',
                                        style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '$specialty • $governorate • 📞 $phone',
                                  style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // كارت المعاينة الزمني التفاعلي الحي (Live Calculated Expiry Preview)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D3B2E), Color(0xFF1B5E4B)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D3B2E).withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'تاريخ انتهاء الاشتراك المعتمد:',
                                style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AdminColors.accentMint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '+$selectedDays يوم',
                                  style: GoogleFonts.cairo(
                                    color: AdminColors.primaryDark,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            intl.DateFormat('EEEE d MMMM yyyy', 'ar').format(calculatedExpiryDate),
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.shield_outlined, color: AdminColors.accentMint, size: 15),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'فترة سماح إضافية تلقائية (+3 أيام) حتى: ${intl.DateFormat('yyyy/MM/dd').format(gracePeriodEnd)}',
                                  style: GoogleFonts.cairo(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // شرائح المدد الجاهزة بنقرة واحدة
                    Text(
                      '1. خيارات المدد السريعة بنقرة واحدة:',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5, color: AdminColors.textPrimary),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildDurationChip('14 يوماً (أسبوعين تجريبيين)', 14, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        }),
                        _buildDurationChip('30 يوماً (شهر تجريبي كامل) ⭐', 30, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        }),
                        _buildDurationChip('60 يوماً (شهرين)', 60, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        }),
                        _buildDurationChip('90 يوماً (3 أشهر - ربع سنوي)', 90, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        }),
                        _buildDurationChip('180 يوماً (6 أشهر - نصف سنوي)', 180, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        }),
                        _buildDurationChip('365 يوماً (سنة كاملة 👑)', 365, selectedDays, (d) {
                          setDialogState(() {
                            selectedDays = d;
                            daysCtrl.text = d.toString();
                            calculatedExpiryDate = DateTime.now().add(Duration(days: d));
                          });
                        }),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // إدخال يدوي لأي عدد أيام بحرية أو اختيار تاريخ من التقويم
                    Text(
                      '2. أو حدد عدد الأيام أو تاريخ الانتهاء بحرية تامة:',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5, color: AdminColors.textPrimary),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: daysCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              final parsed = int.tryParse(val.trim());
                              if (parsed != null && parsed > 0) {
                                setDialogState(() {
                                  selectedDays = parsed;
                                  calculatedExpiryDate = DateTime.now().add(Duration(days: parsed));
                                });
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'عدد الأيام المخصص',
                              suffixText: 'يوم',
                              prefixIcon: const Icon(Icons.edit_calendar_rounded, size: 18, color: AdminColors.primaryDark),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month_rounded, size: 18, color: AdminColors.primaryDark),
                          label: Text('اختيار تاريخ', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            side: const BorderSide(color: AdminColors.primaryDark),
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

                    const SizedBox(height: 14),

                    // ملاحظات إدارية اختيارية
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        labelText: 'ملاحظات وتوجيهات الإدارة (اختياري)',
                        hintText: 'مثال: باقة ترحيبية مهداة بمناسبة الانضمام للمنظومة...',
                        hintStyle: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                        prefixIcon: const Icon(Icons.note_alt_outlined, size: 18, color: AdminColors.primaryDark),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  'تأكيد الاعتماد وتفعيل الاشتراك ($selectedDays يوم) 🚀',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _approvePartnerWithDuration(
                    item,
                    selectedDays,
                    exactExpiryDate: calculatedExpiryDate,
                    adminNotes: notesCtrl.text.trim(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDurationChip(String label, int days, int currentDays, Function(int) onSelect) {
    final isSelected = currentDays == days;
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
          color: isSelected ? Colors.white : AdminColors.primaryDark,
        ),
      ),
      selected: isSelected,
      selectedColor: AdminColors.primaryDark,
      backgroundColor: AdminColors.accentMintLight.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? AdminColors.primaryDark : AdminColors.cardBorderMint,
        ),
      ),
      onSelected: (_) => onSelect(days),
    );
  }

  /// اعتماد فوري وتحديد مدة الاشتراك وتوثيقها مالياً ورقابياً
  Future<void> _approvePartnerWithDuration(
    Map<String, dynamic> item,
    int days, {
    DateTime? exactExpiryDate,
    String? adminNotes,
  }) async {
    final verificationId = item['id'] as String;
    final userId = item['user_id'] as String;
    final fullName = item['full_name'] as String? ?? 'الشريك';
    final role = (item['role'] as String? ?? 'DOCTOR').toUpperCase();

    final now = DateTime.now();
    final expiryDate = exactExpiryDate ?? now.add(Duration(days: days));
    final gracePeriodDate = expiryDate.add(const Duration(days: 3));
    final formattedExpiry = intl.DateFormat('yyyy/MM/dd').format(expiryDate);

    // 1. تحديث لحظي فوري في الذاكرة (Optimistic Instant Update) في 0 ثانية
    final previousList = List<Map<String, dynamic>>.from(_verificationsList);
    setState(() {
      _verificationsList.removeWhere((v) => v['id'] == verificationId);
      if (_pendingCount > 0) _pendingCount--;
      _approvedCount++;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '🎉 تم اعتماد وتفعيل حساب $fullName بنجاح لمدة $days يوماً حتى ($formattedExpiry)!',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: AdminColors.success,
        duration: const Duration(seconds: 4),
      ),
    );

    // 2. مزامنة الباك إند وقاعدة البيانات بالكامل
    try {
      // أ) تحديث جدول طلبات التوثيق
      await _client.from('partner_verifications').update({
        'status': 'APPROVED',
        'reviewed_at': now.toIso8601String(),
      }).eq('id', verificationId);

      // ب) تحديث حالة الحساب العام
      await _client.from('profiles').update({'is_approved': true}).eq('id', userId);

      // ج) تحديث جدول الأطباء أو الصيدليات بفترة الاشتراك وسماح الحجز
      final partnerData = {
        'subscription_status': 'ACTIVE',
        'subscription_expires_at': expiryDate.toIso8601String(),
        'grace_period_ends_at': gracePeriodDate.toIso8601String(),
      };

      if (role == 'DOCTOR') {
        await _client.from('doctors').update(partnerData).eq('id', userId);
      } else if (role == 'PHARMACY') {
        await _client.from('pharmacies').update(partnerData).eq('id', userId);
      }

      // د) قيد رسمي في جدول المعاملات التاريخية subscription_requests
      final monthsCount = (days / 30).round() > 0 ? (days / 30).round() : 1;
      final defaultNote = 'باقة الانضمام والاعتماد الأولية المعتمدة من الإدارة ($days يوم)';
      final finalNote = adminNotes?.isNotEmpty == true ? adminNotes! : defaultNote;

      await _client.from('subscription_requests').insert({
        'user_id': userId,
        'role': role.isNotEmpty ? role : 'DOCTOR',
        'plan_name': 'باقة الانضمام والاعتماد الأولية ($days يوم)',
        'amount': 0,
        'amount_paid': 0,
        'months': monthsCount,
        'payment_method': 'باقة ترحيبية باعتماد الإدارة 🎁',
        'status': 'APPROVED',
        'start_date': now.toIso8601String(),
        'end_date': expiryDate.toIso8601String(),
        'reviewed_at': now.toIso8601String(),
        'notes': finalNote,
      });

      // هـ) تسجيل العملية في سجل الأمان والرقابة
      AdminAuditService.log(
        actionType: 'اعتماد شريك مع تحديد اشتراك ($days يوم)',
        targetType: role.isNotEmpty ? role : 'PARTNER',
        targetId: userId,
        targetName: fullName,
        details: {
          'verification_id': verificationId,
          'role': role,
          'days': days,
          'start_date': now.toIso8601String(),
          'subscription_expires_at': expiryDate.toIso8601String(),
          'grace_period_ends_at': gracePeriodDate.toIso8601String(),
          'notes': finalNote,
          'specialty': item['specialty'],
          'governorate': item['governorate'],
        },
      );
    } catch (e) {
      // في حالة حدوث خطأ في الاتصال نعيد الحالة السابقة
      if (mounted) {
        setState(() {
          _verificationsList = previousList;
          _pendingCount++;
          if (_approvedCount > 0) _approvedCount--;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إتمام الاعتماد: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  /// رفض فوري لحظي (Optimistic Instant Rejection)
  void _showRejectDialog(Map<String, dynamic> item) {
    final verificationId = item['id'] as String;
    final userId = item['user_id'] as String;
    final fullName = item['full_name'] as String? ?? 'الشريك';
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: AdminColors.emergency, size: 24),
            const SizedBox(width: 8),
            Text('رفض طلب الانضمام ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('يرجى توضيح سبب الرفض للشريك ($fullName):', style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textPrimary)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              style: GoogleFonts.cairo(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'مثال: صورة ترخيص المزاولة غير واضحة، يرجى إعادة رفعها بدقة أعلى...',
                hintStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade500),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.emergency,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('يرجى كتابة سبب الرفض', style: GoogleFonts.cairo())),
                );
                return;
              }
              Navigator.pop(ctx);

              // تحديث لحظي فوري في الذاكرة
              final previousList = List<Map<String, dynamic>>.from(_verificationsList);
              setState(() {
                _verificationsList.removeWhere((v) => v['id'] == verificationId);
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تم رفض الطلب وحفظ السبب للشريك $fullName'),
                  backgroundColor: AdminColors.emergency,
                  duration: const Duration(seconds: 2),
                ),
              );

              try {
                await _client.from('partner_verifications').update({
                  'status': 'REJECTED',
                  'rejection_reason': reason,
                  'reviewed_at': DateTime.now().toIso8601String(),
                }).eq('id', verificationId);

                await _client.from('profiles').update({'is_approved': false}).eq('id', userId);

                // تسجيل الرفض في سجل الرقابة
                AdminAuditService.log(
                  actionType: 'رفض طلب توثيق شريك (KYC)',
                  targetType: (item['role'] as String? ?? 'PARTNER').toUpperCase(),
                  targetId: userId,
                  targetName: fullName,
                  status: 'REJECTED',
                  details: {
                    'verification_id': verificationId,
                    'rejection_reason': reason,
                  },
                );
              } catch (e) {
                if (mounted) {
                  setState(() => _verificationsList = previousList);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency),
                  );
                }
              }
            },
            child: Text('تأكيد الرفض', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  final Map<String, String> _signedUrlCache = {};

  Future<String> _resolveImageUrlAsync(String rawUrl) async {
    if (rawUrl.trim().isEmpty) return '';
    final trimmed = rawUrl.trim();

    if (_signedUrlCache.containsKey(trimmed)) {
      return _signedUrlCache[trimmed]!;
    }

    String bucket = 'identity_documents';
    String filePath = trimmed;

    if (trimmed.contains('/identity_documents/')) {
      bucket = 'identity_documents';
      filePath = trimmed.split('/identity_documents/').last.split('?').first;
    } else if (trimmed.contains('/verification_docs/')) {
      bucket = 'verification_docs';
      filePath = trimmed.split('/verification_docs/').last.split('?').first;
    } else if (trimmed.startsWith('id_') || (!trimmed.startsWith('http') && trimmed.endsWith('.jpg'))) {
      bucket = 'identity_documents';
      filePath = trimmed;
    }

    try {
      final signed = await _client.storage.from(bucket).createSignedUrl(filePath, 1800);
      var resolved = signed;
      if (kIsWeb && Uri.base.scheme == 'https' && resolved.startsWith('http://178.105.236.62:8000')) {
        resolved = resolved.replaceFirst(
          'http://178.105.236.62:8000',
          AdminSupabaseConfig.supabaseUrl,
        );
      }
      _signedUrlCache[trimmed] = resolved;
      return resolved;
    } catch (_) {
      var direct = trimmed;
      if (kIsWeb && Uri.base.scheme == 'https' && direct.startsWith('http://178.105.236.62:8000')) {
        direct = direct.replaceFirst(
          'http://178.105.236.62:8000',
          AdminSupabaseConfig.supabaseUrl,
        );
      }
      _signedUrlCache[trimmed] = direct;
      return direct;
    }
  }

  String _resolveImageUrl(String rawUrl) {
    if (rawUrl.trim().isEmpty) return '';
    final trimmed = rawUrl.trim();
    if (_signedUrlCache.containsKey(trimmed)) {
      return _signedUrlCache[trimmed]!;
    }
    if (kIsWeb && Uri.base.scheme == 'https') {
      if (trimmed.startsWith('http://178.105.236.62:8000')) {
        return trimmed.replaceFirst(
          'http://178.105.236.62:8000',
          AdminSupabaseConfig.supabaseUrl,
        );
      }
    }
    return trimmed;
  }

  void _showFullImage(String url, String title) async {
    if (url.trim().isEmpty) return;
    final resolvedUrl = await _resolveImageUrlAsync(url);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 850, maxHeight: 650),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: AdminColors.primaryDark,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.image_search_rounded, color: AdminColors.accentMint, size: 20),
                        const SizedBox(width: 8),
                        Text(title, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminColors.accentMint,
                            foregroundColor: AdminColors.primaryDark,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: Text('فتح المستند الأصلي ↗', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            final uri = Uri.parse(resolvedUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.network(
                      resolvedUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const Center(
                              child: AdminShimmerBox(
                                width: double.infinity,
                                height: 400,
                                borderRadius: 12,
                              ),
                            ),
                      errorBuilder: (ctx, err, stack) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.description_outlined, size: 48, color: AdminColors.primaryDark),
                            const SizedBox(height: 12),
                            Text('المستند مرفوع ومحفوظ بأمان على السيرفر ✅', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AdminColors.primaryDark,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.visibility_rounded, size: 18),
                              label: Text('عرض وفحص الصورة بدقة كاملة 🔍', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                              onPressed: () async {
                                final uri = Uri.parse(resolvedUrl);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
    // تصفية حية وفورية بناءً على نص البحث بالاسم أو رقم الهاتف
    final filteredList = _verificationsList.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final query = _searchQuery.trim().toLowerCase();
      final name = (item['full_name'] as String? ?? '').toLowerCase();
      final phone = (item['phone'] as String? ?? '').toLowerCase();
      final specialty = (item['specialty'] as String? ?? '').toLowerCase();
      final gov = (item['governorate'] as String? ?? '').toLowerCase();
      return name.contains(query) || phone.contains(query) || specialty.contains(query) || gov.contains(query);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس الصفحة
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
                          color: AdminColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: AdminColors.warning, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'لوحة تدقيق الهوية والاعتماد (KYC)',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'فحص مستندات الأطباء والصيدليات (البطاقة وترخيص المزاولة والسجل التجاري) واعتمادها',
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
                label: Text('تحديث الطلبات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: () {
                  _fetchVerifications();
                  _fetchStatusCounts();
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // كروت المؤشرات العلوية (KPI Metric Summary Cards)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'طلبات معلقة بانتظار التدقيق',
                  count: _pendingCount,
                  subtitle: 'تتطلب فحص وثائق الهوية والترخيص',
                  icon: Icons.hourglass_top_rounded,
                  color: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFFFBEB),
                  borderColor: const Color(0xFFFDE68A),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildKpiCard(
                  title: 'شركاء معتمدين ومفعلين',
                  count: _approvedCount,
                  subtitle: 'حسابات نشطة ومصرح لها بالعمل',
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildKpiCard(
                  title: 'طلبات تم رفضها',
                  count: _rejectedCount,
                  subtitle: 'مستندات غير مستوفية للشروط',
                  icon: Icons.cancel_rounded,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFECACA),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // شريط البحث المباشر (Search Bar by Name & Phone)
          Container(
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
              onChanged: (val) => setState(() => _searchQuery = val),
              style: GoogleFonts.cairo(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: '🔍 ابحث فوراً باسم الطبيب، الصيدلية، التخصص، المحافظة، أو رقم الهاتف...',
                hintStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // التابات العصرية وفلاتر الدور
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // فلاتر التصنيف (طبيب / صيدلية)
              Row(
                children: [
                  Text('التصنيف:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textPrimary)),
                  const SizedBox(width: 8),
                  AdminFilterChips(
                    options: const ['الكل 🌐', 'أطباء 🩺', 'صيدليات 💊'],
                    selectedOption: _selectedRoleFilter == 'ALL'
                        ? 'الكل 🌐'
                        : (_selectedRoleFilter == 'doctor' ? 'أطباء 🩺' : 'صيدليات 💊'),
                    onSelected: (val) {
                      String roleKey = 'ALL';
                      if (val.contains('أطباء')) roleKey = 'doctor';
                      if (val.contains('صيدليات')) roleKey = 'pharmacy';
                      setState(() => _selectedRoleFilter = roleKey);
                      _onFilterChanged();
                    },
                  ),
                ],
              ),

              // تابات الحالة العصرية (معلقة، معتمدة، مرفوضة)
              AdminModernTabBar(
                tabs: [
                  AdminTabItem(
                    label: 'طلبات معلقة',
                    icon: Icons.hourglass_top_rounded,
                    count: _pendingCount,
                    badgeColor: const Color(0xFFF59E0B),
                  ),
                  AdminTabItem(
                    label: 'معتمدة ومفعلة',
                    icon: Icons.check_circle_rounded,
                    count: _approvedCount,
                    badgeColor: const Color(0xFF10B981),
                  ),
                  AdminTabItem(
                    label: 'طلبات مرفوضة',
                    icon: Icons.cancel_rounded,
                    count: _rejectedCount,
                    badgeColor: const Color(0xFFEF4444),
                  ),
                ],
                selectedIndex: _selectedTabIndex,
                onTabSelected: (index) {
                  setState(() => _selectedTabIndex = index);
                  _onFilterChanged();
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // محتوى القائمة
          if (_isLoading && _verificationsList.isEmpty)
            const AdminTableSkeleton(rows: 6)
          else if (filteredList.isEmpty)
            AdminEmptyStateCard(
              title: _searchQuery.isNotEmpty
                  ? 'لا توجد نتائج تطابق بحثك "$_searchQuery"'
                  : (_selectedTabIndex == 0
                      ? 'لا توجد طلبات اعتماد معلقة حالياً'
                      : (_selectedTabIndex == 1
                          ? 'لا يوجد شركاء معتمدين في هذا القسم'
                          : 'لا توجد طلبات مرفوضة في هذا القسم')),
              description: _searchQuery.isNotEmpty
                  ? 'تأكد من كتابة الاسم أو رقم الهاتف بشكل صحيح، أو أعد ضبط الفلاتر.'
                  : 'جميع طلبات توثيق واعتماد الهوية للأطباء والصيدليات تم البت فيها بنجاح.',
              icon: _selectedTabIndex == 0
                  ? Icons.verified_user_rounded
                  : (_selectedTabIndex == 1
                      ? Icons.task_alt_rounded
                      : Icons.folder_open_rounded),
              onRefresh: () {
                _fetchVerifications();
                _fetchStatusCounts();
              },
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final item = filteredList[index];
                return _buildVerificationCard(item);
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$count',
                      style: GoogleFonts.cairo(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AdminColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count > 0 ? 'نشط' : 'فارغ',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
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
                    fontSize: 10.5,
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

  Widget _buildVerificationCard(Map<String, dynamic> item) {
    final role = (item['role'] as String? ?? 'doctor').toLowerCase();
    final isDoctor = role.contains('doc');
    final fullName = item['full_name'] as String? ?? 'غير محدد';
    final phone = item['phone'] as String? ?? 'لا يوجد';
    final governorate = item['governorate'] as String? ?? 'مصر';
    final specialty = item['specialty'] as String? ?? (isDoctor ? 'طب عام' : 'صيدلية');
    final bio = item['bio'] as String? ?? '';
    final status = item['status'] as String? ?? 'PENDING';
    final rejectionReason = item['rejection_reason'] as String?;

    // روابط الصور
    final frontUrl = item['id_front_url'] as String? ?? item['national_id_front_url'] as String? ?? '';
    final backUrl = item['id_back_url'] as String? ?? item['national_id_back_url'] as String? ?? '';
    final syndicateUrl = item['syndicate_card_url'] as String? ?? '';
    final licenseUrl = item['practice_license_url'] as String? ?? item['commercial_register_url'] as String? ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorderMint),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الهيدر والبيانات الأساسية
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: isDoctor ? AdminColors.primaryDark.withValues(alpha: 0.1) : AdminColors.accentMint.withValues(alpha: 0.15),
                      child: Icon(
                        isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded,
                        color: isDoctor ? AdminColors.primaryDark : AdminColors.accentMint,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              fullName,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16, color: AdminColors.textPrimary),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDoctor ? AdminColors.primaryDark.withValues(alpha: 0.1) : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isDoctor ? 'طبيب 🩺' : 'صيدلية 💊',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDoctor ? AdminColors.primaryDark : Colors.teal.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$specialty • $governorate',
                          style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),

                // تفاصيل التواصل
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_iphone_rounded, size: 16, color: AdminColors.primaryDark),
                      const SizedBox(width: 6),
                      Text(phone, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),

            if (bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('📝 النبذة / العنوان: $bio', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade800)),
              ),
            ],

            if (status == 'REJECTED' && rejectionReason != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('سبب الرفض: $rejectionReason', style: GoogleFonts.cairo(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // معرض صور المستندات والبطاقات (KYC Document Previews)
            Text('المستندات ووثائق الهوية المرفقة (اضغط للتكبير والفحص):', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
            const SizedBox(height: 10),

            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                if (frontUrl.isNotEmpty)
                  _buildDocThumbnail(frontUrl, 'بطاقة الرقم القومي (الوجه الأمامي)'),
                if (backUrl.isNotEmpty)
                  _buildDocThumbnail(backUrl, 'بطاقة الرقم القومي (الوجه الخلفي)'),
                if (syndicateUrl.isNotEmpty)
                  _buildDocThumbnail(syndicateUrl, 'كارنيه النقابة الساري'),
                if (licenseUrl.isNotEmpty)
                  _buildDocThumbnail(licenseUrl, isDoctor ? 'تصريح مزاولة المهنة' : 'السجل التجاري والبطاقة الضريبية'),
                if (frontUrl.isEmpty && backUrl.isEmpty && syndicateUrl.isEmpty && licenseUrl.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('⚠️ لم يتم إرفاق صور مستندات ورقية مع هذا الطلب', style: GoogleFonts.cairo(fontSize: 12, color: Colors.amber.shade900)),
                  ),
              ],
            ),

            if (status == 'PENDING') ...[
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // أزرار اتخاذ القرار السريعة (Approve / Reject Action Buttons)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.emergency,
                      side: const BorderSide(color: AdminColors.emergency),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    label: Text('رفض الطلب ❌', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => _showRejectDialog(item),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.verified_user_rounded, size: 18),
                    label: Text('اعتماد وتحديد فترة الاشتراك 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => _showApproveDurationDialog(item),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocThumbnail(String url, String title) {
    return FutureBuilder<String>(
      future: _resolveImageUrlAsync(url),
      builder: (context, snapshot) {
        final resolvedUrl = snapshot.data ?? _resolveImageUrl(url);
        return InkWell(
          onTap: () => _showFullImage(url, title),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 140,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (resolvedUrl.isNotEmpty)
                  Image.network(
                    resolvedUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      color: Colors.teal.shade50,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.file_present_rounded, color: AdminColors.primaryDark, size: 28),
                          const SizedBox(height: 4),
                          Text('مستند مرفق 📄', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                          Text('(اضغط للفحص)', style: GoogleFonts.cairo(fontSize: 8.5, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  )
                else
                  const Center(
                    child: AdminShimmerBox(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: 10,
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    color: Colors.black.withValues(alpha: 0.65),
                    child: Text(
                      title,
                      style: GoogleFonts.cairo(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
