import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _client = AdminSupabaseConfig.client;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _targetRole = 'ALL';
  bool _isPublishing = false;

  Future<List<Map<String, dynamic>>> _fetchAnnouncements() async {
    final res = await _client.from('system_announcements').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> _handlePublish() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) return;

    setState(() => _isPublishing = true);

    try {
      await _client.from('system_announcements').insert({
        'title': title,
        'content': content,
        'target_role': _targetRole,
        'is_active': true,
      });

      _titleController.clear();
      _contentController.clear();
      setState(() => _isPublishing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📢 تم بث الإعلان لجميع مستخدمي المنظومة بنجاح!'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isPublishing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // نموذج بث إعلان جديد
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
                    Icon(Icons.campaign_rounded, color: AdminColors.primaryDark, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'بث إعلان وتنبيه عام للمستخدمين',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'عنوان الإعلان أو التنبيه'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'نص الرسالة أو الإعلان التفصيلي'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _targetRole,
                  decoration: const InputDecoration(labelText: 'الفئة المستهدفة'),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('جميع المستخدمين (مرضى، أطباء، صيدليات)')),
                    DropdownMenuItem(value: 'DOCTOR', child: Text('الأطباء والعيادات فقط')),
                    DropdownMenuItem(value: 'PHARMACY', child: Text('الصيدليات فقط')),
                    DropdownMenuItem(value: 'PATIENT', child: Text('المرضى فقط')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _targetRole = val);
                  },
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _isPublishing ? null : _handlePublish,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('بث الإعلان الآن'),
                  style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          const Text(
            'سجل الإعلانات والتنبيهات السابقة:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 12),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchAnnouncements(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final list = snapshot.data ?? [];

              if (list.isEmpty) {
                return const Text('لا توجد إعلانات سابقة مسجلة');
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final ann = list[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AdminColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminColors.cardBorderMint),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ann['title'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ann['content'] as String? ?? '',
                          style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
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
