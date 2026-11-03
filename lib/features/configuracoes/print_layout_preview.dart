import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import 'settings_models.dart';

class TicketLogoPreview extends StatelessWidget {
  const TicketLogoPreview({super.key, required this.logo});
  final TicketLogo logo;
  @override
  Widget build(BuildContext context) => Container(
    width: 180,
    height: 92,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: logo == TicketLogo.standard
          ? AppColors.green
          : AppColors.paleGreen,
      borderRadius: BorderRadius.circular(8),
    ),
    child: logo == TicketLogo.standard
        ? const AppAsset('logo-topo', size: 76)
        : const Icon(
            Icons.local_shipping_outlined,
            size: 52,
            color: AppColors.green,
          ),
  );
}
