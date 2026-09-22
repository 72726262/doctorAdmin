import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_admin/features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'package:doctor_admin/features/labs_governance/presentation/screens/labs_governance_screen.dart';

void main() {
  test('admin dashboard and labs governance screens construct', () {
    expect(const AdminDashboardScreen(), isA<AdminDashboardScreen>());
    expect(const LabsGovernanceScreen(), isA<LabsGovernanceScreen>());
  });
}
