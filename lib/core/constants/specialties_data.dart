import 'package:flutter/material.dart';

/// كائن يمثل بيانات التخصص الطبي
class SpecialtyInfo {
  final String id;
  final String nameAr;
  final String nameEn;
  final String category;
  final IconData icon;

  const SpecialtyInfo({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.category,
    required this.icon,
  });
}

/// القائمة الموحدة والشاملة لكافة التخصصات الطبية في مصر
class SpecialtiesData {
  SpecialtiesData._();

  static const List<SpecialtyInfo> all = [
    SpecialtyInfo(
      id: 'internal_medicine',
      nameAr: 'باطنة عامة',
      nameEn: 'Internal Medicine',
      category: 'طب عام وباطني',
      icon: Icons.monitor_heart_rounded,
    ),
    SpecialtyInfo(
      id: 'pediatrics',
      nameAr: 'أطفال وحديثي الولادة',
      nameEn: 'Pediatrics & Neonatology',
      category: 'أطفال',
      icon: Icons.child_care_rounded,
    ),
    SpecialtyInfo(
      id: 'general_surgery',
      nameAr: 'جراحة عامة ومناظير',
      nameEn: 'General Surgery',
      category: 'جراحة',
      icon: Icons.healing_rounded,
    ),
    SpecialtyInfo(
      id: 'orthopedics',
      nameAr: 'عظام ومفاصل وعمود فقري',
      nameEn: 'Orthopedics & Spine',
      category: 'عظام',
      icon: Icons.accessible_forward_rounded,
    ),
    SpecialtyInfo(
      id: 'gynecology',
      nameAr: 'نساء وتوليد وعقم',
      nameEn: 'Obstetrics & Gynecology',
      category: 'نساء وتوليد',
      icon: Icons.pregnant_woman_rounded,
    ),
    SpecialtyInfo(
      id: 'dentistry',
      nameAr: 'أسنان وجراحة فم وزراعة',
      nameEn: 'Dentistry & Oral Surgery',
      category: 'أسنان',
      icon: Icons.sentiment_very_satisfied_rounded,
    ),
    SpecialtyInfo(
      id: 'dermatology',
      nameAr: 'جلدية وتجميل وليزر',
      nameEn: 'Dermatology & Cosmetology',
      category: 'جلدية',
      icon: Icons.face_retouching_natural_rounded,
    ),
    SpecialtyInfo(
      id: 'cardiology',
      nameAr: 'أمراض القلب والأوعية الدموية',
      nameEn: 'Cardiology',
      category: 'قلب وأوعية',
      icon: Icons.favorite_rounded,
    ),
    SpecialtyInfo(
      id: 'neurology',
      nameAr: 'مخ وأعصاب وجراحة',
      nameEn: 'Neurology & Neurosurgery',
      category: 'أعصاب',
      icon: Icons.psychology_rounded,
    ),
    SpecialtyInfo(
      id: 'ophthalmology',
      nameAr: 'عيون وجراحة رمد وليزر',
      nameEn: 'Ophthalmology & Lasik',
      category: 'عيون',
      icon: Icons.visibility_rounded,
    ),
    SpecialtyInfo(
      id: 'ent',
      nameAr: 'أنف وأذن وحنجرة',
      nameEn: 'ENT (Ear, Nose & Throat)',
      category: 'أنف وأذن',
      icon: Icons.hearing_rounded,
    ),
    SpecialtyInfo(
      id: 'urology',
      nameAr: 'مسالك بولية وذكورة وعقم',
      nameEn: 'Urology & Andrology',
      category: 'مسالك',
      icon: Icons.water_drop_rounded,
    ),
    SpecialtyInfo(
      id: 'gastroenterology',
      nameAr: 'جهاز هضمي وكبد ومناظير',
      nameEn: 'Gastroenterology & Hepatology',
      category: 'باطني',
      icon: Icons.medication_liquid_rounded,
    ),
    SpecialtyInfo(
      id: 'pulmonology',
      nameAr: 'أمراض صدرية وحساسية وجهاز تنفسي',
      nameEn: 'Pulmonology & Chest Diseases',
      category: 'باطني',
      icon: Icons.air_rounded,
    ),
    SpecialtyInfo(
      id: 'psychiatry',
      nameAr: 'طب نفسي وعلاج الإدمان',
      nameEn: 'Psychiatry & Addiction',
      category: 'نفسي',
      icon: Icons.self_improvement_rounded,
    ),
    SpecialtyInfo(
      id: 'physical_therapy',
      nameAr: 'علاج طبيعي وتأهيل حركي',
      nameEn: 'Physical Therapy & Rehabilitation',
      category: 'تأهيل',
      icon: Icons.fitness_center_rounded,
    ),
    SpecialtyInfo(
      id: 'oncology',
      nameAr: 'أورام وطب نووي',
      nameEn: 'Oncology & Nuclear Medicine',
      category: 'أورام',
      icon: Icons.bubble_chart_rounded,
    ),
    SpecialtyInfo(
      id: 'rheumatology',
      nameAr: 'روماتيزم ومناعة وآلام مفاصل',
      nameEn: 'Rheumatology & Immunology',
      category: 'مناعة ومفاصل',
      icon: Icons.accessibility_new_rounded,
    ),
    SpecialtyInfo(
      id: 'endocrinology',
      nameAr: 'غدد صماء وسكر وسمنة',
      nameEn: 'Endocrinology & Diabetes',
      category: 'باطني',
      icon: Icons.bloodtype_rounded,
    ),
    SpecialtyInfo(
      id: 'vascular_surgery',
      nameAr: 'جراحة أوعية دموية وقدم سكري',
      nameEn: 'Vascular Surgery',
      category: 'جراحة',
      icon: Icons.linear_scale_rounded,
    ),
    SpecialtyInfo(
      id: 'plastic_surgery',
      nameAr: 'جراحة تجميل وإصلاح وحروق',
      nameEn: 'Plastic & Reconstructive Surgery',
      category: 'جراحة',
      icon: Icons.auto_fix_high_rounded,
    ),
    SpecialtyInfo(
      id: 'phoniatrics',
      nameAr: 'تخاطب وصعوبات تعلم وتنمية مهارات',
      nameEn: 'Phoniatrics & Speech Therapy',
      category: 'تخاطب وتأهيل',
      icon: Icons.record_voice_over_rounded,
    ),
    SpecialtyInfo(
      id: 'audiology',
      nameAr: 'سمعيات واتزان',
      nameEn: 'Audiology & Balance',
      category: 'أنف وأذن',
      icon: Icons.graphic_eq_rounded,
    ),
    SpecialtyInfo(
      id: 'pain_management',
      nameAr: 'تخدير وعلاج الألم المزمن',
      nameEn: 'Anesthesia & Pain Management',
      category: 'تخدير وعلاج ألم',
      icon: Icons.spa_rounded,
    ),
    SpecialtyInfo(
      id: 'nephrology',
      nameAr: 'أمراض كلى وغسيل كلوي',
      nameEn: 'Nephrology & Dialysis',
      category: 'باطني',
      icon: Icons.clean_hands_rounded,
    ),
    SpecialtyInfo(
      id: 'cardiothoracic',
      nameAr: 'جراحة قلب وصدر',
      nameEn: 'Cardiothoracic Surgery',
      category: 'جراحة',
      icon: Icons.heart_broken_rounded,
    ),
    SpecialtyInfo(
      id: 'pediatric_surgery',
      nameAr: 'جراحة أطفال ومبتسرين',
      nameEn: 'Pediatric Surgery',
      category: 'جراحة',
      icon: Icons.escalator_warning_rounded,
    ),
    SpecialtyInfo(
      id: 'geriatrics',
      nameAr: 'طب المسنين وأمراض الشيخوخة',
      nameEn: 'Geriatrics & Aging Medicine',
      category: 'باطني',
      icon: Icons.elderly_rounded,
    ),
    SpecialtyInfo(
      id: 'family_medicine',
      nameAr: 'طب الأسرة والصحة العامة',
      nameEn: 'Family Medicine',
      category: 'طب عام',
      icon: Icons.family_restroom_rounded,
    ),
    SpecialtyInfo(
      id: 'clinical_nutrition',
      nameAr: 'تغذية علاجية وسمنة ونحافة',
      nameEn: 'Clinical Nutrition',
      category: 'تغذية',
      icon: Icons.restaurant_rounded,
    ),
    SpecialtyInfo(
      id: 'clinical_pathology',
      nameAr: 'تحاليل طبية ومناعة وباثولوجي',
      nameEn: 'Clinical Pathology & Labs',
      category: 'معامل وتحاليل',
      icon: Icons.science_rounded,
    ),
    SpecialtyInfo(
      id: 'radiology',
      nameAr: 'أشعة تشخيصية وتداخلية وسونار',
      nameEn: 'Radiology & Sonar',
      category: 'أشعة',
      icon: Icons.camera_alt_rounded,
    ),
    SpecialtyInfo(
      id: 'hematology',
      nameAr: 'أمراض دم وتجلط',
      nameEn: 'Hematology',
      category: 'باطني',
      icon: Icons.invert_colors_rounded,
    ),
    SpecialtyInfo(
      id: 'allergy_immunology',
      nameAr: 'حساسية ومناعة',
      nameEn: 'Allergy & Immunology',
      category: 'مناعة',
      icon: Icons.coronavirus_rounded,
    ),
    SpecialtyInfo(
      id: 'critical_care',
      nameAr: 'طب الحالات الحرجة وطوارئ',
      nameEn: 'Critical Care & Emergency',
      category: 'طوارئ',
      icon: Icons.emergency_rounded,
    ),
    SpecialtyInfo(
      id: 'orthodontics',
      nameAr: 'تقويم أسنان وفكين',
      nameEn: 'Orthodontics',
      category: 'أسنان',
      icon: Icons.view_column_rounded,
    ),
    SpecialtyInfo(
      id: 'endodontics',
      nameAr: 'علاج جذور وعصب الأسنان',
      nameEn: 'Endodontics',
      category: 'أسنان',
      icon: Icons.architecture_rounded,
    ),
    SpecialtyInfo(
      id: 'maxillofacial',
      nameAr: 'جراحة وجه وفكين',
      nameEn: 'Maxillofacial Surgery',
      category: 'أسنان وجراحة',
      icon: Icons.person_pin_rounded,
    ),
  ];

