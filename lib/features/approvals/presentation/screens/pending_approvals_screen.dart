import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final _client = AdminSupabaseConfig.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingList = [];

  @override
  void initState() {
    super.initState();
    _fetchPendingProfiles();
  }

  Future<void> _fetchPendingProfiles() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client
          .from('profiles')
          .select('''
            id,
            full_name,
            phone,
            role,
            governorate,
            avatar_url,
            created_at,
            doctors (
              specialty,
              bio
            ),
            pharmacies (
              name,
              address_text
            )
          ''')
          .eq('is_approved', false)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingList = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveUser(String userId, String name) async {
    try {
      await _client.from('profiles').update({'is_approved': true}).eq('id', userId);
      _fetchPendingProfiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 تم اعتماد وتفعيل حساب $name بنجاح!'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    }
  }

  Future<void> _rejectUser(String userId, String name) async {
    try {
      await _client.from('profiles').delete().eq('id', userId);
      _fetchPendingProfiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم رفض وحذف طلب $name'),
            backgroundColor: AdminColors.emergency,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                        decoration: BoxDecoration(color: AdminColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.verified_user_rounded, color: AdminColors.warning, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text('طلبات الاعتماد والانضمام الجديدة', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('مراجعة طلبات انضمام الأطباء والصيدليات والتحقق من الهوية والتراخيص قبل النشر', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث الطلبات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchPendingProfiles,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                : _pendingList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: const BoxDecoration(color: AdminColors.accentMintLight, shape: BoxShape.circle),
                              child: const Icon(Icons.check_circle_outline_rounded, size: 56, color: AdminColors.success),
                            ),
                            const SizedBox(height: 18),
                            Text('رائع! لا توجد طلبات اعتماد معلقة حالياً', style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w800, color: AdminColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text('جميع الأطباء والصيدليات المسجلين معتمدون ويعملون بشكل طبيعي', style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _pendingList.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final user = _pendingList[index];
                          final role = user['role'] as String? ?? 'DOCTOR';
                          final isDoctor = role == 'DOCTOR';
                          final docData = user['doctors'] as Map<String, dynamic>?;
                          final phaData = user['pharmacies'] as Map<String, dynamic>?;

                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AdminColors.surfaceWhite,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                  backgroundImage: (user['avatar_url'] != null && user['avatar_url'] != '')
                                      ? NetworkImage(user['avatar_url'])
                                      : null,
                                  child: (user['avatar_url'] == null || user['avatar_url'] == '')
                                      ? Icon(isDoctor ? Icons.medical_services_rounded : Icons.local_pharmacy_rounded, color: AdminColors.primaryDark)
                                      : null,
                                ),
                                const SizedBox(width: 14),

                                // Info
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            user['full_name'] ?? 'مستخدم جديد',
                                            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                            child: Text('طلب جديد ⏳', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                                          ),
                                        ],
                                      ),
                                      if (isDoctor && docData != null)
                                        Text('التخصص: ${docData['specialty'] ?? ''}', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.accentCyan, fontWeight: FontWeight.bold))
                                      else if (!isDoctor && phaData != null)
                                        Text('الصيدلية: ${phaData['name'] ?? ''} - ${phaData['address_text'] ?? ''}', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.accentMint, fontWeight: FontWeight.bold)),
                                      Text(
                                        '📞 الهاتف: ${user['phone'] ?? ''} | 📍 المحافظة: ${user['governorate'] ?? 'مصر'}',
                                        style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),

                                // Actions
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AdminColors.emergency,
                                    side: const BorderSide(color: AdminColors.emergency),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.close_rounded, size: 16),
                                  label: Text('رفض', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: () => _rejectUser(user['id'], user['full_name'] ?? ''),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AdminColors.success,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.check_rounded, size: 16),
                                  label: Text('اعتماد وتفعيل', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: () => _approveUser(user['id'], user['full_name'] ?? ''),
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
