import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';

class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key, this.initial});
  final Cat? initial;
  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  late Cat? _cat = widget.initial;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = services.where((s) => (_cat == null || s.cat == _cat) && (q.isEmpty || s.name.toLowerCase().contains(q) || s.description.toLowerCase().contains(q))).toList();
    final c = _cat == null ? null : categoryOf(_cat!);
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) {
        final b = AuraStore.i.booking;
        return AuraPage(
          title: c?.label ?? 'All services',
          subtitle: c?.blurb ?? '${services.length} services across ${categories.length} categories',
          scroll: false,
          bottom: b.serviceIds.isEmpty
              ? null
              : Btn(label: 'Continue booking · ${b.serviceIds.length} selected', onTap: () => Navigator.pushNamed(context, Routes.booking)),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(hintText: 'Search services', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 12, 16, 6), children: [
                ChipPill('All', selected: _cat == null, onTap: () => setState(() => _cat = null)),
                for (final x in menuCategories) Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: ChipPill(x.label, selected: _cat == x.id, onTap: () => setState(() => _cat = x.id))),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(icon: Icons.search_off_rounded, title: 'No matches', body: 'Try another word or category.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => ServiceTile(s: list[i]),
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class ServiceTile extends StatelessWidget {
  const ServiceTile({super.key, required this.s});
  final Service s;
  @override
  Widget build(BuildContext context) {
    final b = AuraStore.i.booking;
    final added = b.serviceIds.contains(s.id);
    return AuraCard(
      padding: const EdgeInsets.all(10),
      onTap: () => Navigator.pushNamed(context, Routes.service, arguments: s.id),
      child: Row(children: [
        AuraImage(s.image, width: 84, height: 84, radius: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.popular) const Padding(padding: EdgeInsets.only(bottom: 3), child: Badge2('POPULAR')),
            Text(s.name, style: AppText.sans(size: 14.5, weight: FontWeight.w600)),
            Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
            const SizedBox(height: 4),
            Text('${mins(s.minutes)} · ${s.priceFrom ? 'from ' : ''}${rs(s.price)}', style: AppText.sans(size: 12.5, weight: FontWeight.w700, color: AppColors.maroon)),
          ]),
        ),
        IconButton(
          tooltip: added ? 'Remove' : 'Add to booking',
          onPressed: () {
            AuraStore.i.update(() => added ? b.serviceIds.remove(s.id) : b.serviceIds.add(s.id));
            if (!added) toast(context, '${s.name} added to your booking');
          },
          icon: Icon(added ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: AppColors.maroon, size: 28),
        ),
      ]),
    );
  }
}
