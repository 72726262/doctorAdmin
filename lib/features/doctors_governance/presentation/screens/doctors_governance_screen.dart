import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

class DoctorsGovernanceScreen extends StatefulWidget {
  const DoctorsGovernanceScreen({super.key});

  @override
  State<DoctorsGovernanceScreen> createState() => _DoctorsGovernanceScreenState();
}

class _DoctorsGovernanceScreenState extends State<DoctorsGovernanceScreen> {
  final _client = AdminSupabaseConfig.client;
  final _realtimeManager = AdminRealtimeManager();

  static List<Map<String, dynamic>>? _cachedDoctors;

  bool _isLoading = true;
  List<Map<String, dynamic>> _doctors = [];
  String _searchQuery = '';
  String _governorateFilter = 'الكل';
  int _selectedStatusTabIndex = 0; // 0: الكل, 1: ساري, 2: ينتهي قريباً, 3: منتهي, 4: مجمد

  @override
  void initState() {
    super.initState();
    if (_cachedDoctors != null && _cachedDoctors!.isNotEmpty) {
      _doctors = _cachedDoctors!;
      _isLoading = false;
    }
    _fetchDoctors(silent: _cachedDoctors != null);
    _realtimeManager.addPartnerListener(_onRealtimePartner);
  }

  void _onRealtimePartner() {
    if (mounted) _fetchDoctors(silent: true);
  }

  @override
  void dispose() {
    _realtimeManager.removePartnerListener(_onRealtimePartner);
    super.dispose();
  }