  /// أسماء التخصصات للعرض السريع في القوائم المنسدلة
  static List<String> get namesAr {
    return all.map((s) => s.nameAr).toList();
  }

  /// تطبيع النصوص للبحث الذكي وتجاوز الفروق الإملائية الشائعة
  static String normalizeArabic(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// فحص ما إذا كان التخصص المدخل يطابق أي تخصص في القائمة بذكاء وفهم للجذور
  static bool matches(String specialty, String query) {
    if (query.isEmpty || query == 'الكل') return true;
    final normSpec = normalizeArabic(specialty);
    final normQuery = normalizeArabic(query);
    if (normSpec.contains(normQuery) || normQuery.contains(normSpec)) return true;

    // استخراج الكلمات الدلالية الأساسية (تجاهل الألقاب وحروف العطف)
    final ignoreWords = {
      'طب', 'وجراحه', 'جراحه', 'امراض', 'وعلاج', 'عام', 'عامه', 'دقيق',
      'استشاري', 'استشاريه', 'اخصائي', 'اخصائيه', 'دكتور', 'دكتوره', 'مركز', 'عياده'
    };
    final queryWords = normQuery
        .split(' ')
        .map((w) => w.trim())
        .where((w) => w.length >= 3 && !ignoreWords.contains(w));

    for (final w in queryWords) {
      if (normSpec.contains(w)) return true;
    }
    return false;
  }
}
