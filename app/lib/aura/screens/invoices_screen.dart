import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../services/live.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';

class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  void _open(BuildContext context, Appointment a) {
    final br = branchById(a.branchId) ?? branches.first;
    showAuraSheet<void>(context, builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Logo(size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Aura by HS', style: AppText.display(size: 18)),
                Text(br.name, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('INVOICE', style: AppText.eyebrow()),
              Text('INV-${a.id.substring(4)}', style: AppText.sans(size: 12, weight: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 14),
          InfoRow('Date', fmtDateLong(a.date)),
          InfoRow('Customer', AuraStore.i.profile.name),
          InfoRow('Artist', stylistById(a.stylistId)?.name ?? ''),
          const Divider(color: AppColors.border),
          for (final id in a.serviceIds) InfoRow(serviceById(id)?.name ?? 'Service', rs(serviceById(id)?.price ?? 0)),
          const Divider(color: AppColors.border),
          InfoRow('Total', rs(a.total), bold: true),
          InfoRow('Paid', rs(a.paid), valueColor: AppColors.success),
          if (a.paidBy != null) InfoRow('Method', a.paidBy!),
          if (a.total > a.paid) InfoRow('Balance', rs(a.total - a.paid), valueColor: AppColors.warning),
          const SizedBox(height: 14),
          Btn(label: 'Share receipt', icon: Icons.ios_share_rounded, variant: BtnVariant.outline, onTap: () {
            Navigator.pop(c);
            toast(context, 'Receipt sent to ${AuraStore.i.profile.phone}');
          }),
        ]));
  }

  void _openLive(BuildContext context, Invoice inv) {
    showAuraSheet<void>(context, builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Logo(size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Aura by HS', style: AppText.display(size: 18)),
                Text(inv.shopName, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('RECEIPT', style: AppText.eyebrow()),
              Text(inv.receiptNo, style: AppText.sans(size: 12, weight: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 14),
          InfoRow('Date', fmtDateLong(inv.at)),
          if (inv.status == 'refunded') const InfoRow('Status', 'Refunded', valueColor: AppColors.destructive),
          const Divider(color: AppColors.border),
          for (final it in inv.items) InfoRow('${it['name']}${(it['quantity'] ?? 1) > 1 ? ' ×${it['quantity']}' : ''}', rs((it['lineTotal'] ?? 0) as num)),
          const Divider(color: AppColors.border),
          if (inv.discount > 0) InfoRow('Discounts', '−${rs(inv.discount)}', valueColor: AppColors.success),
          if (inv.tax > 0) InfoRow('Tax', rs(inv.tax)),
          InfoRow('Total', rs(inv.total), bold: true),
          for (final p in inv.payments) InfoRow('Paid · ${methodLabel('${p['method']}')}', rs((p['amount'] ?? 0) as num)),
          if (inv.balanceDue > 0) InfoRow('Balance due', rs(inv.balanceDue), valueColor: AppColors.warning),
          if (inv.pointsEarned > 0) InfoRow('Points earned', '+${inv.pointsEarned}', valueColor: AppColors.success),
          const SizedBox(height: 12),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    if (AuraStore.i.live) {
      final rows = AuraStore.i.invoices;
      return AuraPage(
        title: 'Invoices & receipts',
        body: rows.isEmpty
            ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No receipts yet', body: 'Bills from your visits appear here as soon as the salon closes them.')
            : Column(children: [
                for (final inv in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AuraCard(
                      padding: const EdgeInsets.all(12),
                      onTap: () => _openLive(context, inv),
                      child: Row(children: [
                        const CircleAvatar(backgroundColor: AppColors.goldSoft, child: Icon(Icons.receipt_long_rounded, color: AppColors.maroon, size: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(inv.items.map((i) => i['name']).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(weight: FontWeight.w600)),
                            Text('${inv.receiptNo} · ${fmtDateLong(inv.at)} · ${inv.shopName}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                          ]),
                        ),
                        Text(rs(inv.total), style: AppText.sans(weight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ]),
      );
    }
    final list = AuraStore.i.appointments.where((a) => a.status != ApptStatus.cancelled && a.paid > 0).toList();
    return AuraPage(
      title: 'Invoices & receipts',
      body: list.isEmpty
          ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No invoices yet', body: 'Receipts appear here after your first payment.')
          : Column(children: [
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AuraCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () => _open(context, a),
                    child: Row(children: [
                      const CircleAvatar(backgroundColor: AppColors.goldSoft, child: Icon(Icons.receipt_long_rounded, color: AppColors.maroon, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(weight: FontWeight.w600)),
                          Text('INV-${a.id.substring(4)} · ${fmtDateLong(a.date)}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                        ]),
                      ),
                      Text(rs(a.total), style: AppText.sans(weight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
