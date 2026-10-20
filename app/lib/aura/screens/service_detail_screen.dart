import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';

class ServiceDetailScreen extends StatelessWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});
  final String serviceId;

  @override
  Widget build(BuildContext context) {
    final s = serviceById(serviceId);
    if (s == null) return const AuraPage(title: 'Service', body: EmptyState(icon: Icons.search_off_rounded, title: 'No longer offered', body: 'This service is not on the menu any more.'));
    final cat = categoryOf(s.cat);
    final artists = stylists.where((x) => x.specialties.contains(s.cat)).toList();
    final related = services.where((x) => x.cat == s.cat && x.id != s.id).take(3).toList();
    return PhoneFrame(
      child: ListenableBuilder(
        listenable: AuraStore.i,
        builder: (context, _) {
          final store = AuraStore.i;
          final fav = store.favouriteServices.contains(s.id);
          return Scaffold(
            backgroundColor: AppColors.background,
            body: CustomScrollView(slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: AppColors.maroon,
                foregroundColor: Colors.white,
                actions: [
                  IconButton(
                    tooltip: fav ? 'Remove from favourites' : 'Save to favourites',
                    onPressed: () => store.update(() => fav ? store.favouriteServices.remove(s.id) : store.favouriteServices.add(s.id)),
                    icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? AppColors.goldLight : Colors.white),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(fit: StackFit.expand, children: [
                    AuraImage(s.image),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66000000), Color(0x00000000), Color(0xCC2B0709)]))),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.list(children: [
                  Text(cat.label.toUpperCase(), style: AppText.eyebrow()),
                  const SizedBox(height: 4),
                  Text(s.name, style: AppText.display(size: 26)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.schedule_rounded, size: 16, color: AppColors.mutedForeground),
                    Text(' ${mins(s.minutes)}', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
                    const SizedBox(width: 14),
                    Text('${s.priceFrom ? 'from ' : ''}${rs(s.price)}', style: AppText.display(size: 20, color: AppColors.maroon)),
                  ]),
                  const SizedBox(height: 14),
                  Text(s.description, style: AppText.sans(size: 14.5, height: 1.5)),
                  if (s.addOns.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Popular add-ons', style: AppText.display(size: 18)),
                    const SizedBox(height: 8),
                    for (final a in s.addOns)
                      AuraCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          const Icon(Icons.add_circle_outline_rounded, color: AppColors.gold),
                          const SizedBox(width: 10),
                          Expanded(child: Text(a.name, style: AppText.sans(weight: FontWeight.w500))),
                          Text('+${rs(a.price)}', style: AppText.sans(weight: FontWeight.w600)),
                        ]),
                      ),
                    Text('Choose add-ons while booking.', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                  ],
                  if (artists.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Artists for this service', style: AppText.display(size: 18)),
                    const SizedBox(height: 8),
                    for (final st in artists)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(name: st.name),
                        title: Text(st.name, style: AppText.sans(weight: FontWeight.w600)),
                        subtitle: Text(st.reviews == 0 ? st.role : '${st.role} · ★ ${st.rating}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                      ),
                  ],
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('You may also like', style: AppText.display(size: 18)),
                    const SizedBox(height: 8),
                    for (final r in related)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => Navigator.pushReplacementNamed(context, Routes.service, arguments: r.id),
                        leading: AuraImage(r.image, width: 48, height: 48, radius: 10),
                        title: Text(r.name, style: AppText.sans(weight: FontWeight.w500)),
                        subtitle: Text(rs(r.price), style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                  ],
                  const SizedBox(height: 20),
                ]),
              ),
            ]),
            bottomNavigationBar: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.border))),
              child: SafeArea(
                top: false,
                child: Btn(
                  label: 'Book this service',
                  icon: Icons.calendar_month_rounded,
                  onTap: () {
                    final b = store.booking;
                    if (!b.serviceIds.contains(s.id)) b.serviceIds.add(s.id);
                    Navigator.pushNamed(context, Routes.booking);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
