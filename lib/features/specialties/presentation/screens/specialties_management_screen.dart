import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';
import 'package:doctor_admin/core/widgets/admin_shimmer.dart';
import 'package:doctor_admin/core/widgets/admin_modern_tab_bar.dart';
import 'package:doctor_admin/core/services/admin_audit_service.dart';

class SpecialtiesManagementScreen extends StatefulWidget {
  const SpecialtiesManagementScreen({super.key});

  @override
  State<SpecialtiesManagementScreen> createState() => _SpecialtiesManagementScreenState();
}

class _SpecialtiesManagementScreenState extends State<SpecialtiesManagementScreen> {
  final _client = AdminSupabaseConfig.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _specialties = [];
  String _searchQuery = '';
  String _selectedCategory = 'الكل';
  int _selectedStatusTab = 0; // 0: الكل, 1: نشط, 2: معطل

  @override
  void initState() {
    super.initState();
    _fetchSpecialties();
  }

  Future<void> _fetchSpecialties() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.rpc('admin_get_medical_specialties');
      if (mounted) {
        setState(() {
          _specialties = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching specialties: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل التخصصات: $e', style: GoogleFonts.cairo())),
        );
      }
    }
  }

  Future<void> _toggleSpecialtyActive(Map<String, dynamic> specialty) async {
    final newStatus = !(specialty['is_active'] as bool? ?? true);
    final id = specialty['id'] as String;
    final nameAr = specialty['name_ar'] as String;

    // Optimistic UI update
    setState(() {
      specialty['is_active'] = newStatus;
    });

    try {
      final res = await _client.rpc('admin_upsert_medical_specialty', params: {
        'p_id': id,
        'p_name_ar': nameAr,
        'p_name_en': specialty['name_en'] ?? '',
        'p_category': specialty['category'] ?? 'عام',
        'p_icon_code': specialty['icon_code'] ?? 'medical_services',
        'p_is_active': newStatus,
        'p_display_order': specialty['display_order'] ?? 0,
      });

      if (res != null && res['success'] == true) {
        await AdminAuditService.log(
          actionType: 'SPECIALTY_STATUS_TOGGLED',
          targetType: 'SPECIALTY',
          targetName: nameAr,
          targetId: id,
          details: {'name_ar': nameAr, 'is_active': newStatus},
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: newStatus ? AdminColors.success : Colors.grey.shade800,
              content: Text(
                newStatus ? 'تم تفعيل تخصص "$nameAr" بنجاح 🟢' : 'تم تعطيل/تجميد تخصص "$nameAr" ⏸️',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Revert
      setState(() {
        specialty['is_active'] = !newStatus;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تعديل الحالة: $e', style: GoogleFonts.cairo())),
        );
      }
    }
  }

  Future<void> _deleteSpecialty(Map<String, dynamic> specialty) async {
    final id = specialty['id'] as String;
    final nameAr = specialty['name_ar'] as String;
    final docCount = (specialty['doctor_count'] as num?)?.toInt() ?? 0;

    // إذا كان هناك أطباء مرتبطون، نظهر حوار تنبيه يمنع الحذف ويقترح التعطيل
    if (docCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_rounded, color: Colors.amber, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'سياسة حماية المنظومة 🛡️',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AdminColors.emergency, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'لا يمكن حذف تخصص "$nameAr" نهائياً!',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AdminColors.emergency, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'يوجد حالياً $docCount أطباء مسجلين بهذا التخصص في المنظومة. حذف التخصص سيؤدي إلى فقدان بياناتهم أو إرباك بحث المرضى وحجوزاتهم.',
                style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                '💡 الخيار الموصى به: تجميد/تعطيل التخصص بدلاً من حذفه، حتى لا يظهر لأي طبيب جديد في التسجيل، مع الحفاظ على سلامة الحسابات القائمة.',
                style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.primaryDark, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AdminColors.textSecondary)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _toggleSpecialtyActive(specialty);
              },
              icon: const Icon(Icons.pause_circle_filled_rounded, size: 18),
              label: Text('تجميد التخصص الآن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // إذا لم يكن هناك أطباء، نطلب تأكيد الحذف
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تأكيد حذف التخصص 🗑️', style: GoogleFonts.cairo(fontWeight: FontWeight.w900)),
        content: Text(
          'هل أنت متأكد من حذف تخصص "$nameAr"؟ (لا يوجد أي طبيب مرتبط به حالياً)',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AdminColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.emergency, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('تأكيد الحذف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await _client.rpc('admin_delete_medical_specialty', params: {
          'p_specialty_id': id,
        });

        if (res != null && res['success'] == true) {
          await AdminAuditService.log(
            actionType: 'SPECIALTY_DELETED',
            targetType: 'SPECIALTY',
            targetName: nameAr,
            targetId: id,
            details: {'name_ar': nameAr},
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: AdminColors.success, content: Text('تم حذف التخصص بنجاح', style: GoogleFonts.cairo())),
            );
            _fetchSpecialties();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: AdminColors.emergency, content: Text(res?['message'] ?? 'فشل الحذف', style: GoogleFonts.cairo())),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء الحذف: $e', style: GoogleFonts.cairo())),
          );
        }
      }
    }
  }

  void _showUpsertDialog([Map<String, dynamic>? item]) {
    final isEditing = item != null;
    final nameArController = TextEditingController(text: item?['name_ar'] ?? '');
    final nameEnController = TextEditingController(text: item?['name_en'] ?? '');
    final categoryController = TextEditingController(text: item?['category'] ?? 'عام');
    final iconController = TextEditingController(text: item?['icon_code'] ?? 'medical_services');
    final displayOrderController = TextEditingController(text: (item?['display_order'] ?? 0).toString());
    bool isActive = item?['is_active'] as bool? ?? true;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AdminColors.primaryDark.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                  color: AdminColors.primaryDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isEditing ? 'تعديل التخصص الطبي' : 'إضافة تخصص طبي جديد 🩺',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameArController,
                      style: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: 'اسم التخصص بالعربية *',
                        hintText: 'مثال: جراحة أورام ومناظير دقيقة',
                        prefixIcon: Icon(Icons.title_rounded, color: AdminColors.primaryDark),
                      ),
                      validator: (val) => (val == null || val.trim().isEmpty) ? 'اسم التخصص مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameEnController,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'اسم التخصص بالإنجليزية (اختياري)',
                        hintText: 'e.g. Surgical Oncology',
                        prefixIcon: Icon(Icons.translate_rounded, color: AdminColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: categoryController,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'تصنيف التخصص (مثال: جراحة / باطني / أسنان)',
                        prefixIcon: Icon(Icons.category_rounded, color: AdminColors.accentMint),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: displayOrderController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.cairo(fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'ترتيب الظهور (رقم)',
                              prefixIcon: Icon(Icons.sort_rounded, color: AdminColors.textMuted),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('تخصص نشط', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
                            value: isActive,
                            activeTrackColor: AdminColors.success,
                            onChanged: (val) => setDialogState(() => isActive = val),
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
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AdminColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final nameAr = nameArController.text.trim();
                final nameEn = nameEnController.text.trim();
                final category = categoryController.text.trim();
                final iconCode = iconController.text.trim();
                final order = int.tryParse(displayOrderController.text.trim()) ?? 0;

                try {
                  final res = await _client.rpc('admin_upsert_medical_specialty', params: {
                    'p_id': item?['id'],
                    'p_name_ar': nameAr,
                    'p_name_en': nameEn,
                    'p_category': category.isEmpty ? 'عام' : category,
                    'p_icon_code': iconCode.isEmpty ? 'medical_services' : iconCode,
                    'p_is_active': isActive,
                    'p_display_order': order,
                  });

                  if (res != null && res['success'] == true) {
                    await AdminAuditService.log(
                      actionType: isEditing ? 'SPECIALTY_UPDATED' : 'SPECIALTY_CREATED',
                      targetType: 'SPECIALTY',
                      targetName: nameAr,
                      targetId: item?['id'] ?? (res['data']?['id']?.toString()),
                      details: {'name_ar': nameAr, 'category': category},
                    );

                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AdminColors.success,
                          content: Text(res['message'] ?? 'تم الحفظ بنجاح', style: GoogleFonts.cairo()),
                        ),
                      );
                      _fetchSpecialties();
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AdminColors.emergency,
                          content: Text(res?['message'] ?? 'فشل حفظ التخصص', style: GoogleFonts.cairo()),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ أثناء الحفظ: $e', style: GoogleFonts.cairo())),
                    );
                  }
                }
              },
              child: Text(isEditing ? 'حفظ التعديلات' : 'إضافة التخصص', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filter logic
    final filtered = _specialties.where((s) {
      final nameAr = (s['name_ar'] as String? ?? '').toLowerCase();
      final nameEn = (s['name_en'] as String? ?? '').toLowerCase();
      final category = (s['category'] as String? ?? '').toLowerCase();
      final isActive = s['is_active'] as bool? ?? true;

      // Status tab
      if (_selectedStatusTab == 1 && !isActive) return false;
      if (_selectedStatusTab == 2 && isActive) return false;

      // Category filter
      if (_selectedCategory != 'الكل' && s['category'] != _selectedCategory) return false;

      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return nameAr.contains(q) || nameEn.contains(q) || category.contains(q);
      }

      return true;
    }).toList();

    // Stats
    final totalCount = _specialties.length;
    final activeCount = _specialties.where((s) => s['is_active'] == true).length;
    final inactiveCount = totalCount - activeCount;
    int totalDoctorsLinked = 0;
    for (final s in _specialties) {
      totalDoctorsLinked += (s['doctor_count'] as num?)?.toInt() ?? 0;
    }

    final categories = {'الكل', ..._specialties.map((s) => (s['category'] as String? ?? 'عام')).where((c) => c.isNotEmpty)};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
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
                        child: const Icon(Icons.health_and_safety_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'دليل وحوكمة التخصصات الطبية 🩺',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إدارة شاملة لكافة التخصصات الطبية مع حماية مشددة تمنع حذف أي تخصص مرتبط بأطباء مسجلين',
                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                    tooltip: 'تحديث البيانات',
                    onPressed: _fetchSpecialties,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showUpsertDialog(),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text('إضافة تخصص جديد ➕', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 2. KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'إجمالي التخصصات',
                  count: totalCount,
                  subtitle: 'تخصصات معتمدة بالنظام',
                  icon: Icons.list_alt_rounded,
                  color: AdminColors.primaryDark,
                  bgColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFBBF7D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'تخصصات نشطة ومتاحة 🟢',
                  count: activeCount,
                  subtitle: 'متاحة للأطباء والمرضى',
                  icon: Icons.check_circle_rounded,
                  color: AdminColors.success,
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'تخصصات مجمدة ⏸️',
                  count: inactiveCount,
                  subtitle: 'معطلة عن التسجيل الجديد',
                  icon: Icons.pause_circle_filled_rounded,
                  color: const Color(0xFF64748B),
                  bgColor: const Color(0xFFF8FAFC),
                  borderColor: const Color(0xFFE2E8F0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'أطباء مرتبطون بالتخصصات 👨‍⚕️',
                  count: totalDoctorsLinked,
                  subtitle: 'محميون من الحذف غير المقصود',
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF2563EB),
                  bgColor: const Color(0xFFEFF6FF),
                  borderColor: const Color(0xFFBFDBFE),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 3. Search & Filter Bar
          Row(
            children: [
              // Search field
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: TextField(
                    style: GoogleFonts.cairo(fontSize: 13),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: '🔍 ابحث باسم التخصص بالعربية أو الإنجليزية أو التصنيف...',
                      hintStyle: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.primaryDark),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Category dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c == 'الكل' ? 'كل التصنيفات 📁' : '📁 $c')))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedCategory = val ?? 'الكل'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status tabs
          AdminModernTabBar(
            tabs: [
              AdminTabItem(label: 'الكل', icon: Icons.all_inclusive_rounded, count: totalCount),
              AdminTabItem(label: 'نشط ومتاح 🟢', icon: Icons.check_circle_rounded, count: activeCount, badgeColor: const Color(0xFF10B981)),
              AdminTabItem(label: 'مجمد / معطل ⏸️', icon: Icons.pause_circle_filled_rounded, count: inactiveCount, badgeColor: const Color(0xFF64748B)),
            ],
            selectedIndex: _selectedStatusTab,
            onTabSelected: (idx) => setState(() => _selectedStatusTab = idx),
          ),

          // Active Filter Info Banner
          if (_selectedCategory != 'الكل' || _searchQuery.isNotEmpty || _selectedStatusTab != 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 18, color: AdminColors.primaryDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'إجمالي التخصصات: $totalCount | المعروض حالياً: ${filtered.length} تخصص'
                      '${_selectedCategory != 'الكل' ? ' • التصنيف: $_selectedCategory' : ''}'
                      '${_searchQuery.isNotEmpty ? ' • بحث: "$_searchQuery"' : ''}',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () {
                      setState(() {
                        _selectedCategory = 'الكل';
                        _searchQuery = '';
                        _selectedStatusTab = 0;
                      });
                    },
                    icon: const Icon(Icons.clear_all_rounded, size: 16, color: Colors.red),
                    label: Text('إلغاء الفلاتر', style: GoogleFonts.cairo(fontSize: 11.5, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 4. Specialties Table / List
          if (_isLoading)
            const AdminTableSkeleton(rows: 8)
          else if (filtered.isEmpty)
            AdminEmptyStateCard(
              title: _searchQuery.isNotEmpty ? 'لا توجد تخصصات مطابقة لبحث "$_searchQuery"' : 'لا توجد تخصصات في هذا القسم',
              description: 'يمكنك إضافة تخصص طبي جديد بضغطة زر وتعيين حالته فورياً.',
              icon: Icons.medical_services_outlined,
              onRefresh: _fetchSpecialties,
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = filtered[index];
                final nameAr = item['name_ar'] as String? ?? '';
                final nameEn = item['name_en'] as String? ?? '';
                final category = item['category'] as String? ?? 'عام';
                final docCount = (item['doctor_count'] as num?)?.toInt() ?? 0;
                final isActive = item['is_active'] as bool? ?? true;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AdminColors.cardBorderMint),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Leading Icon
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isActive
                            ? AdminColors.primaryDark.withValues(alpha: 0.1)
                            : Colors.grey.shade200,
                        child: Icon(
                          Icons.health_and_safety_rounded,
                          color: isActive ? AdminColors.primaryDark : Colors.grey,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Details
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  nameAr,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5,
                                    color: isActive ? AdminColors.textPrimary : Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Text(
                                    category,
                                    style: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (!isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'مجمد ⏸️',
                                      style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            if (nameEn.isNotEmpty)
                              Text(
                                nameEn,
                                style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textMuted),
                              ),
                          ],
                        ),
                      ),

                      // Doctor Count Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: docCount > 0 ? AdminColors.accentMintLight : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: docCount > 0 ? AdminColors.cardBorderMint : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_alt_rounded,
                              size: 14,
                              color: docCount > 0 ? AdminColors.success : AdminColors.textMuted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              docCount > 0 ? '$docCount طبيب مسجل 👨‍⚕️' : 'لا يوجد أطباء',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: docCount > 0 ? AdminColors.success : AdminColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Active toggle switch
                      Tooltip(
                        message: isActive ? 'تجميد التخصص' : 'تفعيل التخصص',
                        child: Switch(
                          value: isActive,
                          activeTrackColor: AdminColors.success,
                          onChanged: (_) => _toggleSpecialtyActive(item),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Edit button
                      IconButton(
                        icon: const Icon(Icons.edit_note_rounded, color: AdminColors.primaryDark, size: 22),
                        tooltip: 'تعديل التخصص',
                        onPressed: () => _showUpsertDialog(item),
                      ),

                      // Delete button (Protected by Guard Policy)
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: docCount > 0 ? Colors.grey.shade400 : AdminColors.emergency,
                          size: 20,
                        ),
                        tooltip: docCount > 0 ? 'محمي من الحذف لوجود $docCount طبيب مسجل' : 'حذف التخصص',
                        onPressed: () => _deleteSpecialty(item),
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

  Widget _buildKpiCard({
    required String title,
    required int count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