  Future<void> _fetchDoctors({bool silent = false}) async {
    if (!silent && _doctors.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await _client.from('doctors').select('''
        id,
        specialty,
        bio,
        rating_avg,
        rating_count,
        subscription_status,
        subscription_expires_at,
        grace_period_ends_at,
        profiles (
          id,
          full_name,
          phone,
          governorate,
          avatar_url,
          is_approved
        ),
        branches (
          id,
          name,
          governorate,
          address_text,
          max_daily_capacity,
          is_queue_active,
          is_active,
          is_main
        )
      ''').order('rating_avg', ascending: false);

      if (mounted) {
        final list = List<Map<String, dynamic>>.from(res as List);
        setState(() {
          _doctors = list;
          _cachedDoctors = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDoctorApproval(String doctorId, bool currentStatus) async {
    try {
      await _client.rpc('admin_toggle_entity_approval', params: {
        'p_id': doctorId,
        'p_is_approved': !currentStatus,
      });

      await _client.from('profiles').update({'is_approved': !currentStatus}).eq('id', doctorId);
      await _client.from('doctors').update({
        'subscription_status': !currentStatus ? 'ACTIVE' : 'SUSPENDED'
      }).eq('id', doctorId);

      await _fetchDoctors(silent: true);

      AdminAuditService.log(
        actionType: !currentStatus ? 'تفعيل حساب طبيب' : 'تجميد حساب طبيب',
        targetType: 'DOCTOR',
        targetId: doctorId,
        targetName: 'طبيب $doctorId',
        details: {'is_approved': !currentStatus},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? '🟢 تم تفعيل واعتماد حساب الطبيب بنجاح' : '⏸️ تم تجميد وإيقاف حساب الطبيب بنجاح'),
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

  /// حساب وتحليل حالة وتاريخ انتهاء اشتراك الطبيب بدقة
  Map<String, dynamic> _getSubscriptionInfo(Map<String, dynamic> doc) {
    final status = (doc['subscription_status'] as String? ?? 'INACTIVE').toUpperCase();
    final expiresAtStr = doc['subscription_expires_at'] as String?;

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

  /// تمديد اشتراك الطبيب مع توثيق العملية فوراً في جدول الفواتير التاريخي
  Future<void> _extendSubscription(String doctorId, int days, {DateTime? exactExpiryDate, String? notes}) async {
    try {
      final currentDoc = _doctors.firstWhere(
        (d) => d['id'] == doctorId,
        orElse: () => {'subscription_expires_at': null},
      );
      final currentExpiryStr = currentDoc['subscription_expires_at'] as String?;
      DateTime startDate = DateTime.now();

      if (currentExpiryStr != null) {
        final parsed = DateTime.tryParse(currentExpiryStr)?.toLocal();
        if (parsed != null && parsed.isAfter(DateTime.now())) {
          startDate = parsed;
        }
      }
      final newExpiry = exactExpiryDate ?? startDate.add(Duration(days: days));

      // 1. تسجيل العملية في جدول subscription_requests كاشتراك معتمد وتمديد إداري
      final monthsCount = (days / 30).round() == 0 ? 1 : (days / 30).round();
      final adminNote = notes?.trim().isNotEmpty == true
          ? notes!.trim()
          : 'تمديد إداري استثنائي مباشر ($days يوم)';

      await _client.from('subscription_requests').insert({
        'user_id': doctorId,
        'role': 'DOCTOR',
        'plan_name': 'باقة العيادات الاحترافية',
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

      // 2. تحديث بيانات الطبيب وتاريخ الانتهاء وفترة السماح
      await _client.from('doctors').update({
        'subscription_status': 'ACTIVE',
        'subscription_expires_at': newExpiry.toIso8601String(),
        'grace_period_ends_at': newExpiry.add(const Duration(days: 2)).toIso8601String(),
      }).eq('id', doctorId);

      await _client.from('profiles').update({'is_approved': true}).eq('id', doctorId);

      AdminAuditService.log(
        actionType: 'تمديد اشتراك طبيب',
        targetType: 'DOCTOR',
        targetId: doctorId,
        targetName: 'طبيب $doctorId',
        details: {
          'days': days,
          'start_date': startDate.toIso8601String(),
          'end_date': newExpiry.toIso8601String(),
          'notes': adminNote,
        },
      );

      await _fetchDoctors(silent: true);

      if (mounted) {
        final formattedNewExpiry = intl.DateFormat('yyyy/MM/dd').format(newExpiry);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 تم تمديد اشتراك الطبيب لـ $days يوماً بنجاح حتى ($formattedNewExpiry)!'),
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

  /// نافذة منبثقة لتعديل تقييم الطبيب بالمنظومة
  void _showEditDoctorRatingDialog(Map<String, dynamic> doc) {
    final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
    final doctorName = profile['full_name'] ?? 'طبيب';
    final doctorSpec = doc['specialty'] ?? 'تخصص عام';
    final doctorGov = profile['governorate'] ?? 'مصر';
    final currentRating = ((doc['rating_avg'] as num?)?.toDouble() ?? 5.0);
    final currentCount = ((doc['rating_count'] as num?)?.toInt() ?? 50);

    double tempRating = currentRating;
    int tempCount = currentCount;
    final countController = TextEditingController(text: tempCount.toString());
    final ratingController = TextEditingController(text: tempRating.toStringAsFixed(1));
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                width: 600,
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
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تعديل تقييم الطبيب ⭐',
                                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                                  ),
                                  Text(
                                    'يؤثر هذا التقييم على صدارة الطبيب في "الأطباء الموصى بهم"',
                                    style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                    radius: 22,
                                    backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                    backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                                        ? NetworkImage(profile['avatar_url'])
                                        : null,
                                    child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                                        ? const Icon(Icons.person, color: AdminColors.primaryDark)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(doctorName, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w900)),
                                        Text('$doctorSpec • 📍 $doctorGov', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                        const SizedBox(width: 3),
                                        Text('${tempRating.toStringAsFixed(1)} ($tempCount)', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('أزرار سريعة للتقييم:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [5.0, 4.9, 4.8, 4.7, 4.5, 4.0].map((val) {
                                final isSel = (tempRating - val).abs() < 0.05;
                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      tempRating = val;
                                      ratingController.text = val.toStringAsFixed(1);
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isSel ? Colors.amber.shade100 : AdminColors.backgroundCanvas,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isSel ? Colors.amber.shade700 : AdminColors.cardBorder),
                                    ),
                                    child: Text(
                                      '⭐ ${val.toStringAsFixed(1)}',
                                      style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: isSel ? FontWeight.w900 : FontWeight.w600, color: isSel ? Colors.amber.shade900 : AdminColors.textPrimary),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            Text('الضبط الدقيق (${tempRating.toStringAsFixed(1)} ⭐):', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.amber,
                                thumbColor: Colors.amber.shade700,
                                overlayColor: Colors.amber.withValues(alpha: 0.2),
                                inactiveTrackColor: Colors.amber.withValues(alpha: 0.2),
                              ),
                              child: Slider(
                                value: tempRating.clamp(1.0, 5.0),
                                min: 1.0,
                                max: 5.0,
                                divisions: 40,
                                label: '${tempRating.toStringAsFixed(1)} ⭐',
                                onChanged: (newVal) {
                                  setModalState(() {
                                    tempRating = double.parse(newVal.toStringAsFixed(1));
                                    ratingController.text = tempRating.toStringAsFixed(1);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('التقييم الرقمي:', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: ratingController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onChanged: (v) {
                                          final parsed = double.tryParse(v);
                                          if (parsed != null && parsed >= 1.0 && parsed <= 5.0) {
                                            setModalState(() => tempRating = parsed);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('عدد المراجعات:', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: countController,
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(Icons.people_alt_rounded, color: AdminColors.primaryDark, size: 20),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onChanged: (v) {
                                          final parsed = int.tryParse(v);
                                          if (parsed != null && parsed >= 0) {
                                            setModalState(() => tempCount = parsed);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AdminColors.cardBorder)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                            child: Text('إلغاء', style: GoogleFonts.cairo(color: AdminColors.textSecondary)),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: isSaving
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.save_rounded, size: 16),
                            label: Text(
                              isSaving ? 'جارٍ الحفظ...' : 'حفظ التقييم فوراً 💾',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    final navigator = Navigator.of(dialogCtx);
                                    setModalState(() => isSaving = true);
                                    try {
                                      final finalRating = double.parse(tempRating.toStringAsFixed(2));
                                      final finalCount = tempCount;

                                      await _client.rpc('admin_update_doctor_rating', params: {
                                        'p_doctor_id': doc['id'],
                                        'p_rating_avg': finalRating,
                                        'p_rating_count': finalCount,
                                      });

                                      await AdminAuditService.log(
                                        actionType: 'UPDATE_DOCTOR_RATING',
                                        targetType: 'DOCTOR',
                                        targetName: doctorName,
                                        targetId: doc['id'] as String?,
                                        details: {
                                          'doctor_id': doc['id'],
                                          'doctor_name': doctorName,
                                          'rating': finalRating,
                                          'count': finalCount,
                                        },
                                      );

                                      if (mounted) {
                                        setState(() {
                                          doc['rating_avg'] = finalRating;
                                          doc['rating_count'] = finalCount;
                                        });
                                      }

                                      navigator.pop();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('تم تحديث تقييم $doctorName إلى $finalRating ⭐ بنجاح', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                                          backgroundColor: AdminColors.success,
                                        ),
                                      );
                                      _fetchDoctors(silent: true);
                                    } catch (e) {
                                      setModalState(() => isSaving = false);
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency),
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

  /// نافذة منبثقة لتعديل بيانات وحساب الطبيب بالكامل (استبدال الطبيب / نقل ملكية العيادة)
  void _showEditDoctorAccountDialog(Map<String, dynamic> doc) {
    final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
    final doctorId = doc['id'] as String;
    final initialName = (profile['full_name'] as String?) ?? '';
    final initialPhone = (profile['phone'] as String?) ?? '';
    final initialSpecialty = (doc['specialty'] as String?) ?? '';
    final initialGov = (profile['governorate'] as String?) ?? 'القاهرة';
    final initialBio = (doc['bio'] as String?) ?? '';

    final nameController = TextEditingController(text: initialName);
    final phoneController = TextEditingController(text: initialPhone);
    final specialtyController = TextEditingController(text: initialSpecialty);
    final bioController = TextEditingController(text: initialBio);
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
              _client.rpc('admin_get_account_security_info', params: {'p_user_id': doctorId}).then((res) {
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
                                child: const Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تعديل بيانات وحساب الطبيب (استبدال / نقل ملكية) 🩺',
                                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                                  ),
                                  Text(
                                    'تحديث الهوية، الهاتف، التخصص، أو استبدال الطبيب عند انتقال العيادة',
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
                                        '💡 ملحوظة نقل العيادة والاستبدال: في حال تسليم العيادة لطبيب بديل أو شريك جديد، يمكنك تعديل الاسم، رقم الهاتف، والتخصص وتعيين كلمة مرور جديدة فوراً. جميع فروع العيادة، الإعدادات، وقوائم الانتظار ستظل محفوظة ومرتبطة بحساب العيادة دون أي انقطاع.',
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

                              // Section: Personal & Professional Data
                              Text(
                                'البيانات الشخصية والمهنية',
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
                                        labelText: 'اسم الطبيب بالكامل *',
                                        labelStyle: GoogleFonts.cairo(fontSize: 12),
                                        prefixIcon: const Icon(Icons.person_rounded, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم الطبيب مطلوب' : null,
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

                              // Specialty & Governorate Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: specialtyController,
                                      style: GoogleFonts.cairo(fontSize: 13),
                                      decoration: InputDecoration(
                                        labelText: 'التخصص الطبي',
                                        labelStyle: GoogleFonts.cairo(fontSize: 12),
                                        prefixIcon: const Icon(Icons.medical_services_rounded, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
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
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Bio
                              TextFormField(
                                controller: bioController,
                                maxLines: 2,
                                style: GoogleFonts.cairo(fontSize: 12.5),
                                decoration: InputDecoration(
                                  labelText: 'النبذة والخبرات المهنية',
                                  labelStyle: GoogleFonts.cairo(fontSize: 12),
                                  alignLabelWithHint: true,
                                  prefixIcon: const Icon(Icons.description_rounded, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Section: Security & Login Credentials
                              Row(
                                children: [
                                  const Icon(Icons.lock_person_rounded, color: AdminColors.primaryDark, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'بيانات تسجيل الدخول والأمان (حساب العيادة)',
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
                                        helperText: 'يستخدمه الطبيب لتسجيل الدخول بالتطبيق',
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
                                      final finalSpec = specialtyController.text.trim();
                                      final finalBio = bioController.text.trim();
                                      final finalEmail = emailController.text.trim().isEmpty ? null : emailController.text.trim();
                                      final finalPass = passwordController.text.trim().isEmpty ? null : passwordController.text.trim();

                                      final rpcRes = await _client.rpc('admin_update_doctor_account', params: {
                                        'p_doctor_id': doctorId,
                                        'p_full_name': finalName,
                                        'p_phone': finalPhone,
                                        'p_specialty': finalSpec,
                                        'p_governorate': selectedGov,
                                        'p_bio': finalBio,
                                        'p_email': finalEmail,
                                        'p_new_password': finalPass,
                                      });

                                      if (rpcRes != null && rpcRes is Map && rpcRes['success'] == false) {
                                        throw rpcRes['message'] ?? 'فشل تحديث البيانات';
                                      }

                                      await AdminAuditService.log(
                                        actionType: 'UPDATE_DOCTOR_ACCOUNT',
                                        targetType: 'DOCTOR',
                                        targetName: finalName,
                                        targetId: doctorId,
                                        details: {
                                          'doctor_id': doctorId,
                                          'full_name': finalName,
                                          'phone': finalPhone,
                                          'specialty': finalSpec,
                                          'governorate': selectedGov,
                                          'password_changed': finalPass != null,
                                        },
                                      );

                                      navigator.pop();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('🟢 تم تحديث بيانات وحساب $finalName بنجاح', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                                          backgroundColor: AdminColors.success,
                                        ),
                                      );
                                      _fetchDoctors(silent: true);
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

  /// نافذة منبثقة لعرض سجل الاشتراكات التاريخي الزمني للطبيب (من تاريخ كذا إلى كذا بالتفصيل)
  void _showDoctorSubscriptionHistoryDialog(Map<String, dynamic> doc) {
    final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
    final doctorName = profile['full_name'] ?? 'طبيب المنظومة';
    final doctorId = doc['id'] as String;
    final subInfo = _getSubscriptionInfo(doc);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 680),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الهيدر
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AdminColors.primaryDark.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.history_edu_rounded, color: AdminColors.primaryDark, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'سجل فترات الاشتراكات والتمديدات 💳',
                            style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                          ),
                          Text(
                            'الطبيب: $doctorName (${doc['specialty'] ?? 'تخصص عام'})',
                            style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AdminColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // كارت ملخص الاشتراك الساري الحالي
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AdminColors.primaryDark.withValues(alpha: 0.08), AdminColors.accentMintLight.withValues(alpha: 0.4)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AdminColors.cardBorderMint),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الاشتراك الساري حالياً:', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text(
                          'ينتهي في: ${subInfo['fullExpiryText']}',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13, color: AdminColors.primaryDark),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: subInfo['badgeColor'],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: subInfo['borderColor']),
                      ),
                      child: Text(
                        subInfo['label'],
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 11.5, color: subInfo['textColor']),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'سجل الفترات السابقة (من تاريخ كذا إلى كذا):',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textPrimary),
              ),
              const SizedBox(height: 8),

              // قائمة الفترات الزمنية
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _client
                      .from('subscription_requests')
                      .select('''
                        id,
                        amount,
                        amount_paid,
                        months,
                        payment_method,
                        receipt_image_url,
                        status,
                        start_date,
                        end_date,
                        notes,
                        rejection_reason,
                        created_at,
                        reviewed_at
                      ''')
                      .eq('user_id', doctorId)
                      .order('created_at', ascending: false),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: AdminTableSkeleton(rows: 4));
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('خطأ أثناء تحميل السجل: ${snapshot.error}', style: GoogleFonts.cairo(color: AdminColors.emergency)),
                      );
                    }

                    final records = snapshot.data ?? [];
                    if (records.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.receipt_long_outlined, size: 48, color: AdminColors.textSecondary),
                              const SizedBox(height: 8),
                              Text('لا توجد اشتراكات أو فواتير سابقة مسجلة لهذا الطبيب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text('أي تجديد أو تمديد إداري سيتم تسجيله هنا بالتفصيل من تاريخ كذا إلى كذا', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final rec = records[index];
                        final status = (rec['status'] as String? ?? 'PENDING').toUpperCase();
                        final isApproved = status == 'APPROVED';
                        final isRejected = status == 'REJECTED';
                        final months = rec['months'] ?? 1;
                        final amount = rec['amount'] ?? rec['amount_paid'] ?? 0;
                        final method = rec['payment_method'] ?? 'إلكتروني';
                        final receiptUrl = rec['receipt_image_url'] as String?;
                        final notes = rec['notes'] as String?;
                        final rejectReason = rec['rejection_reason'] as String?;

                        // استخراج تواريخ الفترة
                        String periodText = '';
                        final startStr = rec['start_date'] as String?;
                        final endStr = rec['end_date'] as String?;
                        final createdStr = rec['created_at'] as String?;

                        if (startStr != null && endStr != null) {
                          final sDate = DateTime.tryParse(startStr)?.toLocal();
                          final eDate = DateTime.tryParse(endStr)?.toLocal();
                          if (sDate != null && eDate != null) {
                            periodText = 'من: ${intl.DateFormat('yyyy/MM/dd').format(sDate)}  إلى: ${intl.DateFormat('yyyy/MM/dd').format(eDate)}';
                          }
                        } else if (createdStr != null) {
                          final cDate = DateTime.tryParse(createdStr)?.toLocal();
                          if (cDate != null) {
                            final eDate = cDate.add(Duration(days: (months as int) * 30));
                            periodText = 'من: ${intl.DateFormat('yyyy/MM/dd').format(cDate)}  إلى: ${intl.DateFormat('yyyy/MM/dd').format(eDate)}';
                          }
                        }

                        final reviewedStr = rec['reviewed_at'] as String?;
                        String reviewedDateFormatted = '';
                        if (reviewedStr != null) {
                          final rDate = DateTime.tryParse(reviewedStr)?.toLocal();
                          if (rDate != null) {
                            reviewedDateFormatted = intl.DateFormat('yyyy/MM/dd - hh:mm a').format(rDate);
                          }
                        }

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isApproved ? AdminColors.cardBorderMint : (isRejected ? Colors.red.shade200 : Colors.amber.shade200),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    isApproved ? Icons.check_circle_rounded : (isRejected ? Icons.cancel_rounded : Icons.pending_rounded),
                                    color: isApproved ? AdminColors.success : (isRejected ? AdminColors.emergency : Colors.amber.shade800),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'فترة الاشتراك: $periodText',
                                      style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13, color: AdminColors.textPrimary),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isApproved ? AdminColors.success.withValues(alpha: 0.1) : (isRejected ? Colors.red.shade50 : Colors.amber.shade50),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isApproved ? 'معتمد ومفعل ✅' : (isRejected ? 'مرفوض ❌' : 'قيد المراجعة ⏳'),
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isApproved ? AdminColors.success : (isRejected ? AdminColors.emergency : Colors.amber.shade900),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'المدة: $months شهر • القيمة: $amount ج.م • الوسيلة: $method',
                                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary, fontWeight: FontWeight.w600),
                                  ),
                                  if (reviewedDateFormatted.isNotEmpty) ...[
                                    const Spacer(),
                                    Text(
                                      'تاريخ الاعتماد: $reviewedDateFormatted',
                                      style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ],
                              ),
                              if (notes != null && notes.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(color: AdminColors.backgroundCanvas, borderRadius: BorderRadius.circular(6)),
                                  child: Text('ملاحظات: $notes', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textPrimary)),
                                ),
                              ],
                              if (isRejected && rejectReason != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                                  child: Text('سبب الرفض: $rejectReason', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.emergency, fontWeight: FontWeight.bold)),
                                ),
                              ],
                              if (receiptUrl != null && receiptUrl.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                                    icon: const Icon(Icons.receipt_rounded, size: 16, color: AdminColors.primaryDark),
                                    label: Text('معاينة صورة الإيصال 🖼️', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (c) => Dialog(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AppBar(title: Text('إيصال السداد', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold)), automaticallyImplyLeading: false, actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c))]),
                                              Image.network(receiptUrl, fit: BoxFit.contain, height: 500),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.add_card_rounded, size: 18),
                    label: Text('تمديد اشتراك لهذا الطبيب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showExtendSubscriptionDialog(doctorId, doctorName);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// تفعيل أو تعطيل فرع عيادة محدد للطبيب مع إلزامه بالاشتراك الموحد للطبيب
  Future<void> _toggleBranchActivation({
    required Map<String, dynamic> branch,
    required Map<String, dynamic> doc,
    required Map<String, dynamic> subInfo,
    required bool isActive,
    required StateSetter setModalState,
  }) async {
    final branchId = branch['id']?.toString();
    final branchName = branch['name'] ?? 'العيادة';
    if (branchId == null) return;

    try {
      await _client.rpc('admin_toggle_branch_active', params: {
        'p_branch_id': branchId,
        'p_is_active': isActive,
      });

      AdminAuditService.log(
        actionType: isActive ? 'تفعيل فرع عيادة' : 'إيقاف فرع عيادة',
        targetType: 'BRANCH',
        targetId: branchId,
        targetName: '$branchName (طبيب: ${doc['id']})',
        details: {
          'is_active': isActive,
          'doctor_subscription_expires_at': doc['subscription_expires_at'],
        },
      );

      _fetchDoctors(silent: true);

      if (mounted) {
        final expiryNotice = subInfo['fullExpiryText'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            backgroundColor: isActive ? AdminColors.success : const Color(0xFF455A64),
            content: Row(
              children: [
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isActive
                        ? '🟢 تم تفعيل عيادة ($branchName) بنجاح! وتنتهي مع الاشتراك الموحد للطبيب في ($expiryNotice)'
                        : '⏸️ تم تعطيل وإيقاف عيادة ($branchName). باقي العيادات تعمل حتى موعد الاشتراك الموحد ($expiryNotice)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setModalState(() {
          branch['is_active'] = !isActive;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحديث حالة العيادة: $e'),
            backgroundColor: AdminColors.emergency,
          ),
        );
      }
    }
  }

  void _showDoctorDetailsModal(Map<String, dynamic> doc) {
    final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
    final rawBranches = (doc['branches'] as List?) ?? [];
    final branches = rawBranches.map((b) => Map<String, dynamic>.from(b as Map)).toList();
    final isApproved = (profile['is_approved'] == true) && (doc['subscription_status'] != 'SUSPENDED' && doc['subscription_status'] != 'FROZEN');
    final subInfo = _getSubscriptionInfo(doc);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 700,
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modal Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                        backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                            ? NetworkImage(profile['avatar_url'])
                            : null,
                        child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                            ? const Icon(Icons.person, color: AdminColors.primaryDark, size: 30)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  profile['full_name'] ?? 'طبيب المنظومة',
                                  style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isApproved ? AdminColors.accentMintLight : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isApproved ? 'معتمد 🟢' : 'مجمد / موقوف 🔴',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      color: isApproved ? AdminColors.success : AdminColors.emergency,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              doc['specialty'] ?? 'تخصص عام',
                              style: GoogleFonts.cairo(color: AdminColors.accentCyan, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '📞 ${profile['phone'] ?? 'غير متوفر'} | 📍 ${profile['governorate'] ?? 'مصر'}',
                              style: GoogleFonts.cairo(color: AdminColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Subscription Details Box (مع تاريخ الانتهاء والعداد الدقيق)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AdminColors.backgroundCanvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.card_membership_rounded, color: AdminColors.primaryDark, size: 20),
                                const SizedBox(width: 6),
                                Text('حالة اشتراك العيادة بالمنظومة:', style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: subInfo['badgeColor'],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: subInfo['borderColor']),
                              ),
                              child: Text(
                                subInfo['label'],
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: subInfo['textColor'],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'موعد انتهاء الاشتراك الدقيق: ${subInfo['fullExpiryText']}',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: AdminColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.08),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.history_rounded, size: 16, color: AdminColors.primaryDark),
                            label: Text('عرض سجل الاشتراكات السابقة بالتفصيل (من وإلى) 📜', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showDoctorSubscriptionHistoryDialog(doc);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // تقييم الطبيب وحوكمة التوصيات ⭐
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تقييم الطبيب بالمنظومة ⭐',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                                ),
                                Text(
                                  'المتوسط: ${((doc['rating_avg'] as num?)?.toDouble() ?? 5.0).toStringAsFixed(1)} من 5.0 • إجمالي المراجعات: ${doc['rating_count'] ?? 0}',
                                  style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textPrimary),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AdminColors.primaryDark,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.manage_accounts_rounded, size: 16),
                              label: Text('تعديل البيانات والحساب ⚙️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showEditDoctorAccountDialog(doc);
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.edit_rounded, size: 15),
                              label: Text('تعديل التقييم ⭐', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showEditDoctorRatingDialog(doc);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bio
                  Text('النبذة والخبرات:', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    doc['bio'] != null && doc['bio'] != '' ? doc['bio'] : 'لا توجد نبذة مسجلة',
                    style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                  ),
                  const SizedBox(height: 18),

                  // Branches List Header & Counter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'فروع العيادات المسجلة (${branches.length} فروع):',
                        style: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AdminColors.primaryDark.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'المفعلة: ${branches.where((b) => b['is_active'] as bool? ?? true).length} من ${branches.length}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AdminColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Unified Expiry Governance Notice Box
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'قاعدة الاشتراك الموحد لكافة عيادات الطبيب ⚖️',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF14532D),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'كافة فروع وعيادات الطبيب مرتبطة بالاشتراك العام الموحد المنتهي في (${subInfo['fullExpiryText']}). يمكنك تفعيل أو إيقاف أي عيادة بالتبديل أدناه، وأي عيادة يتم تفعيلها لاحقاً ستنتهي حتماً في نفس موعد الاشتراك دون أي زيادة.',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: const Color(0xFF166534),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (branches.isEmpty)
                    Text('لا توجد فروع مسجلة لهذا الطبيب حالياً', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary))
                  else
                    ...branches.map((b) {
                      final isActive = (b['is_active'] as bool? ?? true);
                      final isMain = (b['is_main'] == true);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFFF9FDFB) : AdminColors.backgroundCanvas,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive ? AdminColors.cardBorderMint : AdminColors.cardBorder,
                            width: isActive ? 1.5 : 1,
                          ),
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
                                      Text(
                                        b['name'] ?? 'الفرع',
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: isActive ? AdminColors.textPrimary : AdminColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isMain) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                                'المقر الرئيسي ⭐️',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(0xFFB78103),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isActive ? AdminColors.accentMintLight : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          isActive ? '🟢 نشطة وتستقبل الحجوزات' : '⚪ معطلة بالاشتراك',
                                          style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isActive ? AdminColors.primaryDark : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '📍 ${b['governorate']} - ${b['address_text']}',
                                    style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'السعة: ${b['max_daily_capacity'] ?? 30} كشف/يوم | الطابور: ${b['is_queue_active'] == true ? 'نشط 🟢' : 'متوقف ⏸️'}',
                                    style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Switch Control with informative status
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isActive ? 'مفعلة' : 'معطلة',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? AdminColors.primaryDark : Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Switch(
                                      value: isActive,
                                      activeThumbColor: AdminColors.primaryDark,
                                      activeTrackColor: AdminColors.accentMint,
                                      onChanged: (newVal) {
                                        setModalState(() {
                                          b['is_active'] = newVal;
                                        });
                                        _toggleBranchActivation(
                                          branch: b,
                                          doc: doc,
                                          subInfo: subInfo,
                                          isActive: newVal,
                                          setModalState: setModalState,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                Text(
                                  isActive ? 'تنتهي: ${subInfo['expiryText']}' : 'انقر لتفعيل العيادة',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    color: isActive ? AdminColors.accentCyan : AdminColors.textSecondary,
                                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  // Actions Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('إغلاق', style: GoogleFonts.cairo(color: AdminColors.textSecondary)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminColors.accentCyan,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_card_rounded, size: 18),
                        label: Text('تمديد الاشتراك', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showExtendSubscriptionDialog(doc['id'], profile['full_name'] ?? 'الطبيب');
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isApproved ? AdminColors.warning : AdminColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(isApproved ? Icons.pause_circle_rounded : Icons.check_circle_rounded, size: 18),
                        label: Text(isApproved ? 'تجميد الحساب' : 'تفعيل الحساب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _toggleDoctorApproval(doc['id'], isApproved);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showExtendSubscriptionDialog(String docId, String doctorName) {
    final currentDoc = _doctors.firstWhere(
      (d) => d['id'] == docId,
      orElse: () => {'subscription_expires_at': null},
    );
    final currentExpiryStr = currentDoc['subscription_expires_at'] as String?;
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
                    'تمديد وتخصيص اشتراك: $doctorName 💳',
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
                                'تاريخ انتهاء الاشتراك الجديد المحدد:',
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
                    docId,
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

  @override
  Widget build(BuildContext context) {
    int activeCount = 0;
    int expiringSoonCount = 0;
    int expiredCount = 0;
    int frozenCount = 0;

    for (final d in _doctors) {
      final profile = d['profiles'] as Map<String, dynamic>? ?? {};
      final isApproved = (profile['is_approved'] == true) &&
          (d['subscription_status'] != 'SUSPENDED' && d['subscription_status'] != 'FROZEN');
      final subInfo = _getSubscriptionInfo(d);
      if (!isApproved) {
        frozenCount++;
      } else if (subInfo['status'] == 'ACTIVE') {
        activeCount++;
      } else if (subInfo['isExpiringSoon'] == true) {
        expiringSoonCount++;
      } else if (subInfo['isExpired'] == true) {
        expiredCount++;
      }
    }

    final filtered = _doctors.where((d) {
      final profile = d['profiles'] as Map<String, dynamic>? ?? {};
      final name = profile['full_name']?.toString() ?? '';
      final specialty = d['specialty']?.toString() ?? '';
      final gov = profile['governorate']?.toString() ?? '';
      final isApproved = (profile['is_approved'] == true) &&
          (d['subscription_status'] != 'SUSPENDED' && d['subscription_status'] != 'FROZEN');
      final subInfo = _getSubscriptionInfo(d);

      final matchGov = _governorateFilter == 'الكل' || gov == _governorateFilter;

      bool matchStatus = true;
      if (_selectedStatusTabIndex == 1) {
        matchStatus = isApproved && subInfo['status'] == 'ACTIVE';
      } else if (_selectedStatusTabIndex == 2) {
        matchStatus = isApproved && subInfo['isExpiringSoon'] == true;
      } else if (_selectedStatusTabIndex == 3) {
        matchStatus = isApproved && subInfo['isExpired'] == true;
      } else if (_selectedStatusTabIndex == 4) {
        matchStatus = !isApproved;
      }

      final matchSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery) ||
          specialty.contains(_searchQuery) ||
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
                        child: const Icon(Icons.medical_services_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'مركز حوكمة وإدارة الأطباء والعيادات',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'التحكم الكامل في الأطباء المسجلين، فحص الفروع، متابعة تاريخ انتهاء الاشتراكات بدقة، وسجل الفترات السابقة',
                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث البيانات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _fetchDoctors(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // كروت المؤشرات العلوية (KPI Metric Summary Cards)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'إجمالي الأطباء',
                  count: _doctors.length,
                  subtitle: 'مسجلين في كافة المحافظات',
                  icon: Icons.people_alt_rounded,
                  color: AdminColors.primaryDark,
                  bgColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'اشتراكات سارية 🟢',
                  count: activeCount,
                  subtitle: 'حسابات نشطة وعيادات مفعلة',
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'توشك على الانتهاء ⚠️',
                  count: expiringSoonCount,
                  subtitle: 'متبقي 5 أيام أو أقل للتجديد',
                  icon: Icons.hourglass_bottom_rounded,
                  color: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFFFBEB),
                  borderColor: const Color(0xFFFDE68A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'منتهية ومجمدة 🔴',
                  count: expiredCount + frozenCount,
                  subtitle: 'تتطلب سداد الرسوم أو التفعيل',
                  icon: Icons.pause_circle_filled_rounded,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFECACA),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Search & Filters Row
          Row(
            children: [
              // Search Input
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
                      hintText: '🔍 بحث باسم الطبيب، التخصص، أو المحافظة...',
                      hintStyle: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.primaryDark),
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
              AdminTabItem(label: 'الكل', icon: Icons.people_alt_rounded, count: _doctors.length),
              AdminTabItem(label: 'اشتراك ساري 🟢', icon: Icons.check_circle_rounded, count: activeCount, badgeColor: const Color(0xFF10B981)),
              AdminTabItem(label: 'ينتهي قريباً ⚠️', icon: Icons.hourglass_bottom_rounded, count: expiringSoonCount, badgeColor: const Color(0xFFF59E0B)),
              AdminTabItem(label: 'منتهي الصلاحية 🔴', icon: Icons.error_outline_rounded, count: expiredCount, badgeColor: const Color(0xFFEF4444)),
              AdminTabItem(label: 'مجمد / موقوف ⏸️', icon: Icons.pause_circle_filled_rounded, count: frozenCount, badgeColor: const Color(0xFF64748B)),
            ],
            selectedIndex: _selectedStatusTabIndex,
            onTabSelected: (idx) => setState(() => _selectedStatusTabIndex = idx),
          ),

          const SizedBox(height: 16),

          // Doctors Table / List
          if (_isLoading && _doctors.isEmpty)
            const AdminTableSkeleton(rows: 8)
          else if (filtered.isEmpty)
            AdminEmptyStateCard(
              title: _searchQuery.isNotEmpty
                  ? 'لا يوجد أطباء مطابقين لبحث "$_searchQuery"'
                  : 'لا يوجد أطباء في هذا القسم حالياً',
              description: _searchQuery.isNotEmpty
                  ? 'تأكد من كتابة الاسم أو التخصص بشكل صحيح، أو أعد ضبط خيارات البحث.'
                  : 'جميع بيانات الأطباء والعيادات محدثة وجاهزة للمعاينة والإدارة.',
              icon: Icons.medical_services_outlined,
              onRefresh: () => _fetchDoctors(),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
                          final branches = (doc['branches'] as List?) ?? [];
                          final isApproved = (profile['is_approved'] == true) &&
                              (doc['subscription_status'] != 'SUSPENDED' && doc['subscription_status'] != 'FROZEN');
                          final subInfo = _getSubscriptionInfo(doc);

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
                                // Avatar
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                  backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                                      ? NetworkImage(profile['avatar_url'])
                                      : null,
                                  child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                                      ? const Icon(Icons.person, color: AdminColors.primaryDark)
                                      : null,
                                ),
                                const SizedBox(width: 14),

                                // Doctor Details
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            profile['full_name'] ?? 'طبيب غير مسجل',
                                            style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14, color: AdminColors.textPrimary),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isApproved ? AdminColors.accentMintLight : Colors.red.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isApproved ? 'معتمد 🟢' : 'مجمد 🔴',
                                              style: GoogleFonts.cairo(
                                                fontSize: 10.5,
                                                color: isApproved ? AdminColors.success : AdminColors.emergency,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${doc['specialty'] ?? 'تخصص عام'} • 📍 ${profile['governorate'] ?? 'مصر'} • 📞 ${profile['phone'] ?? 'بدون هاتف'}',
                                        style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                                const SizedBox(width: 3),
                                                Text(
                                                  '${((doc['rating_avg'] as num?)?.toDouble() ?? 5.0).toStringAsFixed(1)} (${doc['rating_count'] ?? 0} تقييم)',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.amber.shade900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Branches Count
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('فروع العيادة:', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                                      Text('${branches.length} فروع مسجلة', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                                    ],
                                  ),
                                ),

                                // Subscription Status & Exact Expiry Date
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('انتهاء الاشتراك:', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: subInfo['badgeColor'],
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: subInfo['borderColor']),
                                            ),
                                            child: Text(
                                              subInfo['label'],
                                              style: GoogleFonts.cairo(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: subInfo['textColor'],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            subInfo['expiryText'],
                                            style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.w700, color: AdminColors.textPrimary),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Actions
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // زر تعديل بيانات وحساب الطبيب بالكامل (استبدال / نقل ملكية)
                                    IconButton(
                                      icon: const Icon(Icons.manage_accounts_rounded, color: AdminColors.primaryDark, size: 22),
                                      tooltip: 'تعديل بيانات وحساب الطبيب (استبدال / نقل ملكية) ⚙️',
                                      onPressed: () => _showEditDoctorAccountDialog(doc),
                                    ),
                                    const SizedBox(width: 4),

                                    // زر فتح سجل الاشتراكات التاريخي الزمني مباشرة
                                    IconButton(
                                      icon: const Icon(Icons.history_edu_rounded, color: AdminColors.primaryDark, size: 22),
                                      tooltip: 'عرض سجل الاشتراكات التاريخي (من وإلى)',
                                      onPressed: () => _showDoctorSubscriptionHistoryDialog(doc),
                                    ),
                                    const SizedBox(width: 4),

                                    // زر تعديل تقييم الطبيب ⭐
                                    IconButton(
                                      icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                                      tooltip: 'تعديل تقييم الطبيب وحوكمة الموصى بهم ⭐',
                                      onPressed: () => _showEditDoctorRatingDialog(doc),
                                    ),
                                    const SizedBox(width: 4),

                                    // زر عرض الملف والفروع
                                    IconButton(
                                      icon: const Icon(Icons.visibility_rounded, color: AdminColors.textSecondary, size: 20),
                                      tooltip: 'عرض الملف الكامل وتمديد الاشتراك',
                                      onPressed: () => _showDoctorDetailsModal(doc),
                                    ),
                                    const SizedBox(width: 4),

                                    // زر التجميد والتفعيل
                                    IconButton(
                                      icon: Icon(
                                        isApproved ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                                        color: isApproved ? AdminColors.warning : AdminColors.success,
                                        size: 22,
                                      ),
                                      tooltip: isApproved ? 'تجميد الحساب' : 'تفعيل الحساب',
                                      onPressed: () => _toggleDoctorApproval(doc['id'], isApproved),
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
