import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';

class UnopenedClinicsScreen extends StatefulWidget {
  const UnopenedClinicsScreen({super.key});

  @override
  State<UnopenedClinicsScreen> createState() => _UnopenedClinicsScreenState();
}

class _UnopenedClinicsScreenState extends State<UnopenedClinicsScreen> {
  final _client = AdminSupabaseConfig.client;

  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1));
  String _selectedGovernorate = 'الكل';
  String _searchQuery = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _clinics = [];

  final List<String> _governorates = [
    'الكل',
    'القاهرة',
    'الجيزة',
    'الإسكندرية',
    'الغربية',
    'الدقهلية',
    'الشرقية',
    'المنوفية',
    'القليوبية',
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
  ];

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchReport() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = _formatDateForApi(_selectedDate);
      final res = await _client.rpc('get_unopened_clinics_report', params: {
        'p_date': dateStr,
        'p_governorate': _selectedGovernorate == 'الكل' ? null : _selectedGovernorate,
      });

      if (mounted) {
        final list = List<Map<String, dynamic>>.from(res as List);
        setState(() {
          _clinics = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching unopened clinics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setDate(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    _fetchReport();
  }

  Future<void> _selectCustomDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AdminColors.primaryDark,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AdminColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      _setDate(picked);
    }
  }

  List<Map<String, dynamic>> get _filteredClinics {
    if (_searchQuery.trim().isEmpty) return _clinics;
    final query = _searchQuery.toLowerCase().trim();
    return _clinics.where((c) {
      final docName = (c['doctor_name'] ?? '').toString().toLowerCase();
      final branchName = (c['branch_name'] ?? '').toString().toLowerCase();
      final specialty = (c['doctor_specialty'] ?? '').toString().toLowerCase();
      final phone = (c['doctor_phone'] ?? '').toString().toLowerCase();
      return docName.contains(query) ||
          branchName.contains(query) ||
          specialty.contains(query) ||
          phone.contains(query);
    }).toList();
  }

  int get _totalWastedBookings =>
      _filteredClinics.fold(0, (sum, c) => sum + ((c['wasted_count'] as int?) ?? 0));

  int get _totalWarningsIssued =>
      _filteredClinics.where((c) => c['has_warning_for_date'] == true).length;

  int get _pendingWarningsCount =>
      _filteredClinics.where((c) => c['has_warning_for_date'] != true).length;

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredClinics;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
    final isYesterday = _selectedDate.year == today.subtract(const Duration(days: 1)).year &&
        _selectedDate.month == today.subtract(const Duration(days: 1)).month &&
        _selectedDate.day == today.subtract(const Duration(days: 1)).day;
    final isDayBefore = _selectedDate.year == today.subtract(const Duration(days: 2)).year &&
        _selectedDate.month == today.subtract(const Duration(days: 2)).month &&
        _selectedDate.day == today.subtract(const Duration(days: 2)).day;

    return Scaffold(
      backgroundColor: AdminColors.backgroundCanvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. رأس الصفحة والعنوان الفاخر
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
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Icon(Icons.report_problem_rounded, color: Colors.red, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'رقابة العيادات المتخلفة والإنذارات ⚠️',
                          style: GoogleFonts.cairo(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AdminColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'رصد العيادات التي كان لديها حجز للمرضى ولم يُفتح طابورها، وتوجيه الإنذارات الرسمية للأطباء',
                      style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _fetchReport,
                  icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                  tooltip: 'تحديث البيانات فوراً',
                ),
              ],
            ),

            const SizedBox(height: 18),

            // 2. شريط الفلاتر الزمنية واختيار التاريخ
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AdminColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 12,
                    spacing: 12,
                    children: [
                      // أزرار الفلترة السريعة للتاريخ بمساحات رحبة وواضحة تماماً
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildDateTab(
                            label: 'اليوم',
                            isSelected: isToday,
                            onTap: () => _setDate(today),
                          ),
                          _buildDateTab(
                            label: 'أمس',
                            isSelected: isYesterday,
                            onTap: () => _setDate(today.subtract(const Duration(days: 1))),
                          ),
                          _buildDateTab(
                            label: 'أول أمس',
                            isSelected: isDayBefore,
                            onTap: () => _setDate(today.subtract(const Duration(days: 2))),
                          ),
                          _buildDateTab(
                            label: !isToday && !isYesterday && !isDayBefore
                                ? 'تاريخ: ${_formatDateForApi(_selectedDate)}'
                                : 'تاريخ مخصص 📅',
                            isSelected: !isToday && !isYesterday && !isDayBefore,
                            icon: Icons.calendar_month_rounded,
                            onTap: () => _selectCustomDate(context),
                          ),
                        ],
                      ),

                      // فلتر المحافظة
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdminColors.cardBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedGovernorate,
                            icon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 6),
                              child: Icon(Icons.location_on_outlined, size: 18, color: AdminColors.primaryDark),
                            ),
                            style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textPrimary, fontWeight: FontWeight.bold),
                            items: _governorates.map((gov) {
                              return DropdownMenuItem(value: gov, child: Text(gov));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedGovernorate = val);
                                _fetchReport();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // شريط البحث المباشر
                  TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم الطبيب، اسم العيادة، التخصص، أو رقم الهاتف...',
                      hintStyle: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AdminColors.textMuted),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AdminColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AdminColors.cardBorder),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 3. كروت مؤشرات الـ KPIs الإحصائية
            Row(
              children: [
                Expanded(
                  child: _buildKpiCard(
                    title: 'العيادات المتخلفة عن الفتح',
                    value: '${filtered.length}',
                    subtitle: 'عيادات لم تشغل طوابيرها',
                    icon: Icons.cancel_presentation_rounded,
                    color: Colors.red.shade700,
                    bgColor: Colors.red.shade50,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildKpiCard(
                    title: 'الحجوزات والتذاكر المهدرة',
                    value: '$_totalWastedBookings',
                    subtitle: 'مريض تضرروا من عدم الحضور',
                    icon: Icons.people_outline_rounded,
                    color: Colors.amber.shade800,
                    bgColor: Colors.amber.shade50,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildKpiCard(
                    title: 'الإنذارات الصادرة',
                    value: '$_totalWarningsIssued',
                    subtitle: 'طبيب تم توجيه إنذار رسمي لهم',
                    icon: Icons.mark_email_read_rounded,
                    color: AdminColors.primaryDark,
                    bgColor: AdminColors.accentMintLight,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildKpiCard(
                    title: 'عيادات بانتظار الإنذار',
                    value: '$_pendingWarningsCount',
                    subtitle: 'مخالفات تستوجب التحذير فوراً',
                    icon: Icons.notification_important_rounded,
                    color: Colors.deepOrange,
                    bgColor: Colors.deepOrange.shade50,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 4. جدول/قائمة العيادات المتخلفة
            if (_isLoading)
              const AdminStatSkeleton(count: 3)
            else if (filtered.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: AdminColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AdminColors.cardBorder),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: AdminColors.accentMintLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_outline_rounded, size: 56, color: AdminColors.primaryDark),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ممتاز! لا توجد عيادات متخلفة عن الفتح في هذا اليوم 🎉',
                      style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'جميع الأطباء الذين كان لديهم حجوزات التزموا بفتح عياداتهم وتشغيل الطوابير بنجاح.',
                      style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final clinic = filtered[index];
                  return _buildClinicCard(context, clinic);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AdminColors.primaryDark : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AdminColors.primaryDark : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AdminColors.primaryDark.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : AdminColors.primaryDark,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? Colors.white : AdminColors.textPrimary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                ),
                Text(
                  title,
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textMuted),
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

  Widget _buildClinicCard(BuildContext context, Map<String, dynamic> clinic) {
    final docName = clinic['doctor_name'] ?? 'الطبيب';
    final docSpecialty = clinic['doctor_specialty'] ?? 'طبيب معتمد';
    final branchName = clinic['branch_name'] ?? 'الفرع';
    final gov = clinic['branch_governorate'] ?? '';
    final address = clinic['branch_address'] ?? '';
    final phone = clinic['doctor_phone'] ?? '';
    final wastedCount = clinic['wasted_count'] as int? ?? 0;
    final totalBookings = clinic['total_bookings'] as int? ?? 0;
    final pastWarningsCount = clinic['total_past_warnings_count'] as int? ?? 0;
    final hasWarningForDate = clinic['has_warning_for_date'] == true;
    final currentWarningLevel = clinic['current_warning_level'] as String?;
    final branchId = clinic['branch_id'] as String;
    final doctorId = clinic['doctor_id'] as String;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasWarningForDate ? Colors.amber.shade300 : Colors.red.shade200,
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الصف العلوي: بيانات الطبيب وشارة الحالة
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.red.shade50,
                child: const Icon(Icons.person_off_rounded, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            docName,
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AdminColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            'لم تُفتح العيادة 🛑',
                            style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$docSpecialty • $branchName ($gov)',
                      style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    if (address.isNotEmpty)
                      Text(
                        address,
                        style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.phone_android_rounded, size: 15, color: Color(0xFF15803D)),
                              const SizedBox(width: 6),
                              SelectableText(
                                phone,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF14532D),
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: phone));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                          const SizedBox(width: 8),
                                          Text('تم نسخ رقم الهاتف: $phone', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: AdminColors.primaryDark,
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: const Tooltip(
                                    message: 'نسخ رقم الهاتف',
                                    child: Icon(Icons.copy_rounded, size: 12, color: Color(0xFF15803D)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // حالة الإنذار لهذا اليوم
              if (hasWarningForDate)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _getWarningLevelDisplayName(currentWarningLevel),
                        style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'لم يُرسل إنذار بعد ⚠️',
                        style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // شريط إحصائيات المخالفة
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('إجمالي الحجوزات', '$totalBookings تذكرة', AdminColors.textPrimary),
                Container(width: 1, height: 28, color: Colors.grey.shade300),
                _buildStatItem('التذاكر المهدرة للمرضى', '$wastedCount تذكرة لم تُخدم', Colors.red.shade700),
                Container(width: 1, height: 28, color: Colors.grey.shade300),
                _buildStatItem('سجل الإنذارات التاريخي', '$pastWarningsCount إنذار سابق', pastWarningsCount > 0 ? Colors.amber.shade900 : AdminColors.textSecondary),
                Container(width: 1, height: 28, color: Colors.grey.shade300),
                _buildStatItem('تاريخ التقصير', _formatDateForApi(_selectedDate), AdminColors.primaryDark),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // أزرار العمليات المباشرة للإدارة
          // أزرار العمليات المباشرة للإدارة (متجاوبة تماماً مع الشاشات والتابلت)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 10,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // زر إرسال إنذار رسمي
                  ElevatedButton.icon(
                    onPressed: () => _showSendWarningModal(context, clinic),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      hasWarningForDate ? 'إرسال إنذار إضافي / تصعيد ⚠️' : 'إرسال إنذار رسمي للطبيب ⚠️',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasWarningForDate ? Colors.amber.shade800 : Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),

                  // زر استعراض المرضى والتذاكر المهدرة
                  OutlinedButton.icon(
                    onPressed: () => _showWastedTicketsModal(context, branchId, docName),
                    icon: const Icon(Icons.people_alt_outlined, size: 16, color: AdminColors.primaryDark),
                    label: Text('كشف المرضى المتضررين ($wastedCount) 📋', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AdminColors.primaryDark),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),

                  // زر سجل الإنذارات السابقة
                  OutlinedButton.icon(
                    onPressed: () => _showWarningsHistoryModal(context, doctorId, docName),
                    icon: const Icon(Icons.history_edu_rounded, size: 16, color: AdminColors.textSecondary),
                    label: Text('سجل الإنذارات ($pastWarningsCount) 📜', style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AdminColors.cardBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),

              // أزرار التواصل المباشر مع ظهور الرقم كاملاً للمشرف (للاتصال من التابلت أو الموبايل)
              if (phone.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // زر واتساب الطبيب
                    OutlinedButton.icon(
                      onPressed: () => _launchWhatsApp(phone, docName, wastedCount),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Color(0xFF15803D)),
                      label: Text('واتساب', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF15803D))),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFDCFCE7),
                        side: const BorderSide(color: Color(0xFF86EFAC)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),

                    // زر اتصال مباشر يظهر رقم الهاتف بوضوح شديد
                    ElevatedButton.icon(
                      onPressed: () => _launchPhone(phone),
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 16, color: Colors.white),
                      label: Text(
                        'اتصال: $phone',
                        style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.primaryDark,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w900, color: valueColor)),
        Text(label, style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textMuted)),
      ],
    );
  }

  String _getWarningLevelDisplayName(String? level) {
    switch (level) {
      case 'FIRST_WARNING':
        return 'إنذار أول 🟡';
      case 'SECOND_WARNING':
        return 'إنذار ثانٍ 🟠';
      case 'FINAL_WARNING':
        return 'إنذار نهائي 🔴';
      case 'SUSPENSION_NOTICE':
        return 'إشعار تجميد ⛔';
      default:
        return 'إنذار رسمي ⚠️';
    }
  }

  Future<void> _launchWhatsApp(String phone, String docName, int wastedCount) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final dateStr = _formatDateForApi(_selectedDate);
    final text = Uri.encodeComponent(
      'تحية طيبة يا $docName، إدارة منصة كشفك الطبية تود الاستفسار عن عدم فتح العيادة بتاريخ $dateStr وتخلفكم عن خدمة $wastedCount مريض حاجزين. يرجى توضيح سبب التخلف لاتخاذ الإجراءات اللازمة.',
    );
    final url = Uri.parse('https://wa.me/$cleanPhone?text=$text');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final url = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  /// نافذة إرسال إنذار رسمي متعدد المستويات
  void _showSendWarningModal(BuildContext context, Map<String, dynamic> clinic) {
    final docName = clinic['doctor_name'] ?? 'الطبيب';
    final branchName = clinic['branch_name'] ?? 'العيادة';
    final wastedCount = clinic['wasted_count'] as int? ?? 0;
    final doctorId = clinic['doctor_id'] as String;
    final branchId = clinic['branch_id'] as String;
    final pastWarningsCount = clinic['total_past_warnings_count'] as int? ?? 0;
    final dateStr = _formatDateForApi(_selectedDate);

    String selectedLevel = pastWarningsCount == 0
        ? 'FIRST_WARNING'
        : (pastWarningsCount == 1 ? 'SECOND_WARNING' : 'FINAL_WARNING');

    final reasonController = TextEditingController(
      text: 'تنبيه إداري رسمي: رصد عدم فتح عيادة $branchName بتاريخ $dateStr، مما تسبب في إهدار موعد $wastedCount مريض مسجلين دون إخطار مسبق. يُرجى الالتزام بمواعيد العمل المقررة حفاظاً على سلامة المرضى وتجنباً لتجميد العيادة.',
    );
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.notification_important_rounded, color: Colors.red, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إصدار إنذار رسمي لطبيب ⚠️', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w900)),
                        Text('$docName • $branchName', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // اختيار مستوى وشدة الإنذار
                      Text('درجة ومستوى الإنذار:', style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildLevelChip('FIRST_WARNING', 'إنذار أول 🟡', selectedLevel, (val) {
                            setModalState(() => selectedLevel = val);
                          }),
                          _buildLevelChip('SECOND_WARNING', 'إنذار ثانٍ 🟠', selectedLevel, (val) {
                            setModalState(() => selectedLevel = val);
                          }),
                          _buildLevelChip('FINAL_WARNING', 'إنذار نهائي 🔴', selectedLevel, (val) {
                            setModalState(() => selectedLevel = val);
                          }),
                          _buildLevelChip('SUSPENSION_NOTICE', 'إشعار تجميد ⛔', selectedLevel, (val) {
                            setModalState(() => selectedLevel = val);
                          }),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // نص الإنذار المرسل للطبيب
                      Text('نص الإنذار الرسمي (سيظهر في لوحة تحكم الطبيب):', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: reasonController,
                        maxLines: 4,
                        style: GoogleFonts.cairo(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'اكتب نص الإنذار والتوجيه الإداري للطبيب...',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ملاحظات الإدارة الداخلية
                      Text('ملاحظات الإدارة الداخلية (سرية للمشرفين فقط):', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        style: GoogleFonts.cairo(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'ملاحظات المشرف، سبب التقصير أو رقم المتابعة...',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.cardBorder)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty) return;

                    Navigator.pop(dialogCtx);
                    await _sendWarning(
                      doctorId: doctorId,
                      branchId: branchId,
                      docName: docName,
                      level: selectedLevel,
                      reason: reason,
                      wastedTickets: wastedCount,
                      notes: notesController.text.trim(),
                    );
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text('تأكيد وإرسال الإنذار ⚠️', style: GoogleFonts.cairo(fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLevelChip(String levelKey, String label, String currentLevel, Function(String) onSelect) {
    final isSelected = currentLevel == levelKey;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: (_) => onSelect(levelKey),
      selectedColor: AdminColors.primaryDark,
      labelStyle: TextStyle(color: isSelected ? Colors.white : AdminColors.textPrimary),
      backgroundColor: const Color(0xFFF1F5F9),
    );
  }

  Future<void> _sendWarning({
    required String doctorId,
    required String branchId,
    required String docName,
    required String level,
    required String reason,
    required int wastedTickets,
    required String notes,
  }) async {
    try {
      final res = await _client.rpc('send_doctor_clinic_warning', params: {
        'p_doctor_id': doctorId,
        'p_branch_id': branchId,
        'p_warning_date': _formatDateForApi(_selectedDate),
        'p_warning_level': level,
        'p_reason': reason,
        'p_wasted_tickets_count': wastedTickets,
        'p_admin_notes': notes.isEmpty ? null : notes,
        'p_admin_id': _client.auth.currentUser?.id,
      });

      if (mounted) {
        final resMap = Map<String, dynamic>.from(res as Map);
        if (resMap['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('تم إرسال الإنذار الرسمي للطبيب $docName بنجاح ⚠️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ],
              ),
              backgroundColor: AdminColors.primaryDark,
            ),
          );
          _fetchReport();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إرسال الإنذار: $e', style: GoogleFonts.cairo())),
        );
      }
    }
  }

  /// نافذة كشف المرضى والتذاكر المهدرة
  void _showWastedTicketsModal(BuildContext context, String branchId, String docName) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.people_outline_rounded, color: AdminColors.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text('كشف المرضى المتضررين • $docName', style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: FutureBuilder(
              future: _client.rpc('get_wasted_tickets_for_clinic', params: {
                'p_branch_id': branchId,
                'p_date': _formatDateForApi(_selectedDate),
              }),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark));
                }
                final list = List<Map<String, dynamic>>.from((snapshot.data as List?) ?? []);
                if (list.isEmpty) {
                  return Center(child: Text('لا توجد تذاكر مسجلة', style: GoogleFonts.cairo()));
                }

                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = list[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade50,
                        child: Text(
                          '#${item['ticket_number']}',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.w900, color: Colors.red.shade800, fontSize: 13),
                        ),
                      ),
                      title: Text(item['patient_name'] ?? 'مريض', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('هاتف: ${item['patient_phone'] ?? 'غير مسجل'} • الحالة: ${item['status']}', style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary)),
                      trailing: item['patient_phone'] != null && item['patient_phone'].toString().isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.phone_forwarded_rounded, size: 18, color: AdminColors.primaryDark),
                              onPressed: () => _launchPhone(item['patient_phone']),
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إغلاق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// نافذة سجل الإنذارات التاريخي للطبيب
  void _showWarningsHistoryModal(BuildContext context, String doctorId, String docName) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.history_edu_rounded, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text('سجل الإنذارات التاريخي • $docName', style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 400,
            child: FutureBuilder(
              future: _client.rpc('get_doctor_warnings_history', params: {
                'p_doctor_id': doctorId,
              }),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark));
                }
                final list = List<Map<String, dynamic>>.from((snapshot.data as List?) ?? []);
                if (list.isEmpty) {
                  return Center(
                    child: Text('لا توجد إنذارات سابقة مسجلة على هذا الطبيب 🟢', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  );
                }

                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final w = list[index];
                    final isAck = w['is_acknowledged'] == true;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _getWarningLevelDisplayName(w['warning_level']),
                                style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 12.5),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isAck ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isAck ? 'تم الإقرار والاطلاع ✅' : 'بانتظار إقرار الطبيب ⏳',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isAck ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('تاريخ المخالفة: ${w['warning_date']} • عدد التذاكر المهدرة: ${w['wasted_tickets_count']}', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textMuted)),
                          const SizedBox(height: 6),
                          Text(w['reason'] ?? '', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textPrimary)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إغلاق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
