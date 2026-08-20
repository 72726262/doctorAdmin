import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';

class AuditSecurityScreen extends StatefulWidget {
  const AuditSecurityScreen({super.key});

  @override
  State<AuditSecurityScreen> createState() => _AuditSecurityScreenState();
}

class _AuditSecurityScreenState extends State<AuditSecurityScreen> {
  final List<Map<String, dynamic>> _auditLogs = [
    {
      'admin': 'أدمن المنظومة الرئيسي',
      'action': 'اعتماد ترخيص طبيب',
      'target': 'د. خالد عبد الرحمن (جراحة العظام)',
      'ip': '197.34.12.89',
      'timestamp': 'منذ 12 دقيقة',
      'status': 'SUCCESS',
    },
    {
      'admin': 'المسؤول المالي',
      'action': 'تأكيد إيصال سداد وتفعيل باقة 30 يوماً',
      'target': 'د. رانيا عبد الفتاح (فودافون كاش: 1,500 ج.م)',
      'ip': '197.34.12.89',
      'timestamp': 'منذ 34 دقيقة',
      'status': 'SUCCESS',
    },
    {
      'admin': 'النظام التلقائي (Anti-Spam)',
      'action': 'حظر رقم هاتف بسبب تكرار حجز وهمي',
      'target': 'الرقم: 01099887766 (5 حجوزات ملغاة في 10 دقائق)',
      'ip': '41.233.15.60',
      'timestamp': 'منذ ساعتين',
      'status': 'BLOCKED',
    },
    {
      'admin': 'أدمن التشغيل',
      'action': 'بث تنبيه إذاعي للمرضى',
      'target': 'محافظة الإسكندرية (تأخير مواعيد العيادات)',
      'ip': '197.34.12.89',
      'timestamp': 'منذ 3 ساعات',
      'status': 'SUCCESS',
    },
  ];

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
                        child: const Icon(Icons.shield_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'مركز الأمان وسجل العمليات الإدارية (Audit Trail)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'سجل رقابي غير قابل للتعديل لكل حركة وإجراء إداري مع رصد محاولات الاحتيال والحجز الوهمي',
                    style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AdminColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AdminColors.success, size: 16),
                    SizedBox(width: 6),
                    Text('درع الحماية نشط 🛡️', style: TextStyle(color: AdminColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              itemCount: _auditLogs.length,
              itemBuilder: (context, index) {
                final log = _auditLogs[index];
                final isBlocked = log['status'] == 'BLOCKED';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                        decoration: BoxDecoration(
                          color: (isBlocked ? AdminColors.emergency : AdminColors.primaryDark).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isBlocked ? Icons.block_rounded : Icons.history_edu_rounded,
                          color: isBlocked ? AdminColors.emergency : AdminColors.primaryDark,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(log['action'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                                const SizedBox(width: 8),
                                Text('(${log['admin']})', style: const TextStyle(fontSize: 11.5, color: AdminColors.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(log['target'], style: const TextStyle(fontSize: 12, color: AdminColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text('IP: ${log['ip']} • ${log['timestamp']}', style: const TextStyle(fontSize: 11, color: AdminColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
