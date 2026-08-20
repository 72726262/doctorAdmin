import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';

class AnalyticsBiScreen extends StatelessWidget {
  const AnalyticsBiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        child: const Icon(Icons.analytics_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'لوحة التحليلات الاستراتيجية والخرائط الحرارية (BI Analytics)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'توزيع الإشغال الطبي في محافظات مصر، توقع أوقات الذروة، ومؤشرات نمو المنصة',
                    style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Governorates Distribution Heatmap Cards
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
                        const Row(
                          children: [
                            Icon(Icons.map_rounded, color: AdminColors.primaryDark, size: 20),
                            SizedBox(width: 8),
                            Text('الخريطة الحرارية للحجوزات حسب المحافظات المصرية', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildGovProgress('محافظة القاهرة', 0.85, '4,820 كشف', AdminColors.primaryDark),
                        const SizedBox(height: 12),
                        _buildGovProgress('محافظة الجيزة', 0.65, '3,110 كشف', AdminColors.accentCyan),
                        const SizedBox(height: 12),
                        _buildGovProgress('محافظة الإسكندرية', 0.52, '2,490 كشف', AdminColors.accentMint),
                        const SizedBox(height: 12),
                        _buildGovProgress('محافظة الدقهلية (المنصورة)', 0.44, '1,980 كشف', AdminColors.warning),
                        const SizedBox(height: 12),
                        _buildGovProgress('محافظة الغربية (طنطا)', 0.38, '1,420 كشف', AdminColors.accentMint),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Peak Hours Analysis
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
                        const Row(
                          children: [
                            Icon(Icons.access_time_filled_rounded, color: AdminColors.accentCyan, size: 20),
                            SizedBox(width: 8),
                            Text('تحليل أوقات الذروة وساعات الضغط في العيادات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _PeakHourCard(time: '5:00 - 8:00 م', load: 'ذروة قصوى (92%)', color: AdminColors.emergency),
                            _PeakHourCard(time: '8:00 - 11:00 م', load: 'ضغط مرتفع (78%)', color: AdminColors.warning),
                            _PeakHourCard(time: '1:00 - 4:00 م', load: 'معدل متوسط (45%)', color: AdminColors.success),
                            _PeakHourCard(time: '9:00 ص - 12:00 ظ', load: 'هدوء نسبي (22%)', color: AdminColors.primaryDark),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGovProgress(String govName, double progress, String countText, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(govName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            Text(countText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _PeakHourCard extends StatelessWidget {
  final String time;
  final String load;
  final Color color;

  const _PeakHourCard({required this.time, required this.load, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(load, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
