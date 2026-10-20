import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/mock_data.dart';
import '../../l10n.dart';
import '../../routes.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/kit.dart';
import '../../widgets/payment_panel.dart';

class WalletTab extends StatelessWidget {
  const WalletTab({super.key});

  Future<void> _buyVoucher(BuildContext context) async {
    final r = await showAuraSheet<(int, String)>(context, builder: (_) => const _VoucherSheet());
    if (r == null || !context.mounted) return;
    final s = AuraStore.i;
    final p = await showPaymentSheet(context,
        amount: r.$1, purpose: 'Gift voucher for ${r.$2}', allowSalon: false, target: PayTarget.voucher(value: r.$1, recipientName: r.$2, shopId: s.selectedBranchId));
    if (p == null || !context.mounted) return;
    if (s.live) {
      toast(context, p.status == 'paid' ? 'Your gift voucher is ready to share 🎁' : 'Receipt sent — the voucher is issued once the salon confirms it.');
      return;
    }
    final v = s.addVoucher(r.$1, r.$2);
    toast(context, 'Voucher ${v.code} is ready to share 🎁');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) {
        final s = AuraStore.i;
        final progress = s.tier == 'Platinum' ? 1.0 : s.loyaltyPoints / s.nextTierAt;
        return Column(children: [
          ScreenHeader(title: context.t('wallet'), subtitle: 'Points, vouchers & payments'),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.maroon,
              onRefresh: () async {
                try {
                  await s.refreshWallet();
                } catch (_) {}
              },
              child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: AppGradients.maroon, borderRadius: BorderRadius.circular(AppRadius.xxl), boxShadow: AppShadows.lift),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('AURA ${s.tier.toUpperCase()} MEMBER', style: AppText.eyebrow()),
                    const Spacer(),
                    const Logo(size: 34),
                  ]),
                  const SizedBox(height: 10),
                  Text('${s.loyaltyPoints}', style: AppText.display(size: 40, color: Colors.white)),
                  Text('points · worth ${rs(s.loyaltyPoints * s.pointValue)} off${s.credit > 0 ? ' · ${rs(s.credit)} advance on account' : ''}', style: AppText.sans(size: 13, color: Colors.white70)),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 6, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(AppColors.gold)),
                  ),
                  const SizedBox(height: 6),
                  Text(s.tier == 'Platinum' ? 'Top tier unlocked — 15% off every visit' : '${s.nextTierAt - s.loyaltyPoints} points to ${s.tier == 'Silver' ? 'Gold' : 'Platinum'}', style: AppText.sans(size: 12, color: Colors.white70)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Btn(label: 'Gift voucher', icon: Icons.card_giftcard_rounded, variant: BtnVariant.gold, onTap: () => _buyVoucher(context))),
                const SizedBox(width: 10),
                Expanded(child: Btn(label: 'Invoices', icon: Icons.receipt_long_rounded, variant: BtnVariant.outline, onTap: () => Navigator.pushNamed(context, Routes.invoices))),
              ]),
              const SizedBox(height: 14),
              AuraCard(
                child: Row(children: [
                  const Icon(Icons.group_add_rounded, color: AppColors.maroon, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Refer a friend, both get Rs 1,000', style: AppText.sans(weight: FontWeight.w600)),
                      Text('Your code: ${s.profile.firstName.toUpperCase()}-AURA', style: AppText.sans(size: 12.5, color: AppColors.mutedForeground)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Copy code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '${s.profile.firstName.toUpperCase()}-AURA'));
                      toast(context, 'Referral code copied');
                    },
                    icon: const Icon(Icons.copy_rounded, color: AppColors.maroon),
                  ),
                ]),
              ),
              if (s.vouchers.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('My gift vouchers', style: AppText.display(size: 18)),
                const SizedBox(height: 10),
                for (final v in s.vouchers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(gradient: AppGradients.gold, borderRadius: BorderRadius.circular(AppRadius.lg)),
                      child: Row(children: [
                        const Icon(Icons.card_giftcard_rounded, color: AppColors.maroonInk),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${rs(v.value)} · for ${v.recipient}', style: AppText.sans(weight: FontWeight.w700, color: AppColors.maroonInk)),
                            Text(v.code, style: AppText.sans(size: 12.5, letterSpacing: 1.5, color: AppColors.maroonInk)),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: v.code));
                            toast(context, 'Voucher code copied — share it on WhatsApp!');
                          },
                          icon: const Icon(Icons.share_rounded, color: AppColors.maroonInk),
                        ),
                      ]),
                    ),
                  ),
              ],
              const SizedBox(height: 22),
              if (!s.live) Text('Saved payment methods', style: AppText.display(size: 18)),
              const SizedBox(height: 10),
              if (!s.live && s.savedMethods.isEmpty) Text('Methods you save at checkout appear here.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
              for (final m in s.live ? const <SavedMethod>[] : s.savedMethods)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AuraCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(children: [
                      _MethodDot(m.method),
                      const SizedBox(width: 12),
                      Expanded(child: Text(m.label, style: AppText.sans(weight: FontWeight.w600))),
                      if (m.isDefault) const Badge2('Default'),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'default') s.makeDefault(m);
                          if (v == 'remove' && await confirmDialog(context, title: 'Remove ${m.label}?', body: 'You can add it again at your next checkout.', confirm: 'Remove', danger: true)) {
                            s.removeMethod(m);
                          }
                        },
                        itemBuilder: (_) => [
                          if (!m.isDefault) const PopupMenuItem(value: 'default', child: Text('Make default')),
                          const PopupMenuItem(value: 'remove', child: Text('Remove')),
                        ],
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 22),
              Text('Transactions', style: AppText.display(size: 18)),
              const SizedBox(height: 10),
              if (s.payments.isEmpty)
                AuraCard(child: Text('Payments you make in the app appear here with their receipts.', style: AppText.sans(size: 13, color: AppColors.mutedForeground))),
              for (final p in s.payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AuraCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      _MethodDot(p.method),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.purpose, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 13.5, weight: FontWeight.w600)),
                          Text('${p.reference} · ${fmtDate(p.at)}', style: AppText.sans(size: 11.5, color: AppColors.mutedForeground)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('-${rs(p.amount)}', style: AppText.sans(weight: FontWeight.w700)),
                        Text(p.status == 'paid' ? 'Paid' : 'Pending', style: AppText.sans(size: 11, color: p.status == 'paid' ? AppColors.success : AppColors.warning, weight: FontWeight.w600)),
                      ]),
                    ]),
                  ),
                ),
            ]),
            ),
          ),
        ]);
      },
    );
  }
}

