import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// "To do 8" style heading above a group of bucket-list items.
class BucketSectionHeader extends StatelessWidget {
  const BucketSectionHeader({
    super.key,
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) =>
      SoftSectionHeader(label: label, count: count);
}
