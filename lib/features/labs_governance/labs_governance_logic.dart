// Pure helpers for admin labs governance. No Flutter / network.

const kEgyptGovernorates = [
  'القاهرة',
  'الجيزة',
  'الإسكندرية',
  'الدقهلية',
  'الغربية',
  'الشرقية',
  'المنوفية',
  'البحيرة',
  'كفر الشيخ',
  'دمياط',
  'بورسعيد',
  'الإسماعيلية',
  'السويس',
  'القليوبية',
  'بني سويف',
  'الفيوم',
  'المنيا',
  'أسيوط',
  'سوهاج',
  'قنا',
  'الأقصر',
  'أسوان',
  'البحر الأحمر',
  'الوادي الجديد',
  'مطروح',
  'شمال سيناء',
  'جنوب سيناء',
];

bool labIsActive(Map<String, dynamic> lab) {
  final profile = lab['profiles'] as Map<String, dynamic>? ?? {};
  final status = (lab['subscription_status'] ?? '').toString().toUpperCase();
  return profile['is_approved'] == true && status != 'SUSPENDED' && status != 'FROZEN';
}

bool labMatchesFilters({
  required Map<String, dynamic> lab,
  required String searchQuery,
  required String governorateFilter,
  required int statusTabIndex,
}) {
  final profile = lab['profiles'] as Map<String, dynamic>? ?? {};
  final name = lab['name']?.toString() ?? profile['full_name']?.toString() ?? '';
  final gov = lab['governorate']?.toString() ?? profile['governorate']?.toString() ?? '';
  final phone = profile['phone']?.toString() ?? '';
  final district = lab['district']?.toString() ?? '';
  final active = labIsActive(lab);

  final matchGov = governorateFilter == 'الكل' || gov == governorateFilter;
  var matchStatus = true;
  if (statusTabIndex == 1) {
    matchStatus = active;
  } else if (statusTabIndex == 2) {
    matchStatus = !active;
  }

  final q = searchQuery.trim();
  final matchSearch = q.isEmpty ||
      name.contains(q) ||
      gov.contains(q) ||
      district.contains(q) ||
      phone.contains(q);

  return matchGov && matchStatus && matchSearch;
}

Map<String, int> labKpiCounts(List<Map<String, dynamic>> labs) {
  var active = 0;
  var frozen = 0;
  var results = 0;
  for (final lab in labs) {
    if (labIsActive(lab)) {
      active++;
    } else {
      frozen++;
    }
    results += _asInt(lab['results_active_count']);
  }
  return {
    'total': labs.length,
    'active': active,
    'frozen': frozen,
    'results': results,
  };
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, String> labSubscriptionBadge(Map<String, dynamic> lab, {DateTime? now}) {
  final status = (lab['subscription_status'] as String? ?? 'INACTIVE').toUpperCase();
  if (status == 'SUSPENDED' || status == 'FROZEN') {
    return {'status': status, 'label': 'مجمد / موقوف'};
  }
  final expiresAtStr = lab['subscription_expires_at'] as String?;
  if (expiresAtStr == null || expiresAtStr.isEmpty) {
    return {'status': status, 'label': 'غير محدد'};
  }
  final expiry = DateTime.tryParse(expiresAtStr);
  if (expiry == null) {
    return {'status': status, 'label': 'غير محدد'};
  }
  final clock = now ?? DateTime.now();
  final days = expiry.difference(clock).inDays;
  if (days < 0) {
    return {'status': status, 'label': 'منتهي'};
  }
  if (days <= 10) {
    return {'status': status, 'label': 'ينتهي خلال $days يوم'};
  }
  return {'status': status, 'label': 'ساري'};
}

bool opsSummaryIsSafe(Map<String, dynamic> ops) {
  const bannedKeys = {
    'file_path',
    'patient_name',
    'patient_phone',
    'patient_phone_norm',
    'patient_id',
  };

  bool walk(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (bannedKeys.contains(entry.key.toString())) return false;
        if (!walk(entry.value)) return false;
      }
      return true;
    }
    if (value is List) {
      return value.every(walk);
    }
    if (value is String) {
      final lower = value.toLowerCase();
      return !lower.contains('lab_results/') && !lower.endsWith('.pdf');
    }
    return true;
  }

  return walk(ops);
}

List<String> dashboardTabTitlesWithLabs(List<String> current) {
  if (current.any((t) => t.contains('معامل'))) {
    return List<String>.from(current);
  }
  final next = List<String>.from(current);
  final insertAt = next.indexWhere((t) => t.contains('صيدليات'));
  final title = 'رقابة وحوكمة معامل التحاليل';
  if (insertAt >= 0 && insertAt + 1 <= next.length) {
    next.insert(insertAt + 1, title);
  } else {
    next.add(title);
  }
  return next;
}
