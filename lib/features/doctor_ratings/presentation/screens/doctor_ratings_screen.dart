import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';
import 'package:doctor_admin/core/constants/specialties_data.dart';

/// 🌟 قسم إدارة وحوكمة تقييمات الأطباء والأطباء الموصى بهم (Doctor Ratings Governance)
/// يتيح للأدمن التحكم الكامل في تقييمات الأطباء، فرز وترتيب المتصدرين حسب المحافظة،
/// وتعديل متوسط التقييم وعدد المراجعات فورياً مع تحديث لحظي لتطبيق المريض.
class DoctorRatingsScreen extends StatefulWidget {
  const DoctorRatingsScreen({super.key});

  @override
  State<DoctorRatingsScreen> createState() => _DoctorRatingsScreenState();
}

class _DoctorRatingsScreenState extends State<DoctorRatingsScreen> {
  final _client = AdminSupabaseConfig.client;
  final _realtimeManager = AdminRealtimeManager();

  static List<Map<String, dynamic>>? _cachedDoctors;

  bool _isLoading = true;
  List<Map<String, dynamic>> _doctors = [];

  String _searchQuery = '';
  String _selectedGovernorate = 'الكل';
  String _selectedSpecialty = 'الكل';
  int _selectedRatingFilter = 0; // 0: الكل, 1: 5.0 ⭐, 2: 4.5+ ⭐, 3: 4.0+ ⭐, 4: أقل من 4.0
  int _sortBy = 0; // 0: الأعلى تقييماً أولاً, 1: الأكثر مراجعات, 2: الاسم أبجدياً

  final List<String> _egyptGovernorates = [
    'الكل',
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
    'الفيوم',
    'بني سويف',
    'المنيا',
    'أسيوط',
    'سوهاج',
    'قنا',
    'الأقصر',
    'أسوان',
    'مطروح',
    'البحر الأحمر',
    'الوادي الجديد',
    'شمال سيناء',
    'جنوب سيناء',
  ];

