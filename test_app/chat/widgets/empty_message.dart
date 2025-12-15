import 'package:design/themes/f_colors.dart';
import 'package:design/themes/f_font_styles.dart';
import 'package:flutter/material.dart';

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({
    super.key,
    required this.ctName,
  });

  final String ctName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const CircleAvatar(child: Icon(Icons.person, size: 34), radius: 34),
        const SizedBox(height: 6),
        Text(ctName, style: FTextStyles.title3_18.b),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('', style: FTextStyles.body3_13.b.copyWith(color: FColors.current.labelAlternative)),
          ],
        ),
      ],
    );
  }
}
