import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  Cat? _cat;

  void _open(GalleryItem g) {
    showAuraSheet<void>(context, builder: (_) => _BeforeAfter(g: g));
  }

  @override
  Widget build(BuildContext context) {
    final list = gallery.where((g) => _cat == null || g.cat == _cat).toList();
    final cats = gallery.map((g) => g.cat).toSet();
    return AuraPage(
      title: 'The Aura lookbook',
      subtitle: 'Real brides and clients · tap a look to book it',
      scroll: false,
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 12, 16, 6), children: [
            ChipPill('All', selected: _cat == null, onTap: () => setState(() => _cat = null)),
            for (final c in categories.where((c) => cats.contains(c.id)))
              Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: ChipPill(c.label, selected: _cat == c.id, onTap: () => setState(() => _cat = c.id))),
          ]),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final g = list[i];
              return Pressable(
                onTap: () => _open(g),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Stack(fit: StackFit.expand, children: [
                    AuraImage(g.after, alignment: const Alignment(0, -0.3)),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)], stops: [0.55, 1]))),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.caption, style: AppText.sans(size: 13, weight: FontWeight.w600, color: Colors.white)),
                        Text('by ${stylistById(g.stylistId)?.name}', style: AppText.sans(size: 11, color: Colors.white70)),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.g});
  final GalleryItem g;
  @override
  Widget build(BuildContext context) {
    final st = stylistById(g.stylistId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg), child: AspectRatio(aspectRatio: 0.85, child: AuraImage(g.after, alignment: const Alignment(0, -0.3)))),
      const SizedBox(height: 14),
      Text(g.caption, style: AppText.display(size: 22)),
      Text('${categoryOf(g.cat).label} · by ${st?.name}', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
      const SizedBox(height: 14),
      Btn(
        label: 'Book this look',
        onTap: () {
          final b = AuraStore.i.booking..clear();
          b.stylistId = g.stylistId;
          b.serviceIds.add(services.firstWhere((s) => s.cat == g.cat).id);
          Navigator.pop(context);
          Navigator.pushNamed(context, Routes.booking);
        },
      ),
    ]);
  }
}
