import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class AnalyticsBiScreen extends StatefulWidget {
  const AnalyticsBiScreen({super.key});

  @override
  State<AnalyticsBiScreen> createState() => _AnalyticsBiScreenState();
}

class _AnalyticsBiScreenState extends State<AnalyticsBiScreen> {
  final _client = AdminSupabaseConfig.client;
  bool _isLoading = true;
  Map<String, int> _governorateDistribution = {};
  int _totalTickets = 0;
  int _totalDoctors = 0;
  int _totalPharmacies = 0;

  @override
  void initState() {
    super.initState();
    _fetchBiAnalytics();
  }

  Future<void> _fetchBiAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final branchesRes = await _client.from('branches').select('governorate');
      final pharmaciesRes = await _client.from('pharmacies').select('governorate');
      final doctorsRes = await _client.from('doctors').select('id');
      final ticketsRes = await _client.from('tickets').select('id');

      final Map<String, int> govMap = {};

      for (final b in (branchesRes as List)) {
        final gov = b['governorate'] as String? ?? 'أخرى';
        govMap[gov] = (govMap[gov] ?? 0) + 1;
      }
      for (final p in (pharmaciesRes as List)) {
        final gov = p['governorate'] as String? ?? 'أخرى';
        govMap[gov] = (govMap[gov] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _governorateDistribution = govMap;
          _totalDoctors = (doctorsRes as List).length;
          _totalPharmacies = (pharmaciesRes as List).length;
          _totalTickets = (ticketsRes as List).length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalGovCount = _governorateDistribution.values.fold<int>(0, (sum, val) => sum + val);

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
                child: const Icon(Icons.analytics_rounded, color: AdminColors.primaryDark, size: 24),
              ),
              const SizedBox(width: 10),
              Text('لوحة التحليلات الاستراتيجية والخرائط الحرارية (BI Analytics)', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('توزيع الكثافة الطبية والصيدلانية في محافظات مصر، معدلات الإشغال، ومؤشرات نمو المنظومة', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),

          const SizedBox(height: 24),

          // BI Overview Cards
          Row(
            children: [
              Expanded(
                child: _buildBiCard('إجمالي الأطباء المعتمدين', '$_totalDoctors طبيب', Icons.medical_services_rounded, AdminColors.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBiCard('إجمالي الصيدليات الشريكة', '$_totalPharmacies صيدلية', Icons.local_pharmacy_rounded, AdminColors.accentMint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBiCard('إجمالي الحجوزات والتذاكر', '$_totalTickets كشف', Icons.confirmation_number_rounded, AdminColors.accentCyan),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Governorate Heatmap Card
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
                        const Icon(Icons.map_rounded, color: AdminColors.primaryDark, size: 22),
                        const SizedBox(width: 8),
                        Text('الخريطة الحرارية لكثافة الخدمات حسب المحافظات المصرية', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14.5)),
                      ],
                    ),
                    Text('إجمالي المراكز المسجلة: $totalGovCount مركز', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 16),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                else if (_governorateDistribution.isEmpty)
                  Center(child: Text('لا توجد بيانات جغرافية كافية حالياً', style: GoogleFonts.cairo(color: AdminColors.textSecondary)))
                else
                  ..._governorateDistribution.entries.map((entry) {
                    final ratio = totalGovCount > 0 ? (entry.value / totalGovCount) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildGovProgress(
                        'محافظة ${entry.key}',
                        ratio,
                        '${entry.value} فرع وصيدلية (${(ratio * 100).toInt()}%)',
                        _getColorForGov(entry.key),
                      ),
                    );
                  }),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Peak Hours Card
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
                  children: [
                    const Icon(Icons.access_time_filled_rounded, color: AdminColors.accentCyan, size: 22),
                    const SizedBox(width: 8),
                    Text('أوقات الذروة والإشغال الطبي اليومي', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 14.5)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTimeProgress('الفترة المسائية الأولى (05:00 م - 08:00 م)', 0.90, 'أعلى ذروة حجز 🔴 (90% إشغال)', AdminColors.emergency),
                const SizedBox(height: 12),
                _buildTimeProgress('الفترة المسائية المتأخرة (08:00 م - 11:00 م)', 0.72, 'ذروة متوسطة 🟡 (72% إشغال)', AdminColors.warning),
                const SizedBox(height: 12),
                _buildTimeProgress('الفترة الصباحية (10:00 ص - 02:00 م)', 0.45, 'إشغال منخفض 🟢 (45% إشغال)', AdminColors.success),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForGov(String gov) {
    switch (gov) {
      case 'القاهرة':
        return AdminColors.primaryDark;
      case 'الجيزة':
        return AdminColors.accentCyan;
      case 'الإسكندرية':
        return AdminColors.accentMint;
      case 'الدقهلية':
        return AdminColors.warning;
      case 'الغربية':
        return Colors.deepPurple;
      default:
        return AdminColors.textSecondary;
    }
  }

  Widget _buildBiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.cardBorderMint),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                Text(value, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGovProgress(String title, double ratio, String countText, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w800)),
            Text(countText, style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            backgroundColor: AdminColors.backgroundCanvas,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeProgress(String title, double ratio, String statusText, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.w800)),
            Text(statusText, style: GoogleFonts.cairo(fontSize: 11.5, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: AdminColors.backgroundCanvas,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
