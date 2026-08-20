import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _client = AdminSupabaseConfig.client;

  Future<List<Map<String, dynamic>>> _fetchPaymentMethods() async {
    final res = await _client.from('payment_methods').select().order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res as List);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // كارت معلومات النظام
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.cardBorderMint),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'معلومات البنية التحتية والسيرفر ⚙️',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                SizedBox(height: 12),
                Text('قاعدة البيانات: PostgreSQL 17 (Supabase Platform)'),
                SizedBox(height: 4),
                Text('نطاق السيرفر: https://ztpqokvytjmlgyxhuhrv.supabase.co'),
                SizedBox(height: 4),
                Text('نظام التحقق والتنبيه: Realtime WebSocket Channels Enabled'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // طرق الدفع
          const Text(
            'حسابات الدفع وتلقي اشتراكات الأطباء:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 12),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchPaymentMethods(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final methods = snapshot.data ?? [];

              if (methods.isEmpty) {
                return const Text('لا توجد طرق دفع معرفة في النظام');
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: methods.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final m = methods[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AdminColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.cardBorderMint),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, color: AdminColors.primaryDark, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m['name_ar'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                              ),
                              Text(
                                'الرقم / الحساب: ${m['account_number'] ?? ''}',
                                style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
                              ),
                              if (m['instructions'] != null)
                                Text(
                                  m['instructions'] as String,
                                  style: const TextStyle(fontSize: 11.5, color: AdminColors.textMuted),
                                ),
                            ],
                          ),
                        ),
                        Switch(
                          value: m['is_active'] as bool? ?? true,
                          activeThumbColor: AdminColors.primaryDark,
                          onChanged: (val) async {
                            await _client.from('payment_methods').update({'is_active': val}).eq('id', m['id']);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
