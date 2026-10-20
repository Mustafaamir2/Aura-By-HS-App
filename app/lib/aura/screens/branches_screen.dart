import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mock_data.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';

class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// 0300 1234567 → 923001234567, as wa.me wants it.
  static String _wa(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.startsWith('0') ? '92${d.substring(1)}' : d;
  }

  @override
  Widget build(BuildContext context) => AuraPage(
        title: 'Our branches',
        subtitle: '${branches.length} salons across Pakistan',
        body: Column(children: [
          for (final b in branches)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AuraCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(b.name, style: AppText.display(size: 18))),
                    Badge2(b.isOpenNow ? 'Open now' : 'Closed', bg: b.isOpenNow ? AppColors.successSoft : AppColors.destructiveSoft, fg: b.isOpenNow ? AppColors.success : AppColors.destructive),
                  ]),
                  const SizedBox(height: 6),
                  Text(b.address, style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
                  Text(b.timings, style: AppText.sans(size: 13)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 4, children: [
                    if (b.phone.isNotEmpty) TextButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${b.phone}')), icon: const Icon(Icons.call_rounded, size: 18), label: const Text('Call')),
                    if (b.phone.isNotEmpty) TextButton.icon(onPressed: () => _open('https://wa.me/${_wa(b.phone)}'), icon: const Icon(Icons.chat_rounded, size: 18), label: const Text('WhatsApp')),
                    TextButton.icon(onPressed: () => _open('https://www.google.com/maps/dir/?api=1&destination=${b.lat != 0 ? '${b.lat},${b.lng}' : Uri.encodeComponent('${b.name}, ${b.address}')}'), icon: const Icon(Icons.directions_rounded, size: 18), label: const Text('Directions')),
                    TextButton.icon(
                      onPressed: () {
                        AuraStore.i.booking
                          ..clear()
                          ..branchId = b.id;
                        Navigator.pushNamed(context, Routes.booking);
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: const Text('Book here'),
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      );
}