  @override
  void initState() {
    super.initState();
    if (_cachedDoctors != null && _cachedDoctors!.isNotEmpty) {
      _doctors = _cachedDoctors!;
      _isLoading = false;
    }
    _fetchDoctors(silent: _cachedDoctors != null);

    _realtimeManager.addPartnerListener(() {
      if (mounted) _fetchDoctors(silent: true);
    });
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
        profiles!inner(full_name, governorate, avatar_url, phone, is_approved),
        branches(id, name, governorate, is_active)
      ''').order('rating_avg', ascending: false);

      final list = List<Map<String, dynamic>>.from(res as List);
      if (mounted) {
        setState(() {
          _doctors = list;
          _cachedDoctors = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching doctors for ratings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// حساب الترتيب الداخلي للأطباء في كل محافظة لتحديد من يتصدر "الموصى بهم" للمريض
  Map<String, int> _calculateGovernorateRanks() {
    final ranks = <String, int>{};
    final Map<String, List<Map<String, dynamic>>> byGov = {};

    for (final doc in _doctors) {
      final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
      final docGov = (profile['governorate'] as String?) ?? 'غير محدد';
      byGov.putIfAbsent(docGov, () => []).add(doc);

      final branches = (doc['branches'] as List?) ?? [];
      for (final b in branches) {
        final bGov = b['governorate'] as String?;
        if (bGov != null && bGov.isNotEmpty && bGov != docGov) {
          byGov.putIfAbsent(bGov, () => []).add(doc);
        }
      }
    }

    byGov.forEach((gov, docs) {
      docs.sort((a, b) {
        final rA = (a['rating_avg'] as num?)?.toDouble() ?? 0.0;
        final rB = (b['rating_avg'] as num?)?.toDouble() ?? 0.0;
        final comp = rB.compareTo(rA);
        if (comp != 0) return comp;
        final cA = (a['rating_count'] as num?)?.toInt() ?? 0;
        final cB = (b['rating_count'] as num?)?.toInt() ?? 0;
        return cB.compareTo(cA);
      });

      for (int i = 0; i < docs.length; i++) {
        final docId = docs[i]['id'] as String;
        final key = '${docId}_$gov';
        ranks[key] = i + 1;
      }
    });

    return ranks;
  }

  List<Map<String, dynamic>> _getFilteredDoctors() {
    var list = List<Map<String, dynamic>>.from(_doctors);

    // 1. فلتر المحافظة
    if (_selectedGovernorate != 'الكل') {
      list = list.where((d) {
        final profile = d['profiles'] as Map<String, dynamic>? ?? {};
        final docGov = profile['governorate'] as String?;
        final branches = (d['branches'] as List?) ?? [];
        final hasBranchInGov = branches.any((b) => b['governorate'] == _selectedGovernorate);
        return docGov == _selectedGovernorate || hasBranchInGov;
      }).toList();
    }

    // 2. فلتر التخصص الطبي الموحد
    if (_selectedSpecialty != 'الكل') {
      list = list.where((d) {
        final spec = d['specialty'] as String? ?? '';
        return SpecialtiesData.matches(spec, _selectedSpecialty);
      }).toList();
    }

    // 2. فلتر البحث النصي
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((d) {
        final profile = d['profiles'] as Map<String, dynamic>? ?? {};
        final name = (profile['full_name'] as String? ?? '').toLowerCase();
        final phone = (profile['phone'] as String? ?? '').toLowerCase();
        final spec = (d['specialty'] as String? ?? '').toLowerCase();
        final gov = (profile['governorate'] as String? ?? '').toLowerCase();
        return name.contains(q) || phone.contains(q) || spec.contains(q) || gov.contains(q);
      }).toList();
    }

    // 3. فلتر فئة التقييم
    if (_selectedRatingFilter == 1) {
      list = list.where((d) => ((d['rating_avg'] as num?)?.toDouble() ?? 0.0) >= 4.95).toList();
    } else if (_selectedRatingFilter == 2) {
      list = list.where((d) => ((d['rating_avg'] as num?)?.toDouble() ?? 0.0) >= 4.5).toList();
    } else if (_selectedRatingFilter == 3) {
      list = list.where((d) => ((d['rating_avg'] as num?)?.toDouble() ?? 0.0) >= 4.0).toList();
    } else if (_selectedRatingFilter == 4) {
      list = list.where((d) => ((d['rating_avg'] as num?)?.toDouble() ?? 0.0) < 4.0).toList();
    }

    // 4. الترتيب
    if (_sortBy == 0) {
      // الأعلى تقييماً أولاً ثم الأكثر مراجعات
      list.sort((a, b) {
        final rA = (a['rating_avg'] as num?)?.toDouble() ?? 0.0;
        final rB = (b['rating_avg'] as num?)?.toDouble() ?? 0.0;
        final comp = rB.compareTo(rA);
        if (comp != 0) return comp;
        final cA = (a['rating_count'] as num?)?.toInt() ?? 0;
        final cB = (b['rating_count'] as num?)?.toInt() ?? 0;
        return cB.compareTo(cA);
      });
    } else if (_sortBy == 1) {
      // الأكثر مراجعات
      list.sort((a, b) {
        final cA = (a['rating_count'] as num?)?.toInt() ?? 0;
        final cB = (b['rating_count'] as num?)?.toInt() ?? 0;
        return cB.compareTo(cA);
      });
    } else if (_sortBy == 2) {
      // أبجدياً
      list.sort((a, b) {
        final nA = (a['profiles']?['full_name'] as String? ?? '');
        final nB = (b['profiles']?['full_name'] as String? ?? '');
        return nA.compareTo(nB);
      });
    }

    return list;
  }

  /// نافذة تعديل تقييم الطبيب الشاملة والذكية
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
                width: 620,
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
                    // Header Bar
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
                                    'تعديل تقييم الطبيب وحوكمة التوصيات ⭐',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'يؤثر هذا التقييم مباشرة على صدارة الطبيب في قسم "الأطباء الأعلى تقييماً"',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                    ),
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

                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Doctor Info Summary Box
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AdminColors.backgroundCanvas,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AdminColors.cardBorderMint),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                    backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                                        ? NetworkImage(profile['avatar_url'])
                                        : null,
                                    child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                                        ? const Icon(Icons.person, color: AdminColors.primaryDark, size: 28)
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          doctorName,
                                          style: GoogleFonts.cairo(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w900,
                                            color: AdminColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '$doctorSpec • 📍 $doctorGov',
                                          style: GoogleFonts.cairo(
                                            fontSize: 12,
                                            color: AdminColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${tempRating.toStringAsFixed(1)} ($tempCount)',
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Presets Row
                            Text(
                              'خيارات سريعة للتقييم:',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AdminColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildPresetChip(5.0, '⭐ 5.0 (نخبة والأعلى تقييماً)', tempRating, (val) {
                                  setModalState(() {
                                    tempRating = val;
                                    ratingController.text = val.toStringAsFixed(1);
                                  });
                                }),
                                _buildPresetChip(4.9, '⭐ 4.9 (ممتاز جداً)', tempRating, (val) {
                                  setModalState(() {
                                    tempRating = val;
                                    ratingController.text = val.toStringAsFixed(1);
                                  });
                                }),
                                _buildPresetChip(4.8, '⭐ 4.8 (ممتاز)', tempRating, (val) {
                                  setModalState(() {
                                    tempRating = val;
                                    ratingController.text = val.toStringAsFixed(1);
                                  });
                                }),
                                _buildPresetChip(4.7, '⭐ 4.7 (جيد جداً)', tempRating, (val) {
                                  setModalState(() {
                                    tempRating = val;
                                    ratingController.text = val.toStringAsFixed(1);
                                  });
                                }),
                                _buildPresetChip(4.5, '⭐ 4.5 (جيد)', tempRating, (val) {
                                  setModalState(() {
                                    tempRating = val;
                                    ratingController.text = val.toStringAsFixed(1);
                                  });
                                }),
                                _buildPresetChip(4.0, '⭐ 4.0 (مقبول)', tempRating, (val) {
                                  setModalState(() {
                                    tempRating = val;
                                    ratingController.text = val.toStringAsFixed(1);
                                  });
                                }),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Interactive Star Rating & Slider
                            Text(
                              'ضبط التقييم بدقة (${tempRating.toStringAsFixed(1)} من 5.0):',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AdminColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // 5 Interactive Stars Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (starIdx) {
                                final starVal = starIdx + 1.0;
                                final isFull = tempRating >= starVal;
                                final isHalf = tempRating >= starVal - 0.5 && tempRating < starVal;

                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      tempRating = starVal;
                                      ratingController.text = starVal.toStringAsFixed(1);
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(
                                      isFull
                                          ? Icons.star_rounded
                                          : isHalf
                                              ? Icons.star_half_rounded
                                              : Icons.star_outline_rounded,
                                      color: Colors.amber,
                                      size: 38,
                                    ),
                                  ),
                                );
                              }),
                            ),

                            const SizedBox(height: 10),

                            // Slider for exact decimal precision
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.amber,
                                thumbColor: Colors.amber.shade700,
                                overlayColor: Colors.amber.withValues(alpha: 0.2),
                                inactiveTrackColor: Colors.amber.withValues(alpha: 0.2),
                                trackHeight: 6,
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

                            const SizedBox(height: 16),

                            // Numbers Row: Rating input + Review Count input
                            Row(
                              children: [
                                // Rating average input
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'التقييم الرقمي (من 1.0 إلى 5.0):',
                                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: ratingController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(Icons.star_rounded, color: Colors.amber),
                                          hintText: '4.9',
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.amber, width: 2)),
                                        ),
                                        onChanged: (val) {
                                          final parsed = double.tryParse(val);
                                          if (parsed != null && parsed >= 1.0 && parsed <= 5.0) {
                                            setModalState(() => tempRating = parsed);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Review count input
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'عدد التقييمات المسجلة:',
                                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: countController,
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(Icons.people_alt_rounded, color: AdminColors.primaryDark),
                                          hintText: '50',
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.primaryDark, width: 2)),
                                        ),
                                        onChanged: (val) {
                                          final parsed = int.tryParse(val);
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

                            const SizedBox(height: 8),

                            // Quick count boosters
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('زيادة سريعة: ', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                                _buildCountIncrementButton('+10', () {
                                  setModalState(() {
                                    tempCount += 10;
                                    countController.text = tempCount.toString();
                                  });
                                }),
                                const SizedBox(width: 6),
                                _buildCountIncrementButton('+50', () {
                                  setModalState(() {
                                    tempCount += 50;
                                    countController.text = tempCount.toString();
                                  });
                                }),
                                const SizedBox(width: 6),
                                _buildCountIncrementButton('+100', () {
                                  setModalState(() {
                                    tempCount += 100;
                                    countController.text = tempCount.toString();
                                  });
                                }),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Live Patient App Preview Simulation
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.phone_android_rounded, color: AdminColors.success, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        'معاينة حية كما سيظهر في تطبيق المريض (الأطباء الأعلى تقييماً ⭐):',
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          color: const Color(0xFF166534),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Center(
                                    child: Container(
                                      width: 190,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          CircleAvatar(
                                            radius: 28,
                                            backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                            backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                                                ? NetworkImage(profile['avatar_url'])
                                                : null,
                                            child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                                                ? const Icon(Icons.person, color: AdminColors.primaryDark)
                                                : null,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            doctorName,
                                            style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 12.5),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                          Text(
                                            doctorSpec,
                                            style: GoogleFonts.cairo(fontSize: 10, color: AdminColors.textSecondary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    tempRating.toStringAsFixed(1),
                                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w800),
                                                  ),
                                                ],
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AdminColors.accentMintLight,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  doctorGov,
                                                  style: GoogleFonts.cairo(fontSize: 9.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            width: double.infinity,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: AdminColors.primaryDark,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text('حجز موعد', style: GoogleFonts.cairo(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Footer Actions
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AdminColors.cardBorder)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                            child: Text(
                              'إلغاء التعديل',
                              style: GoogleFonts.cairo(color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: isSaving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.save_rounded, size: 18),
                            label: Text(
                              isSaving ? 'جارٍ الحفظ...' : 'حفظ التقييم وتحديث المنظومة فوراً 💾',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 13),
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

                                      // تنفيذ التحديث عبر الدالة الذرية RPC
                                      await _client.rpc('admin_update_doctor_rating', params: {
                                        'p_doctor_id': doc['id'],
                                        'p_rating_avg': finalRating,
                                        'p_rating_count': finalCount,
                                      });

                                      // تسجيل العملية في سجل الأمان والمراقبة
                                      await AdminAuditService.log(
                                        actionType: 'UPDATE_DOCTOR_RATING',
                                        targetType: 'DOCTOR',
                                        targetName: doctorName,
                                        targetId: doc['id'] as String?,
                                        details: {
                                          'doctor_id': doc['id'],
                                          'doctor_name': doctorName,
                                          'old_rating': currentRating,
                                          'new_rating': finalRating,
                                          'old_count': currentCount,
                                          'new_count': finalCount,
                                        },
                                      );

                                      // تحديث الحالة المحلية فوراً
                                      if (mounted) {
                                        setState(() {
                                          doc['rating_avg'] = finalRating;
                                          doc['rating_count'] = finalCount;
                                        });
                                      }

                                      navigator.pop();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'تم تحديث تقييم $doctorName بنجاح إلى $finalRating ⭐ ($finalCount تقييم)',
                                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                          ),
                                          backgroundColor: AdminColors.success,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      _fetchDoctors(silent: true);
                                    } catch (e) {
                                      debugPrint('Error updating doctor rating: $e');
                                      setModalState(() => isSaving = false);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('خطأ أثناء حفظ التقييم: $e', style: GoogleFonts.cairo()),
                                          backgroundColor: AdminColors.emergency,
                                        ),
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

  Widget _buildPresetChip(double val, String label, double current, Function(double) onSelect) {
    final isSelected = (current - val).abs() < 0.05;
    return InkWell(
      onTap: () => onSelect(val),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.shade100 : AdminColors.backgroundCanvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.amber.shade700 : AdminColors.cardBorder),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            color: isSelected ? Colors.amber.shade900 : AdminColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildCountIncrementButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AdminColors.accentMintLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AdminColors.cardBorderMint),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.primaryDark),
        ),
      ),
    );
  }

  String _getRatingFilterLabel(int filter) {
    switch (filter) {
      case 1:
        return '5.0 نجوم ⭐';
      case 2:
        return '4.5+ ممتاز ⭐';
      case 3:
        return '4.0 - 4.4 ⭐';
      case 4:
        return 'أقل من 4.0 ⭐';
      default:
        return 'الكل';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredDoctors();
    final govRanks = _calculateGovernorateRanks();

    // KPIs calculation
    final totalDocs = _doctors.length;
    double avgSum = 0;
    int ratedCount = 0;
    int fiveStarCount = 0;
    int eliteCount = 0;

    for (final d in _doctors) {
      final r = (d['rating_avg'] as num?)?.toDouble() ?? 0.0;
      if (r > 0) {
        avgSum += r;
        ratedCount++;
      }
      if (r >= 4.95) fiveStarCount++;
      if (r >= 4.5) eliteCount++;
    }

    final platformAvg = ratedCount > 0 ? (avgSum / ratedCount).toStringAsFixed(2) : '5.00';

    return Scaffold(
      backgroundColor: AdminColors.backgroundCanvas,
      body: RefreshIndicator(
        onRefresh: () => _fetchDoctors(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Banner & Title
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
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.stars_rounded, color: Colors.amber, size: 24),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'إدارة تقييمات الأطباء والأعلى تقييماً ⭐',
                            style: GoogleFonts.cairo(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'حوكمة دقيقة لتقييمات الأطباء والتحكم في ترتيب قسم "الأطباء الأعلى تقييماً" في تطبيق المريض حسب كل محافظة',
                        style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('تحديث البيانات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    onPressed: () => _fetchDoctors(),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 2. Statistical KPI Cards
              Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      title: 'إجمالي الأطباء',
                      value: '$totalDocs طبيب',
                      icon: Icons.people_alt_rounded,
                      color: AdminColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'متوسط تقييم المنظومة',
                      value: '$platformAvg ⭐',
                      icon: Icons.star_rounded,
                      color: Colors.amber.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'نخبة 5 نجوم كاملة',
                      value: '$fiveStarCount طبيب',
                      icon: Icons.workspace_premium_rounded,
                      color: AdminColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'تقييم ممتاز (4.5 فما فوق)',
                      value: '$eliteCount طبيب',
                      icon: Icons.military_tech_rounded,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 3. Toolbar & Search & Filters
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AdminColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AdminColors.cardBorderMint),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Search bar
                        Expanded(
                          flex: 3,
                          child: TextField(
                            style: GoogleFonts.cairo(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'ابحث باسم الطبيب، التخصص، أو الهاتف...',
                              hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                              prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.textSecondary),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      onPressed: () => setState(() => _searchQuery = ''),
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AdminColors.cardBorder),
                              ),
                              filled: true,
                              fillColor: AdminColors.backgroundCanvas,
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Governorate filter
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AdminColors.backgroundCanvas,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminColors.cardBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedGovernorate,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AdminColors.textSecondary),
                                style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                items: _egyptGovernorates
                                    .map((g) => DropdownMenuItem(value: g, child: Text(g == 'الكل' ? 'كل المحافظات 📍' : '📍 $g')))
                                    .toList(),
                                onChanged: (val) => setState(() => _selectedGovernorate = val ?? 'الكل'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Specialty filter
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AdminColors.backgroundCanvas,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminColors.cardBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedSpecialty,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AdminColors.textSecondary),
                                style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                items: ['الكل', ...SpecialtiesData.namesAr]
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s == 'الكل' ? 'كل التخصصات 🩺' : s)))
                                    .toList(),
                                onChanged: (val) => setState(() => _selectedSpecialty = val ?? 'الكل'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Sort order selector
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AdminColors.backgroundCanvas,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminColors.cardBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _sortBy,
                                isExpanded: true,
                                icon: const Icon(Icons.sort_rounded, color: AdminColors.textSecondary),
                                style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('الأعلى تقييماً أولاً 🏆')),
                                  DropdownMenuItem(value: 1, child: Text('الأكثر مراجعات 👥')),
                                  DropdownMenuItem(value: 2, child: Text('الاسم أبجدياً 🔤')),
                                ],
                                onChanged: (val) => setState(() => _sortBy = val ?? 0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // شريط إحصائي لحظي لتوتال الأطباء وحالة الفلترة
                    if (_selectedGovernorate != 'الكل' || _selectedSpecialty != 'الكل' || _selectedRatingFilter != 0 || _searchQuery.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.filter_alt_rounded, size: 18, color: AdminColors.primaryDark),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'إجمالي الأطباء: ${_doctors.length} | المطابق للفلترة: ${filtered.length} طبيب'
                                '${_selectedGovernorate != 'الكل' ? ' • المحافظة: $_selectedGovernorate' : ''}'
                                '${_selectedSpecialty != 'الكل' ? ' • التخصص: $_selectedSpecialty' : ''}'
                                '${_selectedRatingFilter != 0 ? ' • الفئة: ${_getRatingFilterLabel(_selectedRatingFilter)}' : ''}'
                                '${_searchQuery.isNotEmpty ? ' • بحث: "$_searchQuery"' : ''}',
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () {
                                setState(() {
                                  _selectedGovernorate = 'الكل';
                                  _selectedSpecialty = 'الكل';
                                  _selectedRatingFilter = 0;
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.clear_all_rounded, size: 16, color: Colors.red),
                              label: Text('إلغاء الفلاتر', style: GoogleFonts.cairo(fontSize: 11.5, color: Colors.red, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Rating Categories Pills
                    AdminModernTabBar(
                      tabs: [
                        AdminTabItem(label: 'كل التقييمات', icon: Icons.all_inclusive_rounded, count: _doctors.length),
                        AdminTabItem(label: '5.0 نجوم كاملة ⭐', icon: Icons.workspace_premium_rounded, count: fiveStarCount, badgeColor: Colors.amber.shade700),
                        AdminTabItem(label: 'ممتاز 4.5+ ⭐', icon: Icons.star_rounded, count: eliteCount, badgeColor: const Color(0xFF10B981)),
                        AdminTabItem(label: 'جيد 4.0 - 4.4 ⭐', icon: Icons.star_half_rounded),
                        AdminTabItem(label: 'أقل من 4.0 ⭐', icon: Icons.warning_amber_rounded, badgeColor: const Color(0xFFEF4444)),
                      ],
                      selectedIndex: _selectedRatingFilter,
                      onTabSelected: (idx) => setState(() => _selectedRatingFilter = idx),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 4. Doctors List / Table
              if (_isLoading && _doctors.isEmpty)
                const AdminTableSkeleton(rows: 8)
              else if (filtered.isEmpty)
                AdminEmptyStateCard(
                  title: 'لا يوجد أطباء مطابقين لخيارات البحث والتقييم',
                  description: 'حاول تغيير المحافظة المحددة أو خيارات الفلترة لعرض الأطباء.',
                  icon: Icons.star_border_rounded,
                  onRefresh: () => _fetchDoctors(),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final profile = doc['profiles'] as Map<String, dynamic>? ?? {};
                    final docGov = (profile['governorate'] as String?) ?? 'غير محدد';
                    final ratingAvg = ((doc['rating_avg'] as num?)?.toDouble() ?? 5.0);
                    final ratingCount = ((doc['rating_count'] as num?)?.toInt() ?? 0);
                    final doctorId = doc['id'] as String;

                    // Rank in this governorate
                    final targetGov = _selectedGovernorate == 'الكل' ? docGov : _selectedGovernorate;
                    final rankKey = '${doctorId}_$targetGov';
                    final rank = govRanks[rankKey] ?? (index + 1);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminColors.surfaceWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: rank == 1
                              ? Colors.amber.withValues(alpha: 0.6)
                              : AdminColors.cardBorderMint,
                          width: rank == 1 ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                            backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'] != '')
                                ? NetworkImage(profile['avatar_url'])
                                : null,
                            child: (profile['avatar_url'] == null || profile['avatar_url'] == '')
                                ? const Icon(Icons.person, color: AdminColors.primaryDark, size: 28)
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
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: AdminColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (rank <= 3)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: rank == 1
                                              ? Colors.amber.withValues(alpha: 0.2)
                                              : rank == 2
                                                  ? const Color(0xFFE2E8F0)
                                                  : const Color(0xFFFED7AA),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          rank == 1
                                              ? '#1 متصدر الأعلى تقييماً في $targetGov 🏆'
                                              : rank == 2
                                                  ? '#2 في $targetGov 🥈'
                                                  : '#3 في $targetGov 🥉',
                                          style: GoogleFonts.cairo(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            color: rank == 1 ? Colors.amber.shade900 : AdminColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${doc['specialty'] ?? 'تخصص عام'} • 📍 $docGov • 📞 ${profile['phone'] ?? 'بدون هاتف'}',
                                  style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                                ),
                              ],
                            ),
                          ),

                          // Rating Badge
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('التقييم الحالي:', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            ratingAvg.toStringAsFixed(1),
                                            style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12.5,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '($ratingCount تقييم)',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AdminColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Recommended status indicator
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('الظهور للمريض:', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                                const SizedBox(height: 2),
                                Text(
                                  rank <= 5 ? 'ضمن صدارة الأعلى تقييماً ⭐' : 'ترتيب رقم $rank بالمحافظة',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: rank <= 5 ? AdminColors.success : AdminColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Actions
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Edit Rating Button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber.shade700,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.star_rounded, size: 16),
                                label: Text(
                                  'تعديل التقييم ⭐',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                onPressed: () => _showEditDoctorRatingDialog(doc),
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
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorderMint),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
              ),
              Text(
                value,
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
