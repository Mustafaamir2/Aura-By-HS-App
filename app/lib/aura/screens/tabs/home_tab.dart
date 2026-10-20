import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../l10n.dart';
import '../../routes.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/kit.dart';
import '../main_shell.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  String _greet(BuildContext c) {
    final h = DateTime.now().hour;
    return c.t(h < 12 ? 'goodMorning' : h < 17 ? 'goodAfternoon' : 'goodEvening');
  }

  void _pickBranch(BuildContext context) {
    showAuraSheet<void>(context, builder: (c) {
      final s = AuraStore.i;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Choose your branch', style: AppText.display(size: 22)),
        const SizedBox(height: 12),
        for (final b in branches)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AuraCard(
              padding: const EdgeInsets.all(14),
              borderColor: s.selectedBranchId == b.id ? AppColors.maroon : null,
              onTap: () {
                s.update(() => s.selectedBranchId = b.id);
                Navigator.pop(c);
              },
              child: Row(children: [
                const Icon(Icons.location_on_rounded, color: AppColors.maroon),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.name, style: AppText.sans(weight: FontWeight.w600)),
                    Text('${b.city} · ${b.timings}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                  ]),
                ),
                Badge2(b.isOpenNow ? 'Open' : 'Closed', bg: b.isOpenNow ? AppColors.successSoft : AppColors.destructiveSoft, fg: b.isOpenNow ? AppColors.success : AppColors.destructive),
              ]),
            ),
          ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) {
        final s = AuraStore.i;
        final branch = branchById(s.selectedBranchId) ?? (branches.isEmpty ? null : branches.first);
        final news = s.threads.where((t) => t.id == 'th-announce').firstOrNull;
        final next = s.nextAppointment;
        final past = s.appointments.where((a) => a.status == ApptStatus.past).toList();
        return ListView(padding: EdgeInsets.zero, children: [
          // ---------------------------------------------------------- hero
          SizedBox(
            height: 330 + MediaQuery.of(context).padding.top,
            child: Stack(fit: StackFit.expand, children: [
              const AuraImage('$img/bride-hero.jpg', alignment: Alignment(0, -0.3)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x22000000), Color(0xE62B0709)], stops: [0, 0.4, 1]),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Logo(size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Pressable(
                        onTap: () => _pickBranch(context),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('YOUR BRANCH', style: AppText.eyebrow(size: 9.5)),
                          Row(children: [
                            Flexible(child: Text(branch?.name ?? 'Choose a branch', overflow: TextOverflow.ellipsis, style: AppText.sans(size: 14, weight: FontWeight.w600, color: Colors.white))),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                          ]),
                        ]),
                      ),
                    ),
                    _RoundIcon(icon: Icons.notifications_none_rounded, dot: true, onTap: () => Navigator.pushNamed(context, Routes.notifications)),
                  ]),
                  const Spacer(),
                  Text('${_greet(context)}, ${s.guest ? context.t('welcome') : s.profile.firstName} ✨', style: AppText.sans(size: 14, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${context.t('enhance')}\n'),
                      TextSpan(text: context.t('naturalBeauty'), style: AppText.display(size: 32, color: AppColors.goldLight, style: FontStyle.italic)),
                    ]),
                    style: AppText.display(size: 32, color: Colors.white, height: 1.1),
                  ),
                  const SizedBox(height: 16),
                  Pressable(
                    onTap: () => Navigator.pushNamed(context, Routes.catalogue),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: Row(children: [
                        const Icon(Icons.search_rounded, color: AppColors.mutedForeground),
                        const SizedBox(width: 8),
                        Expanded(child: Text(context.t('search'), overflow: TextOverflow.ellipsis, style: AppText.sans(size: 13.5, color: AppColors.mutedForeground))),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          if (s.live && (s.connecting || s.connectError != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: AuraCard(
                color: s.connectError != null ? AppColors.destructiveSoft : AppColors.goldSoft,
                borderColor: Colors.transparent,
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  if (s.connecting) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.maroon)) else const Icon(Icons.wifi_off_rounded, color: AppColors.destructive),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.connecting ? 'Connecting to Aura… (the first time can take up to a minute)' : s.connectError!, style: AppText.sans(size: 12.5))),
                  if (!s.connecting) TextButton(onPressed: s.refreshCatalog, child: const Text('Retry')),
                ]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Expanded(child: Btn(label: context.t('bookNow'), icon: Icons.calendar_month_rounded, onTap: () {
                s.booking.clear();
                Navigator.pushNamed(context, Routes.booking);
              })),
              const SizedBox(width: 10),
              Expanded(child: Btn(label: context.t('bridal'), variant: BtnVariant.gold, icon: Icons.diamond_outlined, onTap: () => Navigator.pushNamed(context, Routes.packages))),
            ]),
          ),
          // ---------------------------------------------------------- upcoming
          if (next != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _UpcomingCard(a: next),
            ),
          const SizedBox(height: 24),
          SectionHeader(context.t('ourServices'), action: context.t('seeAll'), onAction: () => Navigator.pushNamed(context, Routes.catalogue)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                for (final c in categories)
                  if (!s.live || services.any((x) => x.cat == c.id)) _CategoryTile(c: c),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (offers.isNotEmpty) SectionHeader(context.t('offersForYou'), action: context.t('allOffers'), onAction: () => Navigator.pushNamed(context, Routes.offers)),
          if (offers.isNotEmpty)
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: offers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _OfferCard(o: offers[i], dark: i.isEven),
            ),
          ),
          if (news != null && news.messages.isNotEmpty) const SizedBox(height: 16),
          if (news != null && news.messages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AuraCard(
              onTap: () {
                MainShell.goTo(context, 2);
                Navigator.pushNamed(context, Routes.chat, arguments: 'th-announce');
              },
              child: Row(children: [
                Container(width: 44, height: 44, decoration: const BoxDecoration(gradient: AppGradients.gold, shape: BoxShape.circle), child: const Icon(Icons.campaign_rounded, color: AppColors.maroonInk)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Aura Updates', style: AppText.sans(weight: FontWeight.w600)),
                    Text(news.messages.last.text.split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 12.5, color: AppColors.mutedForeground)),
                  ]),
                ),
                if (s.unread('th-announce') > 0) Badge2('${s.unread('th-announce')} new', bg: AppColors.maroon, fg: Colors.white),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          if (packages.isNotEmpty) SectionHeader(context.t('bridalPackages'), action: context.t('seeAll'), onAction: () => Navigator.pushNamed(context, Routes.packages)),
          if (packages.isNotEmpty)
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: packages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _PackageMini(p: packages[i]),
            ),
          ),
          if (past.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionHeader(context.t('bookAgain')),
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: past.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final a = past[i];
                  final sv = serviceById(a.serviceIds.isEmpty ? '' : a.serviceIds.first);
                  return SizedBox(
                    width: 250,
                    child: AuraCard(
                      padding: const EdgeInsets.all(10),
                      onTap: () {
                        s.booking
                          ..clear()
                          ..branchId = a.branchId
                          ..stylistId = a.stylistId;
                        s.booking.serviceIds.addAll(a.serviceIds);
                        Navigator.pushNamed(context, Routes.booking);
                      },
                      child: Row(children: [
                        AuraImage(sv?.image ?? '$img/salon.jpg', width: 60, height: 60, radius: 12),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 13.5, weight: FontWeight.w600)),
                            Text('with ${stylistById(a.stylistId)?.name.split(' ').first}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                            Text('Rebook →', style: AppText.sans(size: 12, weight: FontWeight.w600, color: AppColors.maroon)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (stylists.isNotEmpty) SectionHeader(context.t('meetArtists')),
          if (stylists.isNotEmpty)
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: stylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final st = stylists[i];
                return SizedBox(
                  width: 120,
                  child: AuraCard(
                    padding: const EdgeInsets.all(10),
                    child: Column(children: [
                      Avatar(name: st.name, size: 56, gold: i.isEven),
                      const SizedBox(height: 8),
                      Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 13, weight: FontWeight.w600)),
                      Text(st.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 11, color: AppColors.mutedForeground)),
                      const SizedBox(height: 2),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.star_rounded, color: AppColors.gold, size: 14),
                        Text(st.reviews == 0 ? ' New' : ' ${st.rating}', style: AppText.sans(size: 11.5, weight: FontWeight.w600)),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(context.t('lookbook'), action: context.t('seeAll'), onAction: () => Navigator.pushNamed(context, Routes.gallery)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final g in gallery) Pressable(onTap: () => Navigator.pushNamed(context, Routes.gallery), child: AuraImage(g.after, radius: 12)),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ]);
      },
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.dot = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool dot;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, color: Colors.white, size: 22),
            if (dot) Positioned(top: 10, right: 11, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle))),
          ]),
        ),
      );
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.a});
  final Appointment a;
  @override
  Widget build(BuildContext context) {
    final d = a.startsAt.difference(DateTime.now());
    final when = d.inDays > 0 ? 'in ${d.inDays} day${d.inDays == 1 ? '' : 's'}' : d.inHours > 0 ? 'in ${d.inHours} hrs' : 'today';
    return Pressable(
      onTap: () => MainShell.goTo(context, 1),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: AppGradients.maroon, borderRadius: BorderRadius.circular(AppRadius.xl), boxShadow: AppShadows.lift),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('upcomingAppointment'), style: AppText.eyebrow(size: 9.5)),
              const SizedBox(height: 6),
              Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(size: 17, color: Colors.white)),
              const SizedBox(height: 4),
              Text('${fmtDate(a.date)} · ${fmtTime(a.time)} · ${branchById(a.branchId)?.name}', style: AppText.sans(size: 12, color: Colors.white70)),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Column(children: [
              const Icon(Icons.timer_outlined, color: AppColors.goldLight, size: 20),
              const SizedBox(height: 2),
              Text(when, style: AppText.sans(size: 11.5, weight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.c});
  final Category c;

  /// Cheapest service in the category on the current menu.
  static int _from(Category c) {
    final prices = services.where((s) => s.cat == c.id).map((s) => s.price);
    return prices.isEmpty ? c.from : prices.reduce((a, b) => a < b ? a : b);
  }
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => Navigator.pushNamed(context, Routes.catalogue, arguments: c.id),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Stack(fit: StackFit.expand, children: [
            AuraImage(c.image),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xD92B0709)], stops: [0.35, 1]))),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(context.isUrdu ? c.labelUr : c.label, style: AppText.sans(size: 13.5, weight: FontWeight.w700, color: Colors.white)),
                Text('from ${rs(_from(c))}', style: AppText.sans(size: 11, color: AppColors.goldLight)),
              ]),
            ),
          ]),
        ),
      );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.o, required this.dark});
  final Offer o;
  final bool dark;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => Navigator.pushNamed(context, Routes.offers),
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: dark ? AppGradients.maroon : AppGradients.gold, borderRadius: BorderRadius.circular(AppRadius.xl)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.title, maxLines: 2, style: AppText.display(size: 16, color: dark ? Colors.white : AppColors.maroonInk)),
            const Spacer(),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: dark ? AppColors.goldLight : AppColors.maroon), borderRadius: BorderRadius.circular(8)),
                child: Text(o.code, style: AppText.sans(size: 12, weight: FontWeight.w700, color: dark ? AppColors.goldLight : AppColors.maroon, letterSpacing: 1)),
              ),
              const Spacer(),
              Text('${o.daysLeft} days left', style: AppText.sans(size: 11, color: dark ? Colors.white70 : AppColors.maroonInk)),
            ]),
          ]),
        ),
      );
}

class _PackageMini extends StatelessWidget {
  const _PackageMini({required this.p});
  final BridalPackage p;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => Navigator.pushNamed(context, Routes.packages),
        child: SizedBox(
          width: 170,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Stack(fit: StackFit.expand, children: [
              AuraImage(p.image),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xF22B0709)], stops: [0.3, 1]))),
              if (p.popular) const Positioned(top: 10, left: 10, child: Badge2('MOST LOVED', bg: AppColors.gold, fg: AppColors.maroonInk)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(p.name, style: AppText.display(size: 16, color: Colors.white)),
                  Text(p.occasion, style: AppText.sans(size: 11, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(rs(p.price), style: AppText.sans(size: 13, weight: FontWeight.w700, color: AppColors.goldLight)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
