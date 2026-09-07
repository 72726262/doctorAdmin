import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/create_admin_dialog.dart';

/// شاشة حوكمة وإدارة فريق المشرفين والمسؤولين (Admin Management Screen)
class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  final _client = AdminSupabaseConfig.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _admins = [];
  String _searchQuery = '';
  String? _currentAdminId;

  @override
  void initState() {
    super.initState();
    _currentAdminId = _client.auth.currentUser?.id;
    _fetchAdmins();
  }

  Future<void> _fetchAdmins({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final res = await _client.rpc('admin_get_all_admins');
      if (res != null) {
        final list = List<Map<String, dynamic>>.from(res as List);
        if (mounted) {
          setState(() {
            _admins = list;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching admins: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب قائمة المشرفين: $e', style: GoogleFonts.cairo()),
            backgroundColor: AdminColors.emergency,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredAdmins = _admins.where((admin) {
      final name = (admin['full_name'] as String? ?? '').toLowerCase();
      final email = (admin['email'] as String? ?? '').toLowerCase();
      final phone = (admin['phone'] as String? ?? '').toLowerCase();
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. الهيدر الرئيسي
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
                        child: const Icon(Icons.admin_panel_settings_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'حوكمة وإدارة فريق المشرفين والمسؤولين 👥',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'التحكم المركزي في حسابات مسؤولي المنظومة، إنشاء المشرفين، تعديل البيانات، والحذف النهائي المشروط',
                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      showCreateAdminAccountDialog(
                        context,
                        onAdminCreated: () => _fetchAdmins(silent: true),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'إضافة مشرف جديد ➕',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'تحديث القائمة الآن',
                    icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                    onPressed: () => _fetchAdmins(),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 2. كروت المؤشرات السريعة (KPI Summary Cards)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'إجمالي المشرفين المعتمدين',
                  value: '${_admins.length}',
                  subtitle: 'حسابات إدارة نشطة ومفعلة',
                  icon: Icons.people_alt_rounded,
                  color: AdminColors.primaryDark,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildKpiCard(
                  title: 'مستوى حماية التشفير',
                  value: 'Bcrypt Blowfish',
                  subtitle: 'أعلى معايير تشفير كلمات المرور',
                  icon: Icons.lock_outline_rounded,
                  color: AdminColors.success,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildKpiCard(
                  title: 'قيد الأمان والحظر الذاتي',
                  value: 'مفعل وصارم 🛡️',
                  subtitle: 'منع حذف النفس وحظر حذف المشرف الأخير',
                  icon: Icons.security_rounded,
                  color: AdminColors.accentMint,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 3. شريط البحث والفلترة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: GoogleFonts.cairo(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم المشرف، البريد الإلكتروني، أو رقم الهاتف...',
                      hintStyle: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.primaryDark, size: 20),
                      filled: true,
                      fillColor: AdminColors.surfaceWhite,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AdminColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AdminColors.cardBorder),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: () => setState(() => _searchQuery = ''),
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: Text('مسح البحث', style: GoogleFonts.cairo(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 4. جدول عرض المشرفين
          if (_isLoading)
            const AdminTableSkeleton(rows: 4)
          else if (filteredAdmins.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AdminColors.cardBorder),
              ),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded, size: 48, color: AdminColors.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    'لا يوجد مشرفين يطابقون معايير البحث',
                    style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AdminColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DataTable(
                  horizontalMargin: 20,
                  columnSpacing: 24,
                  headingRowColor: WidgetStateProperty.all(AdminColors.surfaceWhite),
                  dataRowMinHeight: 65,
                  dataRowMaxHeight: 75,
                  columns: [
                    DataColumn(
                      label: Text('المشرف والاسم', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textPrimary)),
                    ),
                    DataColumn(
                      label: Text('البريد الإلكتروني', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textPrimary)),
                    ),
                    DataColumn(
                      label: Text('رقم الهاتف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textPrimary)),
                    ),
                    DataColumn(
                      label: Text('تاريخ الإنشاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textPrimary)),
                    ),
                    DataColumn(
                      label: Text('آخر تسجيل دخول', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textPrimary)),
                    ),
                    DataColumn(
                      label: Text('إجراءات الإدارة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textPrimary)),
                    ),
                  ],
                  rows: filteredAdmins.map((admin) {
                    final id = admin['id'] as String? ?? '';
                    final name = admin['full_name'] as String? ?? 'مشرف';
                    final email = admin['email'] as String? ?? 'لا يوجد';
                    final phone = admin['phone'] as String? ?? 'غير محدد';
                    final createdAt = admin['created_at'] as String?;
                    final lastSignInAt = admin['last_sign_in_at'] as String?;
                    final isSelf = _currentAdminId != null && _currentAdminId == id;

                    String createdStr = 'غير مسجل';
                    if (createdAt != null) {
                      try {
                        final dt = DateTime.parse(createdAt).toLocal();
                        createdStr = intl.DateFormat('yyyy/MM/dd').format(dt);
                      } catch (_) {}
                    }

                    String lastSignInStr = 'لم يسجل دخول بعد';
                    if (lastSignInAt != null) {
                      try {
                        final dt = DateTime.parse(lastSignInAt).toLocal();
                        lastSignInStr = intl.DateFormat('yyyy/MM/dd - hh:mm a').format(dt);
                      } catch (_) {}
                    }

                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isSelf ? AdminColors.accentMint.withValues(alpha: 0.25) : AdminColors.primaryDark.withValues(alpha: 0.12),
                                child: Icon(
                                  isSelf ? Icons.verified_user_rounded : Icons.person_rounded,
                                  color: isSelf ? AdminColors.primaryDark : AdminColors.textSecondary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textPrimary),
                                      ),
                                      if (isSelf) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AdminColors.accentMint.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text('حسابك الحالي 👤', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.primaryDark)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    'مشرف معتمد (ADMIN)',
                                    style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            email,
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textPrimary),
                          ),
                        ),
                        DataCell(
                          Text(
                            phone,
                            style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                          ),
                        ),
                        DataCell(
                          Text(
                            createdStr,
                            style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                          ),
                        ),
                        DataCell(
                          Text(
                            lastSignInStr,
                            style: GoogleFonts.cairo(fontSize: 11, color: lastSignInAt != null ? AdminColors.textPrimary : AdminColors.textSecondary),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // زر التعديل
                              IconButton(
                                tooltip: 'تعديل بيانات المشرف',
                                icon: const Icon(Icons.edit_rounded, color: AdminColors.primaryDark, size: 20),
                                onPressed: () => _showEditAdminDialog(admin),
                              ),
                              const SizedBox(width: 4),
                              // زر الحذف
                              IconButton(
                                tooltip: isSelf ? 'لا يمكنك حذف حسابك الحالي' : 'حذف المشرف نهائياً',
                                icon: Icon(
                                  Icons.delete_forever_rounded,
                                  color: isSelf ? Colors.grey.shade400 : AdminColors.emergency,
                                  size: 20,
                                ),
                                onPressed: isSelf ? null : () => _showDeleteAdminDialog(admin),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
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
                  title,
                  style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(fontSize: 10, color: AdminColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// نافذة تعديل بيانات المشرف
  void _showEditAdminDialog(Map<String, dynamic> admin) {
    final adminId = admin['id'] as String;
    final initialName = admin['full_name'] as String? ?? '';
    final initialEmail = admin['email'] as String? ?? '';
    final initialPhone = admin['phone'] as String? ?? '';

    final nameController = TextEditingController(text: initialName);
    final emailController = TextEditingController(text: initialEmail);
    final phoneController = TextEditingController(text: initialPhone);
    final passwordController = TextEditingController();

    bool obscurePassword = true;
    bool isSaving = false;
    String? emailError;
    Timer? debounce;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void checkEmailConflict(String email) {
            debounce?.cancel();
            if (email.trim().isEmpty || email.trim() == initialEmail) {
              setDialogState(() => emailError = null);
              return;
            }

            debounce = Timer(const Duration(milliseconds: 350), () async {
              try {
                final exists = await _client.rpc('admin_check_email_exists', params: {'p_email': email.trim()});
                if (exists == true) {
                  setDialogState(() {
                    emailError = 'هذا البريد مسجل بالفعل لمستخدم آخر بالمنظومة! ⚠️';
                  });
                } else {
                  setDialogState(() => emailError = null);
                }
              } catch (_) {}
            });
          }

          Future<void> submitUpdate() async {
            final name = nameController.text.trim();
            final email = emailController.text.trim();
            final phone = phoneController.text.trim();
            final pass = passwordController.text.trim();

            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('يرجى إدخال اسم المشرف', style: GoogleFonts.cairo()), backgroundColor: AdminColors.emergency),
              );
              return;
            }

            if (email.isEmpty || !email.contains('@')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('يرجى إدخال بريد إلكتروني صحيح', style: GoogleFonts.cairo()), backgroundColor: AdminColors.emergency),
              );
              return;
            }

            if (emailError != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(emailError!, style: GoogleFonts.cairo()), backgroundColor: AdminColors.emergency),
              );
              return;
            }

            if (pass.isNotEmpty && pass.length < 6) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('كلمة المرور يجب ألا تقل عن 6 أحرف', style: GoogleFonts.cairo()), backgroundColor: AdminColors.emergency),
              );
              return;
            }

            setDialogState(() => isSaving = true);
            final navigator = Navigator.of(dialogCtx);
            final messenger = ScaffoldMessenger.of(context);

            try {
              await _client.rpc('admin_update_admin_account', params: {
                'p_admin_id': adminId,
                'p_full_name': name,
                'p_phone': phone,
                'p_email': email,
                'p_new_password': pass.isEmpty ? null : pass,
                'p_caller_admin_id': _currentAdminId,
              });

              navigator.pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('تم تحديث بيانات المشرف بنجاح ✅', style: GoogleFonts.cairo()),
                  backgroundColor: AdminColors.success,
                ),
              );
              _fetchAdmins(silent: true);
            } catch (e) {
              setDialogState(() => isSaving = false);
              messenger.showSnackBar(
                SnackBar(
                  content: Text('فشل التحديث: $e', style: GoogleFonts.cairo()),
                  backgroundColor: AdminColors.emergency,
                ),
              );
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.manage_accounts_rounded, color: AdminColors.primaryDark),
                const SizedBox(width: 8),
                Text('تعديل بيانات المشرف ⚙️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الاسم الكامل للمشرف:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text('البريد الإلكتروني (تسجيل الدخول):', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: checkEmailConflict,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.email_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        errorText: emailError,
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text('رقم الهاتف:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text('تعيين كلمة مرور جديدة (اتركها فارغة إذا لم ترغب في التغيير):', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                        hintText: 'اترك الحقل فارغاً للإبقاء على كلمة السر الحالية',
                        hintStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
                child: Text('إلغاء', style: GoogleFonts.cairo()),
              ),
              ElevatedButton.icon(
                onPressed: isSaving ? null : submitUpdate,
                icon: isSaving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text('حفظ التعديلات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// نافذة تأكيد حذف المشرف نهائياً
  void _showDeleteAdminDialog(Map<String, dynamic> admin) {
    final adminId = admin['id'] as String;
    final name = admin['full_name'] as String? ?? 'المشرف';
    final email = admin['email'] as String? ?? '';

    bool isDeleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> confirmDelete() async {
            setDialogState(() => isDeleting = true);
            final navigator = Navigator.of(dialogCtx);
            final messenger = ScaffoldMessenger.of(context);

            try {
              await _client.rpc('admin_delete_admin_account', params: {
                'p_target_admin_id': adminId,
                'p_caller_admin_id': _currentAdminId,
              });

              navigator.pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('تم حذف حساب المشرف نهائياً بنجاح 🗑️', style: GoogleFonts.cairo()),
                  backgroundColor: AdminColors.success,
                ),
              );
              _fetchAdmins(silent: true);
            } catch (e) {
              setDialogState(() => isDeleting = false);
              messenger.showSnackBar(
                SnackBar(
                  content: Text('فشل الحذف: $e', style: GoogleFonts.cairo()),
                  backgroundColor: AdminColors.emergency,
                ),
              );
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AdminColors.emergency, size: 28),
                const SizedBox(width: 10),
                Text('تأكيد حذف المشرف نهائياً ⚠️', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: AdminColors.emergency)),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'هل أنت متأكد من رغبتك في حذف حساب المشرف التالي نهائياً من المنظومة؟',
                    style: GoogleFonts.cairo(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('👤 الاسم: $name', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('✉️ البريد: $email', style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '⚠️ تحذير: سيتم حذف بيانات المصادقة وصلاحيات الدخول بالكامل، ولن يتمكن هذا المشرف من الدخول إلى لوحة التحكم مجدداً.',
                    style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.emergency, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.of(dialogCtx).pop(),
                child: Text('إلغاء', style: GoogleFonts.cairo()),
              ),
              ElevatedButton.icon(
                onPressed: isDeleting ? null : confirmDelete,
                icon: isDeleting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_forever_rounded, size: 16),
                label: Text('تأكيد الحذف النهائي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.emergency,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