class _MethodDot extends StatelessWidget {
  const _MethodDot(this.m);
  final PayMethod m;
  @override
  Widget build(BuildContext context) {
    final (c, i) = switch (m) {
      PayMethod.jazzcash => (AppColors.jazzcash, Icons.phone_android_rounded),
      PayMethod.easypaisa => (AppColors.easypaisa, Icons.phone_android_rounded),
      PayMethod.card => (AppColors.visa, Icons.credit_card_rounded),
      PayMethod.bank => (AppColors.maroon, Icons.account_balance_rounded),
      PayMethod.salon => (const Color(0xFF9A7B4F), Icons.storefront_rounded),
    };
    return Container(width: 40, height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)), child: Icon(i, color: Colors.white, size: 20));
  }
}

class _VoucherSheet extends StatefulWidget {
  const _VoucherSheet();
  @override
  State<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends State<_VoucherSheet> {
  static const amounts = [2500, 5000, 10000, 25000];
  int _v = 5000;
  final _to = TextEditingController();
  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Gift a voucher', style: AppText.display(size: 22)),
        Text('Redeemable on any service at every Aura branch.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final a in amounts) ChipPill(rs(a), selected: _v == a, onTap: () => setState(() => _v = a))]),
        const SizedBox(height: 14),
        TextField(controller: _to, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Recipient’s name')),
        const SizedBox(height: 16),
        Btn(label: 'Continue to payment · ${rs(_v)}', onTap: _to.text.trim().isEmpty ? null : () => Navigator.pop(context, (_v, _to.text.trim()))),
      ]);
}
