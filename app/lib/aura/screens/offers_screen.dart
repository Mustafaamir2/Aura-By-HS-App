import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/mock_data.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});
  @override
  Widget build(BuildContext context) => AuraPage(
        title: 'Offers',
        subtitle: 'Apply a code at checkout',
        body: Column(children: [
          for (final (i, o) in offers.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(gradient: i.isEven ? AppGradients.maroon : AppGradients.gold, borderRadius: BorderRadius.circular(AppRadius.xl), boxShadow: AppShadows.card),
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(o.title, style: AppText.display(size: 19, color: i.isEven ? Colors.white : AppColors.maroonInk))),
                    Badge2('${o.daysLeft} days left', bg: i.isEven ? Colors.white24 : Colors.white54, fg: i.isEven ? Colors.white : AppColors.maroonInk),
                  ]),
                  const SizedBox(height: 4),
                  Text(o.description, style: AppText.sans(size: 13, color: i.isEven ? Colors.white70 : AppColors.maroonInk)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Pressable(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: o.code));
                        toast(context, '${o.code} copied');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: i.isEven ? AppColors.goldLight : AppColors.maroon, width: 1.4)),
                        child: Row(children: [
                          Text(o.code, style: AppText.sans(weight: FontWeight.w800, letterSpacing: 1.5, color: i.isEven ? AppColors.goldLight : AppColors.maroon)),
                          const SizedBox(width: 6),
                          Icon(Icons.copy_rounded, size: 15, color: i.isEven ? AppColors.goldLight : AppColors.maroon),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    Btn(
                      label: 'Book now',
                      expand: false,
                      height: 42,
                      variant: i.isEven ? BtnVariant.gold : BtnVariant.primary,
                      onTap: () {
                        AuraStore.i.booking
                          ..clear()
                          ..promo = null;
                        Clipboard.setData(ClipboardData(text: o.code));
                        toast(context, '${o.code} copied — paste it at review');
                        Navigator.pushNamed(context, Routes.booking);
                      },
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      );
}
