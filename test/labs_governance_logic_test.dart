import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_admin/features/labs_governance/labs_governance_logic.dart';
import 'package:doctor_admin/features/labs_governance/presentation/screens/labs_governance_screen.dart';

void main() {
  Map<String, dynamic> lab({
    String name = 'معمل الشفاء',
    String gov = 'أسوان',
    String district = 'أسوان',
    String phone = '01001112233',
    bool approved = true,
    String status = 'ACTIVE',
    int results = 3,
  }) {
    return {
      'name': name,
      'governorate': gov,
      'district': district,
      'subscription_status': status,
      'results_active_count': results,
      'profiles': {
        'full_name': name,
        'phone': phone,
        'is_approved': approved,
      },
    };
  }

  test('governorate allowlist stays at current 27 without expansion', () {
    expect(kEgyptGovernorates, hasLength(27));
    expect(kEgyptGovernorates, contains('أسوان'));
    expect(kEgyptGovernorates, isNot(contains('المريخ')));
  });

  test('active lab requires approval and non-frozen subscription', () {
    expect(labIsActive(lab()), isTrue);
    expect(labIsActive(lab(approved: false)), isFalse);
    expect(labIsActive(lab(status: 'SUSPENDED')), isFalse);
    expect(labIsActive(lab(status: 'FROZEN')), isFalse);
  });

  test('search matches name, governorate, district, or phone', () {
    final row = lab();
    expect(
      labMatchesFilters(lab: row, searchQuery: 'الشفاء', governorateFilter: 'الكل', statusTabIndex: 0),
      isTrue,
    );
    expect(
      labMatchesFilters(lab: row, searchQuery: '0100', governorateFilter: 'الكل', statusTabIndex: 0),
      isTrue,
    );
    expect(
      labMatchesFilters(lab: row, searchQuery: 'صيدلية', governorateFilter: 'الكل', statusTabIndex: 0),
      isFalse,
    );
    expect(
      labMatchesFilters(lab: row, searchQuery: '', governorateFilter: 'القاهرة', statusTabIndex: 0),
      isFalse,
    );
    expect(
      labMatchesFilters(lab: row, searchQuery: '', governorateFilter: 'أسوان', statusTabIndex: 1),
      isTrue,
    );
    expect(
      labMatchesFilters(lab: lab(approved: false), searchQuery: '', governorateFilter: 'الكل', statusTabIndex: 1),
      isFalse,
    );
    expect(
      labMatchesFilters(lab: lab(approved: false), searchQuery: '', governorateFilter: 'الكل', statusTabIndex: 2),
      isTrue,
    );
  });

  test('KPI counts split active, frozen, and result totals', () {
    final kpis = labKpiCounts([
      lab(results: 2),
      lab(name: 'معمل ب', approved: false, results: 4),
      lab(name: 'معمل ج', status: 'SUSPENDED', results: 1),
    ]);
    expect(kpis['total'], 3);
    expect(kpis['active'], 1);
    expect(kpis['frozen'], 2);
    expect(kpis['results'], 7);
  });

  test('subscription badge labels freeze vs active vs expired', () {
    expect(labSubscriptionBadge(lab(status: 'SUSPENDED'))['label'], 'مجمد / موقوف');
    final soon = DateTime(2026, 9, 25);
    expect(
      labSubscriptionBadge({
        ...lab(),
        'subscription_expires_at': DateTime(2026, 9, 28).toIso8601String(),
      }, now: soon)['label'],
      contains('ينتهي'),
    );
    expect(
      labSubscriptionBadge({
        ...lab(),
        'subscription_expires_at': DateTime(2026, 9, 20).toIso8601String(),
      }, now: soon)['label'],
      'منتهي',
    );
  });

  test('ops summary privacy lock rejects patient result dumps', () {
    expect(
      opsSummaryIsSafe({
        'results_active_count': 2,
        'unique_patients_count': 2,
        'gallery_count': 1,
      }),
      isTrue,
    );
    expect(
      opsSummaryIsSafe({
        'file_path': 'lab_results/x/secret.pdf',
        'patient_name': 'أحمد',
      }),
      isFalse,
    );
  });

  test('labs tab is inserted after pharmacies in the admin shell', () {
    final titles = dashboardTabTitlesWithLabs([
      'نظرة عامة ومؤشرات المنصة',
      'غرفة العمليات ورادار الطوابير اللحظي',
      'رقابة العيادات المتخلفة والإنذارات ⚠️',
      'حوكمة وإدارة الأطباء والعيادات',
      'إدارة تقييمات الأطباء والأعلى تقييماً ⭐',
      'دليل وحوكمة التخصصات الطبية 🩺',
      'رقابة الصيدليات وتداول الروشتات',
      'طلبات الاعتماد والانضمام الجديدة',
    ]);
    expect(titles[6], contains('صيدليات'));
    expect(titles[7], contains('معامل'));
    expect(titles[8], contains('الاعتماد'));
    expect(dashboardTabTitlesWithLabs(titles), hasLength(titles.length));
  });

  test('LabsGovernanceScreen can be constructed', () {
    const widget = LabsGovernanceScreen();
    expect(widget, isA<LabsGovernanceScreen>());
  });
}
