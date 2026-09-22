import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_realtime_manager.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';
import 'package:doctor_admin/features/labs_governance/labs_governance_logic.dart';

class LabsGovernanceScreen extends StatefulWidget {
  const LabsGovernanceScreen({super.key});

  @override
  State<LabsGovernanceScreen> createState() => _LabsGovernanceScreenState();
}

class _LabsGovernanceScreenState extends State<LabsGovernanceScreen> {
  final _client = AdminSupabaseConfig.client;
  final _realtimeManager = AdminRealtimeManager();

  static List<Map<String, dynamic>>? _cachedLabs;

  bool _isLoading = true;
  List<Map<String, dynamic>> _labs = [];
  String _searchQuery = '';
  String _governorateFilter = 'الكل';
  int _selectedStatusTabIndex = 0;

  @override
  void initState() {
    super.initState();
    if (_cachedLabs != null && _cachedLabs!.isNotEmpty) {
      _labs = _cachedLabs!;
      _isLoading = false;
    }
    _fetchLabs(silent: _cachedLabs != null);
    _realtimeManager.addPartnerListener(_onRealtimePartner);
  }

  void _onRealtimePartner() {
    if (mounted) _fetchLabs(silent: true);
  }

  @override
  void dispose() {
    _realtimeManager.removePartnerListener(_onRealtimePartner);
    super.dispose();
  }

