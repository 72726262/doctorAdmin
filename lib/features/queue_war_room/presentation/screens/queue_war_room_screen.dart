import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doctor_admin/core/app_colors.dart';
import 'package:doctor_admin/core/supabase_config.dart';

class QueueWarRoomScreen extends StatefulWidget {
  const QueueWarRoomScreen({super.key});

  @override
  State<QueueWarRoomScreen> createState() => _QueueWarRoomScreenState();
}

class _QueueWarRoomScreenState extends State<QueueWarRoomScreen> {
  final _client = AdminSupabaseConfig.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _liveBranches = [];
  String _selectedGovernorate = 'الكل';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchLiveQueues();
  }

  Future<void> _fetchLiveQueues() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch all branches with doctor and profile details
      final branchesRes = await _client.from('branches').select('''
        id,
        doctor_id,
        name,
        governorate,
        address_text,
        max_daily_capacity,
        booking_window_days,
        is_queue_active,
        is_booking_stopped_today,
        doctors (
          id,
          specialty,
          rating_avg,
          rating_count,
          subscription_status,
          profiles (
            full_name,
            phone,
            avatar_url
          )
        )
      ''').order('name', ascending: true);

      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      // 2. Fetch today's tickets for queue stats
      final ticketsRes = await _client
          .from('tickets')
          .select('id, branch_id, ticket_number, status')
          .eq('booking_date', todayStr);

      final ticketsList = List<Map<String, dynamic>>.from(ticketsRes as List);

      final List<Map<String, dynamic>> enriched = [];

      for (final b in (branchesRes as List)) {
        final branchId = b['id'];
        final branchTickets = ticketsList.where((t) => t['branch_id'] == branchId).toList();

        final waitingTickets = branchTickets.where((t) => t['status'] == 'WAITING' || t['status'] == 'BOOKED').toList();
        final inSessionTickets = branchTickets.where((t) => t['status'] == 'IN_SESSION' || t['status'] == 'CALLED').toList();
        final completedTickets = branchTickets.where((t) => t['status'] == 'COMPLETED').toList();

        int currentNumber = 0;
        if (inSessionTickets.isNotEmpty) {
          currentNumber = inSessionTickets.last['ticket_number'] as int? ?? 0;
        } else if (completedTickets.isNotEmpty) {
          currentNumber = completedTickets.last['ticket_number'] as int? ?? 0;
        }

        final docData = b['doctors'] as Map<String, dynamic>?;
        final profileData = docData?['profiles'] as Map<String, dynamic>?;

        enriched.add({
          'id': branchId,
          'doctor_id': b['doctor_id'],
          'branch_name': b['name'] ?? 'الفرع الرئيسي',
          'governorate': b['governorate'] ?? 'القاهرة',
          'address_text': b['address_text'] ?? '',
          'doctor_name': profileData?['full_name'] ?? 'طبيب المنظومة',
          'doctor_phone': profileData?['phone'] ?? '',
          'specialty': docData?['specialty'] ?? 'طب عام',
          'avatar_url': profileData?['avatar_url'] ?? '',
          'rating_avg': docData?['rating_avg'] ?? 4.9,
          'is_queue_active': b['is_queue_active'] ?? false,
          'is_booking_stopped_today': b['is_booking_stopped_today'] ?? false,
          'max_daily_capacity': b['max_daily_capacity'] ?? 40,
          'current_ticket': currentNumber,
          'waiting_count': waitingTickets.length,
          'completed_count': completedTickets.length,
          'total_today': branchTickets.length,
          'is_overcrowded': waitingTickets.length > 12,
        });
      }

      if (mounted) {
        setState(() {
          _liveBranches = enriched;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleBranchQueue(String branchId, bool currentStatus) async {
    try {
      await _client
          .from('branches')
          .update({'is_queue_active': !currentStatus})
          .eq('id', branchId);

      _fetchLiveQueues();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? '🟢 تم فتح وتفعيل طابور العيادة' : '⏸️ تم إيقاف طابور العيادة مؤقتاً'),
            backgroundColor: !currentStatus ? AdminColors.success : AdminColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: AdminColors.emergency),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter by governorate & search
    final filtered = _liveBranches.where((b) {
      final matchGov = _selectedGovernorate == 'الكل' || b['governorate'] == _selectedGovernorate;
      final matchSearch = _searchQuery.isEmpty ||
          b['branch_name'].toString().contains(_searchQuery) ||
          b['doctor_name'].toString().contains(_searchQuery) ||
          b['specialty'].toString().contains(_searchQuery);
      return matchGov && matchSearch;
    }).toList();

    // Stats
    final totalActiveQueues = _liveBranches.where((b) => b['is_queue_active'] == true).length;
    final totalWaitingPatients = _liveBranches.fold<int>(0, (sum, b) => sum + (b['waiting_count'] as int));
    final overcrowdedCount = _liveBranches.where((b) => b['is_overcrowded'] == true).length;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with Live Badge & Refresh
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
                          color: AdminColors.emergency.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.radar_rounded, color: AdminColors.emergency, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'غرفة العمليات ورادار الطوابير اللحظي (Live War Room)',
                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'مراقبة فورية ومباشرة لكافة طوابير العيادات، التذاكر الحالية، وحالات التكدس في محافظات مصر',
                    style: GoogleFonts.cairo(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AdminColors.accentMintLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AdminColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, color: AdminColors.success, size: 8),
                        const SizedBox(width: 6),
                        Text(
                          'تحديث لحظي نشط 🟢',
                          style: GoogleFonts.cairo(color: AdminColors.success, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'تحديث البيانات الآن',
                    icon: const Icon(Icons.refresh_rounded, color: AdminColors.primaryDark),
                    onPressed: _fetchLiveQueues,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // War Room KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildWarRoomKpi(
                  'العيادات ذات الطوابير النشطة',
                  '$totalActiveQueues عيادة',
                  Icons.storefront_rounded,
                  AdminColors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildWarRoomKpi(
                  'إجمالي المنتظرين في الطوابير',
                  '$totalWaitingPatients مريض',
                  Icons.groups_rounded,
                  AdminColors.accentCyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildWarRoomKpi(
                  'تنبيهات التكدس والازدحام',
                  '$overcrowdedCount عيادة',
                  Icons.warning_amber_rounded,
                  overcrowdedCount > 0 ? AdminColors.emergency : AdminColors.success,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Filters Bar
          Row(
            children: [
              // Search Input
              Expanded(
                child: TextField(
                  style: GoogleFonts.cairo(fontSize: 13),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'بحث باسم الطبيب، الفرع، أو التخصص...',
                    hintStyle: GoogleFonts.cairo(fontSize: 13, color: AdminColors.textSecondary),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.textSecondary),
                    filled: true,
                    fillColor: AdminColors.surfaceWhite,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AdminColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AdminColors.cardBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Governorate Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AdminColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AdminColors.cardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGovernorate,
                    style: GoogleFonts.cairo(color: AdminColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    items: ['الكل', 'القاهرة', 'الجيزة', 'الإسكندرية', 'الدقهلية', 'الغربية'].map((gov) {
                      return DropdownMenuItem(value: gov, child: Text(gov));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedGovernorate = val ?? 'الكل'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Live Branches Cards Grid / List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.primaryDark))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.radar_rounded, size: 56, color: AdminColors.textSecondary),
                            const SizedBox(height: 12),
                            Text('لا توجد طوابير عيادات مطابقة للبحث', style: GoogleFonts.cairo(fontSize: 15, color: AdminColors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final branch = filtered[index];
                          final isActive = branch['is_queue_active'] as bool;
                          final isOvercrowded = branch['is_overcrowded'] as bool;

                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AdminColors.surfaceWhite,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isOvercrowded
                                    ? AdminColors.emergency.withValues(alpha: 0.5)
                                    : isActive
                                        ? AdminColors.cardBorderMint
                                        : AdminColors.cardBorder,
                                width: isOvercrowded ? 1.5 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Doctor Avatar / Status
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: AdminColors.primaryDark.withValues(alpha: 0.1),
                                  backgroundImage: branch['avatar_url'] != '' ? NetworkImage(branch['avatar_url']) : null,
                                  child: branch['avatar_url'] == ''
                                      ? const Icon(Icons.person_rounded, color: AdminColors.primaryDark)
                                      : null,
                                ),
                                const SizedBox(width: 14),

                                // Doctor & Branch Info
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            branch['doctor_name'],
                                            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AdminColors.primaryDark.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              branch['governorate'],
                                              style: GoogleFonts.cairo(fontSize: 11, color: AdminColors.primaryDark, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        branch['specialty'],
                                        style: GoogleFonts.cairo(fontSize: 12.5, color: AdminColors.accentCyan, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '📍 ${branch['branch_name']} - ${branch['address_text']}',
                                        style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // Live Ticket Radar Box
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AdminColors.primaryDark.withValues(alpha: 0.06)
                                        : Colors.grey.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'الكشف الحالي',
                                        style: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        isActive ? '#${branch['current_ticket']}' : 'متوقف',
                                        style: GoogleFonts.cairo(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: isActive ? AdminColors.primaryDark : AdminColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Waiting Patients Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isOvercrowded
                                        ? AdminColors.emergency.withValues(alpha: 0.12)
                                        : AdminColors.accentMint.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'في الانتظار',
                                        style: GoogleFonts.cairo(fontSize: 10.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '${branch['waiting_count']} مريض',
                                        style: GoogleFonts.cairo(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: isOvercrowded ? AdminColors.emergency : AdminColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Action Switch
                                Column(
                                  children: [
                                    Switch(
                                      value: isActive,
                                      activeTrackColor: AdminColors.success,
                                      onChanged: (val) => _toggleBranchQueue(branch['id'], isActive),
                                    ),
                                    Text(
                                      isActive ? 'الطابور نشط' : 'الطابور معطل',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? AdminColors.success : AdminColors.textSecondary,
                                      ),
                                    ),
                                  ],
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

  Widget _buildWarRoomKpi(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.cardBorderMint),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.cairo(fontSize: 11.5, color: AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
