import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

enum EmailCheckStatus { idle, checking, available, taken, invalidFormat }

/// نافذة حوار لإنشاء حساب أدمن/مسؤول جديد مع التحقق اللحظي التفاعلي من توفر البريد الإلكتروني
void showCreateAdminAccountDialog(BuildContext context, {VoidCallback? onAdminCreated}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CreateAdminDialogContent(onAdminCreated: onAdminCreated),
  );
}

class _CreateAdminDialogContent extends StatefulWidget {
  final VoidCallback? onAdminCreated;
  const _CreateAdminDialogContent({this.onAdminCreated});

  @override
  State<_CreateAdminDialogContent> createState() => _CreateAdminDialogContentState();
}

class _CreateAdminDialogContentState extends State<_CreateAdminDialogContent> {
  final _client = AdminSupabaseConfig.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController(text: 'مشرف لوحة التحكم');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSaving = false;

  Timer? _debounceTimer;
  EmailCheckStatus _emailStatus = EmailCheckStatus.idle;
  String? _emailStatusMessage;

  final _emailRegex = RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onEmailChanged(String value) {
    _debounceTimer?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _emailStatus = EmailCheckStatus.idle;
        _emailStatusMessage = null;
      });
      return;
    }

    if (!_emailRegex.hasMatch(trimmed)) {
      setState(() {
        _emailStatus = EmailCheckStatus.invalidFormat;
        _emailStatusMessage = 'صيغة البريد الإلكتروني غير مكتملة';
      });
      return;
    }

    setState(() {
      _emailStatus = EmailCheckStatus.checking;
      _emailStatusMessage = 'جارٍ التحقق من توفر البريد الإلكتروني في السيرفر...';
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final res = await _client.rpc('admin_check_email_exists', params: {
          'p_email': trimmed,
        });

        if (!mounted) return;

        final bool exists = res == true;
        setState(() {
          if (exists) {
            _emailStatus = EmailCheckStatus.taken;
            _emailStatusMessage = '⚠️ هذا البريد الإلكتروني مسجل بالفعل لمستخدم آخر بالمنظومة';
          } else {
            _emailStatus = EmailCheckStatus.available;
            _emailStatusMessage = '✅ هذا البريد متاح وجاهز للاستخدام كأدمن جديد';
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _emailStatus = EmailCheckStatus.idle;
          _emailStatusMessage = null;
        });
      }
    });
  }

  Future<void> _submitCreateAdmin() async {
    if (!_formKey.currentState!.validate()) return;

    if (_emailStatus == EmailCheckStatus.taken) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تغيير البريد الإلكتروني لأنه مسجل بالفعل لمستخدم آخر'),
          backgroundColor: AdminColors.emergency,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final fullName = _nameController.text.trim();
      final phone = _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();

      final res = await _client.rpc('admin_create_admin_account', params: {
        'p_email': email,
        'p_password': password,
        'p_full_name': fullName,
        'p_phone': phone,
      });

      if (res != null && res is Map && res['success'] == false) {
        throw res['message'] ?? 'فشل إنشاء حساب المشرف';
      }

      await AdminAuditService.log(
        actionType: 'إنشاء حساب أدمن جديد',
        targetType: 'ADMIN',
        targetName: fullName,
        details: {
          'email': email,
          'phone': phone,
        },
      );

      navigator.pop();
      widget.onAdminCreated?.call();

      messenger.showSnackBar(
        SnackBar(
          content: Text('🎉 تم إنشاء حساب الأدمن الجديد ($fullName) بنجاح ويمكنه تسجيل الدخول فوراً', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          backgroundColor: AdminColors.success,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('خطأ: $e', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            backgroundColor: AdminColors.emergency,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_isSaving && _emailStatus != EmailCheckStatus.taken && _emailStatus != EmailCheckStatus.checking;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 580,
        decoration: BoxDecoration(
          color: AdminColors.surfaceWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
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
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إنشاء حساب مسؤول / أدمن جديد 🛡️',
                            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          Text(
                            'إضافة مستخدم بصلاحيات المشرف العام للتحكم بالمنظومة',
                            style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Notice banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AdminColors.primaryDark, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '💡 يتم إنشاء الحساب بصلاحية ADMIN كاملة ومباشرة، مع فحص لحظي لعدم تكرار البريد وتشفير فوري لكلمة المرور.',
                                style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.primaryDark, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'اسم المشرف / الأدمن *',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          prefixIcon: const Icon(Icons.person_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                      ),
                      const SizedBox(height: 16),

                      // Email Field with Live Checking
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        onChanged: _onEmailChanged,
                        decoration: InputDecoration(
                          labelText: 'البريد الإلكتروني للأدمن *',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          hintText: 'admin2@shefaa.com',
                          hintStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade400),
                          prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                          suffixIcon: _buildEmailSuffix(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: _emailStatus == EmailCheckStatus.taken
                                  ? AdminColors.emergency
                                  : _emailStatus == EmailCheckStatus.available
                                      ? AdminColors.success
                                      : Colors.grey.shade300,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'البريد الإلكتروني مطلوب';
                          if (!_emailRegex.hasMatch(v.trim())) return 'صيغة البريد الإلكتروني غير صحيحة';
                          if (_emailStatus == EmailCheckStatus.taken) return 'البريد الإلكتروني مسجل بالفعل لمستخدم آخر';
                          return null;
                        },
                      ),

                      // Live email status feedback banner below field
                      if (_emailStatusMessage != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (_emailStatus == EmailCheckStatus.checking)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                              )
                            else if (_emailStatus == EmailCheckStatus.taken)
                              const Icon(Icons.cancel_rounded, color: AdminColors.emergency, size: 15)
                            else if (_emailStatus == EmailCheckStatus.available)
                              const Icon(Icons.check_circle_rounded, color: AdminColors.success, size: 15),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _emailStatusMessage!,
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: _emailStatus == EmailCheckStatus.taken
                                      ? AdminColors.emergency
                                      : _emailStatus == EmailCheckStatus.available
                                          ? AdminColors.success
                                          : AdminColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور *',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          hintText: 'يجب ألا تقل عن 6 خانات',
                          hintStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade400),
                          prefixIcon: const Icon(Icons.password_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'كلمة المرور مطلوبة';
                          if (v.trim().length < 6) return 'كلمة المرور يجب ألا تقل عن 6 أحرف';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Phone Field (Optional)
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف (اختياري)',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          hintText: 'اتركه فارغاً للتوليد التلقائي لرقم إداري',
                          hintStyle: GoogleFonts.cairo(fontSize: 11.5, color: Colors.grey.shade400),
                          prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: AdminColors.backgroundCanvas,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: Text('إلغاء', style: GoogleFonts.cairo(color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'جارٍ الإنشاء...' : 'إنشاء حساب الأدمن 🚀',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: canSubmit ? _submitCreateAdmin : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildEmailSuffix() {
    switch (_emailStatus) {
      case EmailCheckStatus.checking:
        return const Padding(
          padding: EdgeInsets.all(12.0),
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case EmailCheckStatus.taken:
        return const Icon(Icons.cancel_rounded, color: AdminColors.emergency);
      case EmailCheckStatus.available:
        return const Icon(Icons.check_circle_rounded, color: AdminColors.success);
      default:
        return null;
    }
  }
}