  List<Map<String, dynamic>> _parseLabs(dynamic res) {
    if (res is List) {
      return res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (res is Map && res['labs'] is List) {
      return (res['labs'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<void> _fetchLabs({bool silent = false}) async {
    if (!silent && _labs.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await _client.rpc('admin_list_labs');
      if (mounted) {
        final list = _parseLabs(res);
        setState(() {
          _labs = list;
          _cachedLabs = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleLabStatus(String labId, bool currentStatus) async {
    try {
      await _client.rpc('toggle_partner_status', params: {
        'p_partner_id': labId,
        'p_role': 'LAB',
        'p_new_status': !currentStatus,
      });
      await _fetchLabs(silent: true);
      AdminAuditService.log(
        actionType: !currentStatus ? 'تفعيل حساب معمل' : 'تجميد حساب معمل',
        targetType: 'LAB',
        targetId: labId,
        targetName: 'معمل $labId',
        details: {'is_approved': !currentStatus},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? 'تم تفعيل واعتماد المعمل بنجاح' : 'تم تجميد وإيقاف المعمل بنجاح'),
            backgroundColor: !currentStatus ? AdminColors.success : AdminColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  Future<void> _extendSubscription(String labId, int days, {String? notes}) async {
    try {
      await _client.rpc('renew_partner_subscription', params: {
        'p_partner_id': labId,
        'p_role': 'LAB',
        'p_days': days,
        'p_plan_name': 'باقة المعامل الاحترافية',
        'p_amount': 0,
      });
      AdminAuditService.log(
        actionType: 'تمديد اشتراك معمل',
        targetType: 'LAB',
        targetId: labId,
        targetName: 'معمل $labId',
        details: {'days': days, 'notes': notes ?? ''},
      );
      await _fetchLabs(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تمديد اشتراك المعمل لـ $days يوماً بنجاح'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء التمديد: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  void _showEditLabAccountDialog(Map<String, dynamic> lab) {
    final profile = lab['profiles'] as Map<String, dynamic>? ?? {};
    final labId = lab['id'] as String;
    final nameController = TextEditingController(text: (lab['name'] as String?) ?? (profile['full_name'] as String?) ?? '');
    final phoneController = TextEditingController(text: (profile['phone'] as String?) ?? '');
    final addressController = TextEditingController(text: (lab['address_text'] as String?) ?? '');
    final districtController = TextEditingController(text: (lab['district'] as String?) ?? '');
    final bioController = TextEditingController(text: (lab['bio'] as String?) ?? '');
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final initialGov = (lab['governorate'] as String?) ?? 'القاهرة';
    String selectedGov = kEgyptGovernorates.contains(initialGov) ? initialGov : kEgyptGovernorates.first;
    bool obscurePassword = true;
    bool isSaving = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final navigator = Navigator.of(ctx);
          final messenger = ScaffoldMessenger.of(this.context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            contentPadding: EdgeInsets.zero,
            actionsPadding: EdgeInsets.zero,
            title: Text(
              'تعديل بيانات وحساب المعمل',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: nameController,
                              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'اسم المعمل *',
                                labelStyle: GoogleFonts.cairo(fontSize: 12),
                                prefixIcon: const Icon(Icons.biotech_rounded, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم المعمل مطلوب' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: phoneController,
                              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'رقم الهاتف *',
                                labelStyle: GoogleFonts.cairo(fontSize: 12),
                                prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedGov,
                              style: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textPrimary, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'المحافظة',
                                labelStyle: GoogleFonts.cairo(fontSize: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              items: kEgyptGovernorates.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedGov = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: districtController,
                              style: GoogleFonts.cairo(fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'المنطقة / الحي',
                                labelStyle: GoogleFonts.cairo(fontSize: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'العنوان',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: bioController,
                        maxLines: 2,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'نبذة المعمل',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: emailController,
                              style: GoogleFonts.cairo(fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'بريد جديد (اختياري)',
                                labelStyle: GoogleFonts.cairo(fontSize: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              style: GoogleFonts.cairo(fontSize: 12.5),
                              decoration: InputDecoration(
                                labelText: 'كلمة مرور جديدة (اختياري)',
                                labelStyle: GoogleFonts.cairo(fontSize: 12),
                                suffixIcon: IconButton(
                                  icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                                  onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                helperText: 'اتركه فارغاً للإبقاء على الحالية',
                                helperStyle: GoogleFonts.cairo(fontSize: 10),
                              ),
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty && v.trim().length < 6) {
                                  return 'كلمة المرور يجب ألا تقل عن 6 أحرف';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: isSaving ? null : () => navigator.pop(),
                      child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.primaryDark,
                        foregroundColor: Colors.white,
                      ),
                      icon: isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(isSaving ? 'جارٍ الحفظ...' : 'حفظ التحديثات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setModalState(() => isSaving = true);
                              try {
                                final finalName = nameController.text.trim();
                                final rpcRes = await _client.rpc('admin_update_lab_account', params: {
                                  'p_lab_id': labId,
                                  'p_name': finalName,
                                  'p_phone': phoneController.text.trim(),
                                  'p_governorate': selectedGov,
                                  'p_district': districtController.text.trim(),
                                  'p_address_text': addressController.text.trim(),
                                  'p_bio': bioController.text.trim(),
                                  'p_email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                                  'p_new_password': passwordController.text.trim().isEmpty ? null : passwordController.text.trim(),
                                });
                                if (rpcRes != null && rpcRes is Map && rpcRes['success'] == false) {
                                  throw rpcRes['message'] ?? 'فشل تحديث البيانات';
                                }
                                await AdminAuditService.log(
                                  actionType: 'UPDATE_LAB_ACCOUNT',
                                  targetType: 'LAB',
                                  targetName: finalName,
                                  targetId: labId,
                                  details: {'lab_id': labId, 'name': finalName, 'governorate': selectedGov},
                                );
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('تم تحديث بيانات معمل $finalName بنجاح', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                                    backgroundColor: AdminColors.success,
                                  ),
                                );
                                _fetchLabs(silent: true);
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                messenger.showSnackBar(
                                  SnackBar(content: Text('خطأ: $e', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)), backgroundColor: AdminColors.emergency),
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showExtendSubscriptionDialog(String labId, String labName) {
    final current = _labs.firstWhere((p) => p['id'] == labId, orElse: () => {'subscription_expires_at': null});
    final currentExpiryStr = current['subscription_expires_at'] as String?;
    DateTime baseStartDate = DateTime.now();
    if (currentExpiryStr != null) {
      final parsed = DateTime.tryParse(currentExpiryStr)?.toLocal();
      if (parsed != null && parsed.isAfter(DateTime.now())) {
        baseStartDate = parsed;
      }
    }
    int selectedDays = 30;
    DateTime calculatedExpiryDate = baseStartDate.add(Duration(days: selectedDays));
    final customDaysCtrl = TextEditingController(text: '30');
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('تمديد اشتراك: $labName', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تاريخ الانتهاء الجديد: ${intl.DateFormat('yyyy/MM/dd').format(calculatedExpiryDate)}',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [14, 30, 60, 90, 180, 365].map((d) {
                      final selected = selectedDays == d;
                      return ChoiceChip(
                        label: Text('$d يوم', style: GoogleFonts.cairo(fontSize: 11)),
                        selected: selected,
                        selectedColor: AdminColors.primaryDark,
                        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                        onSelected: (_) {
                          setDialogState(() {
                            selectedDays = d;
                            customDaysCtrl.text = '$d';
                            calculatedExpiryDate = baseStartDate.add(Duration(days: d));
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: customDaysCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final parsed = int.tryParse(val.trim());
                      if (parsed != null && parsed > 0) {
                        setDialogState(() {
                          selectedDays = parsed;
                          calculatedExpiryDate = baseStartDate.add(Duration(days: parsed));
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'عدد الأيام',
                      labelStyle: GoogleFonts.cairo(fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة إدارية',
                      labelStyle: GoogleFonts.cairo(fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo())),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primaryDark, foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _extendSubscription(labId, selectedDays, notes: notesCtrl.text);
                },
                child: Text('تأكيد التمديد', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _inspectLabOps(Map<String, dynamic> lab) async {
    try {
      final res = await _client.rpc('admin_lab_ops_summary', params: {'p_lab_id': lab['id']});
      final ops = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (!opsSummaryIsSafe(ops)) {
        throw 'تم حجب تفاصيل نتائج المرضى حفاظاً على الخصوصية';
      }
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          final hours = ops['working_hours'];
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('تشغيل المعمل (بدون ملفات المرضى)', style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('نتائج نشطة: ${ops['results_active_count'] ?? 0}', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  Text('نتائج ملغاة (أرشيف): ${ops['results_cancelled_count'] ?? 0}', style: GoogleFonts.cairo()),
                  Text('مرضى هذا المعمل فقط (عدد أرقام): ${ops['unique_patients_count'] ?? 0}', style: GoogleFonts.cairo()),
                  Text('صور المعرض: ${ops['gallery_count'] ?? 0}', style: GoogleFonts.cairo()),
                  Text('مفتوح الآن: ${ops['is_open_now'] == true ? 'نعم' : 'لا'}', style: GoogleFonts.cairo()),
                  const SizedBox(height: 8),
                  Text('ساعات العمل:', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  Text(hours == null ? 'غير محددة' : hours.toString(), style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text(
                    'لا يعرض الأدمن أسماء مرضى المعامل الأخرى ولا ملفات النتائج. العدد فقط لمعمل محدد.',
                    style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.warning),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إغلاق', style: GoogleFonts.cairo())),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kpis = labKpiCounts(_labs);
    final filtered = _labs.where((lab) {
      return labMatchesFilters(
        lab: lab,
        searchQuery: _searchQuery,
        governorateFilter: _governorateFilter,
        statusTabIndex: _selectedStatusTabIndex,
      );
    }).toList();

    return SingleChildScrollView(
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
                        child: const Icon(Icons.biotech_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'مركز رقابة وحوكمة معامل التحاليل',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تجميد وتفعيل المعامل، تعديل الحساب، تمديد الاشتراك، ومتابعة عدد النتائج دون كشف ملفات المرضى',
                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primaryDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('تحديث القائمة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: _fetchLabs,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _kpi('إجمالي المعامل', kpis['total']!, 'مسجلة في المنظومة', Icons.biotech_rounded, AdminColors.primaryDark, const Color(0xFFF0FDF4), const Color(0xFFBBF7D0))),
              const SizedBox(width: 12),
              Expanded(child: _kpi('معتمدة ونشطة', kpis['active']!, 'ظاهرة للمرضى في الدليل', Icons.check_circle_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5), const Color(0xFFA7F3D0))),
              const SizedBox(width: 12),
              Expanded(child: _kpi('نتائج نشطة', kpis['results']!, 'عدد فقط بدون ملفات', Icons.assignment_rounded, const Color(0xFF0EA5E9), const Color(0xFFF0F9FF), const Color(0xFFBAE6FD))),
              const SizedBox(width: 12),
              Expanded(child: _kpi('مجمدة أو موقوفة', kpis['frozen']!, 'حسابات غير مفعلة حالياً', Icons.pause_circle_filled_rounded, const Color(0xFFEF4444), const Color(0xFFFEF2F2), const Color(0xFFFECACA))),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    style: GoogleFonts.cairo(fontSize: 13),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'بحث باسم المعمل أو المحافظة أو الهاتف...',
                      hintStyle: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.textSecondary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _governorateFilter,
                    style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    items: ['الكل', ...kEgyptGovernorates].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (val) => setState(() => _governorateFilter = val ?? 'الكل'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AdminModernTabBar(
            tabs: [
              AdminTabItem(label: 'الكل', icon: Icons.science_rounded, count: _labs.length),
              AdminTabItem(label: 'معتمدة ونشطة', icon: Icons.check_circle_rounded, count: kpis['active'], badgeColor: const Color(0xFF10B981)),
              AdminTabItem(label: 'مجمدة أو موقوفة', icon: Icons.pause_circle_filled_rounded, count: kpis['frozen'], badgeColor: const Color(0xFFEF4444)),
            ],
            selectedIndex: _selectedStatusTabIndex,
            onTabSelected: (idx) => setState(() => _selectedStatusTabIndex = idx),
          ),
          const SizedBox(height: 16),
          if (_isLoading && _labs.isEmpty)
            const AdminTableSkeleton(rows: 8)
          else if (filtered.isEmpty)
            AdminEmptyStateCard(
              title: _searchQuery.isNotEmpty ? 'لا توجد معامل مطابقة لبحث "$_searchQuery"' : 'لا توجد معامل في هذا القسم حالياً',
              description: 'اعتماد المعامل الجديدة يظهر من طلبات الانضمام، ثم تُدار من هنا مثل الأطباء والصيدليات.',
              icon: Icons.biotech_outlined,
              onRefresh: _fetchLabs,
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final lab = filtered[index];
                final profile = lab['profiles'] as Map<String, dynamic>? ?? {};
                final isApproved = labIsActive(lab);
                final sub = labSubscriptionBadge(lab);
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
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AdminColors.accentMintLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.biotech_rounded, color: AdminColors.primaryDark),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    lab['name'] ?? profile['full_name'] ?? 'معمل',
                                    style: GoogleFonts.cairo(fontSize: 14.5, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isApproved ? AdminColors.accentMintLight : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isApproved ? 'معتمد' : 'مجمد / موقوف',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      color: isApproved ? AdminColors.success : AdminColors.emergency,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(sub['label'] ?? '', style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary)),
                              ],
                            ),
                            Text(
                              '${lab['governorate'] ?? ''} - ${lab['district'] ?? ''} • ${profile['phone'] ?? 'بدون هاتف'}',
                              style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${lab['results_active_count'] ?? 0} نتيجة نشطة • ${lab['unique_patients_count'] ?? 0} مريض لهذا المعمل',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.manage_accounts_rounded, color: AdminColors.primaryDark, size: 20),
                            tooltip: 'تعديل بيانات وحساب المعمل',
                            onPressed: () => _showEditLabAccountDialog(lab),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_card_rounded, color: AdminColors.primaryDark, size: 20),
                            tooltip: 'تمديد اشتراك المعمل',
                            onPressed: () => _showExtendSubscriptionDialog(lab['id'] as String, lab['name']?.toString() ?? 'المعمل'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.assignment_outlined, color: AdminColors.primaryDark, size: 20),
                            tooltip: 'ملخص التشغيل بدون ملفات المرضى',
                            onPressed: () => _inspectLabOps(lab),
                          ),
                          IconButton(
                            icon: Icon(
                              isApproved ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                              color: isApproved ? AdminColors.warning : AdminColors.success,
                              size: 22,
                            ),
                            tooltip: isApproved ? 'تجميد المعمل' : 'تفعيل المعمل',
                            onPressed: () => _toggleLabStatus(lab['id'] as String, isApproved),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _kpi(String title, int count, String subtitle, IconData icon, Color color, Color bg, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textSecondary)),
                Text('$count', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w900, color: AdminColors.textPrimary)),
                Text(subtitle, style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
