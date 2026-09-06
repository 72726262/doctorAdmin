import 'package:flutter/material.dart';
import 'package:doctor_admin/core/app_colors.dart';

/// 🌟 نظام الشيمر العصري وفائق السرعة للوحة تحكم الأدمن (Admin Shimmer Library)
/// يمنح إحساساً فورياً بالاستجابة في لمح البصر بدلاً من الدوائر الدوارة القديمة.
class AdminShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final ShapeBorder? shapeBorder;

  const AdminShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 10,
    this.shapeBorder,
  });

  const AdminShimmerBox.circular({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = 0,
        shapeBorder = const CircleBorder();

  @override
  State<AdminShimmerBox> createState() => _AdminShimmerBoxState();
}

class _AdminShimmerBoxState extends State<AdminShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _animation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.shapeBorder == null
                ? BorderRadius.circular(widget.borderRadius)
                : null,
            shape: widget.shapeBorder is CircleBorder
                ? BoxShape.circle
                : BoxShape.rectangle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
              colors: [
                const Color(0xFFE2E8F0),
                const Color(0xFFF1F5F9),
                const Color(0xFFE2E8F0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 📊 سكيليتون كروت المؤشرات العلوية (Stats Skeleton)
class AdminStatSkeleton extends StatelessWidget {
  final int count;
  const AdminStatSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final cardWidth = isWide
            ? (constraints.maxWidth - ((count - 1) * 14)) / count
            : (constraints.maxWidth - 14) / 2;

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: List.generate(
            count,
            (index) => Container(
              width: cardWidth,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminColors.surfaceWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AdminColors.cardBorder),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AdminShimmerBox(width: 80, height: 14, borderRadius: 6),
                      AdminShimmerBox.circular(size: 28),
                    ],
                  ),
                  SizedBox(height: 12),
                  AdminShimmerBox(width: 60, height: 26, borderRadius: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 🏥 سكيليتون رادار الطوابير وغرفة العمليات (War Room Card Skeleton)
class AdminWarRoomCardSkeleton extends StatelessWidget {
  final int count;
  const AdminWarRoomCardSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200
            ? 3
            : (constraints.maxWidth > 700 ? 2 : 1);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 220,
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AdminColors.cardBorder),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AdminShimmerBox.circular(size: 44),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AdminShimmerBox(width: 120, height: 16, borderRadius: 6),
                            SizedBox(height: 6),
                            AdminShimmerBox(width: 80, height: 12, borderRadius: 4),
                          ],
                        ),
                      ),
                      AdminShimmerBox(width: 50, height: 22, borderRadius: 12),
                    ],
                  ),
                  Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AdminShimmerBox(width: 85, height: 40, borderRadius: 10),
                      AdminShimmerBox(width: 85, height: 40, borderRadius: 10),
                      AdminShimmerBox(width: 85, height: 40, borderRadius: 10),
                    ],
                  ),
                  Spacer(),
                  AdminShimmerBox(width: double.infinity, height: 8, borderRadius: 4),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 📋 سكيليتون الجداول والقوائم (Table Rows Skeleton)
class AdminTableSkeleton extends StatelessWidget {
  final int rows;
  const AdminTableSkeleton({super.key, this.rows = 6});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.cardBorder),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (context, index) => const Divider(height: 1, color: AdminColors.cardBorder),
        itemBuilder: (context, index) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                AdminShimmerBox.circular(size: 36),
                SizedBox(width: 14),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdminShimmerBox(width: 160, height: 15, borderRadius: 6),
                      SizedBox(height: 6),
                      AdminShimmerBox(width: 100, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: AdminShimmerBox(width: 90, height: 14, borderRadius: 6),
                ),
                SizedBox(width: 16),
                AdminShimmerBox(width: 70, height: 26, borderRadius: 14),
                SizedBox(width: 16),
                AdminShimmerBox(width: 80, height: 32, borderRadius: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}
