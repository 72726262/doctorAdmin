import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _isLoading = true;
  List<Map<String, dynamic>> _announcements = [];

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.from('system_announcements').select().order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePublish() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة عنوان ونص الإعلان'), backgroundColor: AdminColors.warning),
      );
      return;
    }

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
      _fetchAnnouncements();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📢 تم بث الإعلان لجميع المستخدمين بنجاح!'), backgroundColor: AdminColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _deleteAnnouncement(String id) async {
    try {
      await _client.from('system_announcements').delete().eq('id', id);
      _fetchAnnouncements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الإعلان'), backgroundColor: AdminColors.emergency));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: const Icon(Icons.campaign_rounded, color: AdminColors.primaryDark, size: 24),
              ),
              const SizedBox(width: 10),
              Text('مركز الإذاعة والبث العام والتنبيهات', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('إرسال التنبيهات العامة للأطباء، الصيدليات، والمرضى وبث الإعلانات الرسمية اللحظية', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),

          const SizedBox(height: 20),

          // Broadcast Form
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
                Text('إنشاء وبث إعلان جديد 📢', style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(
                  controller: _titleController,
                  style: GoogleFonts.cairo(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'عنوان الإعلان أو التنبيه الرئيسي'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  style: GoogleFonts.cairo(fontSize: 13),
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'نص الإعلان والرسالة التفصيلية'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('الفئة المستهدفة: ', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _targetRole,
                      style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('جميع المستخدمين (الكل)')),
                        DropdownMenuItem(value: 'DOCTOR', child: Text('الأطباء فقط 👨‍⚕️')),
                        DropdownMenuItem(value: 'PHARMACY', child: Text('الصيدليات فقط 💊')),
                        DropdownMenuItem(value: 'PATIENT', child: Text('المرضى فقط 👥')),
                      ],
                      onChanged: (val) => setState(() => _targetRole = val ?? 'ALL'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.primaryDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: _isPublishing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_isPublishing ? 'جاري البث...' : 'بث الإعلان الآن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      onPressed: _isPublishing ? null : _handlePublish,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Active Announcements List
          Text('الإعلانات المبثوثة النشطة:', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800, color: AdminColors.textPrimary)),
          const SizedBox(height: 12),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
          else if (_announcements.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AdminColors.surfaceWhite, borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text('لا توجد إعلانات مبثوثة حالياً', style: GoogleFonts.cairo(color: AdminColors.textSecondary))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _announcements.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final a = _announcements[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AdminColors.cardBorderMint),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AdminColors.accentMintLight, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.campaign_rounded, color: AdminColors.primaryDark, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(a['title'] ?? '', style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 14)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AdminColors.primaryDark.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                                  child: Text('المستهدف: ${a['target_role']}', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(a['content'] ?? '', style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف الإعلان',
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        onPressed: () => _deleteAnnouncement(a['id']),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
