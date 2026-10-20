import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mock_data.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// Checkout for everything paid in the app — booking advances, bridal
/// deposits, balances and gift vouchers. The flows mirror the real gateways:
/// a wallet approval / OTP for JazzCash and Easypaisa, 3-D Secure for cards,
/// and a transfer slip for bank payments. Going live replaces only [_process].
///
/// Resolves with the [PaymentRecord], or `null` when "Pay at salon" is chosen
/// or the sheet is closed.
///
/// When the app is connected, pass [target] — what is being paid on the server
/// (a booking, bridal booking or voucher) — and the real checkout is used.
Future<PaymentRecord?> showPaymentSheet(BuildContext context, {required int amount, required String purpose, bool allowSalon = true, PayTarget? target}) {
  if (AuraStore.i.live && target != null) {
    return showAuraSheet<PaymentRecord?>(context, builder: (_) => LivePaymentPanel(amount: amount, purpose: purpose, target: target));
  }
  return showAuraSheet<PaymentRecord?>(context, builder: (_) => PaymentPanel(amount: amount, purpose: purpose, allowSalon: allowSalon));
}

/// What a live payment is for, in the API's terms.
class PayTarget {
  const PayTarget.appointment(String id, {this.plan = 'advance', this.amount})
      : purpose = 'appointment',
        refId = id,
        voucher = null;
  const PayTarget.bridal(String id, {this.plan = 'advance', this.amount})
      : purpose = 'bridal',
        refId = id,
        voucher = null;
  PayTarget.voucher({required int value, required String recipientName, required String shopId, String recipientPhone = ''})
      : purpose = 'voucher',
        refId = null,
        plan = 'full',
        amount = null,
        voucher = {'value': value, 'recipientName': recipientName, 'recipientPhone': recipientPhone, 'shopId': shopId};
  final String purpose;
  final String? refId;
  final String plan;
  final num? amount;
  final Map<String, dynamic>? voucher;
}

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({super.key, required this.amount, required this.purpose, this.allowSalon = true});
  final int amount;
  final String purpose;
  final bool allowSalon;
  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

enum _Stage { form, otp, processing, done }

class _M {
  const _M(this.m, this.hint, this.color, this.icon);
  final PayMethod m;
  final String hint;
  final Color color;
  final IconData icon;
}

const _methods = [
  _M(PayMethod.jazzcash, 'Mobile wallet', AppColors.jazzcash, Icons.phone_android_rounded),
  _M(PayMethod.easypaisa, 'Mobile wallet', AppColors.easypaisa, Icons.phone_android_rounded),
  _M(PayMethod.card, 'Visa · Mastercard · UnionPay', AppColors.visa, Icons.credit_card_rounded),
  _M(PayMethod.bank, 'IBFT / Raast', AppColors.maroon, Icons.account_balance_rounded),
  _M(PayMethod.salon, 'Cash or card on the day', Color(0xFF9A7B4F), Icons.storefront_rounded),
];

const _bank = [
  ('Bank', 'Meezan Bank'),
  ('Account title', 'AURA BY HS (PVT) LTD'),
  ('Account no.', '0101 0123 4567 89'),
  ('IBAN', 'PK36 MEZN 0001 0101 2345 6789'),
  ('Raast ID', '0300 1234567'),
];

bool _luhn(String n) {
  var sum = 0;
  var dbl = false;
  for (var i = n.length - 1; i >= 0; i--) {
    var d = int.parse(n[i]);
    if (dbl) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    dbl = !dbl;
  }
  return n.length >= 13 && sum % 10 == 0;
}

String _brand(String n) {
  if (n.startsWith('4')) return 'VISA';
  if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(n)) return 'Mastercard';
  if (n.startsWith('62')) return 'UnionPay';
  return '';
}

class _PaymentPanelState extends State<PaymentPanel> {
  PayMethod _method = PayMethod.easypaisa;
  _Stage _stage = _Stage.form;
  final _wallet = TextEditingController();
  final _card = TextEditingController();
  final _name = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _otp = TextEditingController();
  bool _save = true;
  bool _slip = false;
  String? _error;
  int _timer = 0;
  Timer? _t;
  PaymentRecord? _record;

  @override
  void initState() {
    super.initState();
    final def = AuraStore.i.savedMethods.where((s) => s.isDefault).firstOrNull;
    if (def != null && def.method != PayMethod.salon) _method = def.method;
  }

  @override
  void dispose() {
    _t?.cancel();
    for (final c in [_wallet, _card, _name, _expiry, _cvv, _otp]) {
      c.dispose();
    }
    super.dispose();
  }

  _M get _m => _methods.firstWhere((x) => x.m == _method);
  String get _cardDigits => _card.text.replaceAll(RegExp(r'\D'), '');

  String? _validate() {
    if (_method == PayMethod.jazzcash || _method == PayMethod.easypaisa) {
      if (!RegExp(r'^03\d{9}$').hasMatch(_wallet.text.replaceAll(RegExp(r'\D'), ''))) return 'Enter your ${_method.label} number, e.g. 0300 1234567';
    }
    if (_method == PayMethod.card) {
      if (!_luhn(_cardDigits)) return 'That card number is not valid.';
      if (_name.text.trim().isEmpty) return 'Enter the name on the card.';
      final p = _expiry.text.split('/');
      final mm = p.isNotEmpty ? int.tryParse(p[0]) : null;
      final yy = p.length > 1 ? int.tryParse(p[1]) : null;
      if (mm == null || yy == null || mm < 1 || mm > 12 || !DateTime(2000 + yy, mm + 1).isAfter(DateTime.now())) return 'Enter a valid expiry date (MM/YY).';
      if (!RegExp(r'^\d{3,4}$').hasMatch(_cvv.text)) return 'Enter the 3-digit CVV on the back of the card.';
    }
    if (_method == PayMethod.bank && !_slip) return 'Upload a screenshot of your transfer receipt.';
    return null;
  }

  void _start() {
    final e = _validate();
    setState(() => _error = e);
    if (e != null) return;
    if (_method == PayMethod.salon) {
      Navigator.pop(context, null);
      return;
    }
    if (_method == PayMethod.bank) {
      _process(status: 'pending');
      return;
    }
    _otp.clear();
    setState(() {
      _stage = _Stage.otp;
      _timer = 60;
    });
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _timer = (_timer - 1).clamp(0, 60));
    });
  }

  void _verify() {
    if (_otp.text != '1234') {
      setState(() => _error = 'Incorrect code. For this demo, use 1234.');
      return;
    }
    _process(status: 'paid');
  }

  Future<void> _process({required String status}) async {
    setState(() {
      _error = null;
      _stage = _Stage.processing;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final ref = switch (_method) {
      PayMethod.card => '${_brand(_cardDigits).isEmpty ? 'Card' : _brand(_cardDigits)} •••• ${_cardDigits.substring(_cardDigits.length - 4)}',
      PayMethod.bank => 'Bank transfer slip',
      _ => '${_method.label} •••• ${_wallet.text.replaceAll(RegExp(r'\D'), '').substring(7)}',
    };
    final rec = AuraStore.i.recordPayment(amount: widget.amount, method: _method, purpose: widget.purpose, reference: ref, status: status);
    if (_save && _method != PayMethod.bank) AuraStore.i.saveMethod(_method, ref);
    if (!mounted) return;
    setState(() {
      _record = rec;
      _stage = _Stage.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: switch (_stage) {
        _Stage.processing => _processing(),
        _Stage.done => _done(),
        _Stage.otp => _otpView(),
        _Stage.form => _form(),
      },
    );
  }

  Widget _amountCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: AppGradients.maroon, borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AMOUNT TO PAY', style: AppText.eyebrow(size: 10)),
          const SizedBox(height: 6),
          Text(rs(widget.amount), style: AppText.display(size: 30, color: Colors.white)),
          Text(widget.purpose, style: AppText.sans(size: 12.5, color: Colors.white70)),
        ]),
      );

  Widget _form() {
    final methods = _methods.where((x) => widget.allowSalon || x.m != PayMethod.salon);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Checkout', style: AppText.display(size: 22)),
      const SizedBox(height: 12),
      _amountCard(),
      const SizedBox(height: 16),
      for (final x in methods) ...[
        Pressable(
          onTap: () => setState(() {
            _method = x.m;
            _error = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: _method == x.m ? AppColors.maroon : AppColors.border, width: _method == x.m ? 1.6 : 1),
            ),
            child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: x.color, borderRadius: BorderRadius.circular(12)), child: Icon(x.icon, color: Colors.white, size: 21)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.m.label, style: AppText.sans(size: 14.5, weight: FontWeight.w600)),
                  Text(x.hint, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                ]),
              ),
              Icon(_method == x.m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _method == x.m ? AppColors.maroon : AppColors.border),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      if (_method == PayMethod.jazzcash || _method == PayMethod.easypaisa) ...[
        Text('${_method.label} account number', style: AppText.sans(size: 13, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(controller: _wallet, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '0300 1234567')),
        const SizedBox(height: 6),
        Text('You’ll approve the payment in your ${_method.label} app.', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
      ],
      if (_method == PayMethod.card) ...[
        TextField(
          controller: _card,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16), _CardFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Card number',
            suffixIcon: Padding(padding: const EdgeInsets.all(14), child: Text(_brand(_cardDigits), style: AppText.sans(size: 12, weight: FontWeight.w800, color: AppColors.visa))),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Name on card')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _expiry, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4), _ExpiryFormatter()], decoration: const InputDecoration(hintText: 'MM/YY'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _cvv, keyboardType: TextInputType.number, obscureText: true, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)], decoration: const InputDecoration(hintText: 'CVV'))),
        ]),
        const SizedBox(height: 6),
        Text('Test card: 4242 4242 4242 4242 · any future date · any CVV', style: AppText.sans(size: 11.5, color: AppColors.mutedForeground)),
      ],
      if (_method == PayMethod.bank)
        AuraCard(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            for (final (k, v) in _bank)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: v));
                  toast(context, '$k copied');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(child: Text(k, style: AppText.sans(size: 13, color: AppColors.mutedForeground))),
                    Text(v, style: AppText.sans(size: 13, weight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, size: 14, color: AppColors.mutedForeground),
                  ]),
                ),
              ),
            const SizedBox(height: 10),
            Pressable(
              onTap: () async {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                if (f != null) setState(() => _slip = true);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: _slip ? AppColors.success : AppColors.border, width: 1.5)),
                child: Column(children: [
                  Icon(_slip ? Icons.check_circle_rounded : Icons.upload_rounded, color: _slip ? AppColors.success : AppColors.mutedForeground),
                  const SizedBox(height: 4),
                  Text(_slip ? 'Receipt attached' : 'Upload transfer screenshot', style: AppText.sans(size: 12.5, color: AppColors.mutedForeground)),
                ]),
              ),
            ),
          ]),
        ),
      if (_method == PayMethod.salon)
        AuraCard(
          child: Text('Your slot is held and you pay at the counter on the day — cash, card or wallet.', style: AppText.sans(size: 13.5, color: AppColors.mutedForeground, height: 1.4)),
        ),
      if (_method != PayMethod.bank && _method != PayMethod.salon)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.maroon,
          value: _save,
          onChanged: (v) => setState(() => _save = v ?? false),
          title: Text('Save for faster checkout', style: AppText.sans(size: 13)),
        ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: AppText.sans(size: 12.5, color: AppColors.destructive))),
      const SizedBox(height: 12),
      Btn(
        label: switch (_method) {
          PayMethod.salon => 'Confirm — pay at salon',
          PayMethod.bank => 'I’ve transferred the money',
          _ => 'Pay ${rs(widget.amount)}',
        },
        onTap: _start,
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_rounded, size: 13, color: AppColors.success),
        const SizedBox(width: 6),
        Text('Encrypted payment · Aura never stores card details', style: AppText.sans(size: 11.5, color: AppColors.mutedForeground)),
      ]),
    ]);
  }

  Widget _otpView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: _m.color, borderRadius: BorderRadius.circular(AppRadius.xl)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_method == PayMethod.card ? '3-D SECURE VERIFICATION' : '${_method.label.toUpperCase()} APPROVAL', style: AppText.eyebrow(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(rs(widget.amount), style: AppText.display(size: 28, color: Colors.white)),
            Text('to Aura by HS · ${widget.purpose}', style: AppText.sans(size: 12.5, color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 14),
        Text(
          _method == PayMethod.card
              ? 'Your bank has sent a one-time code by SMS. Enter it to authorise the payment.'
              : 'A payment request was sent to ${_wallet.text}. Approve it in the ${_method.label} app, or enter the OTP you received.',
          style: AppText.sans(size: 13.5, color: AppColors.mutedForeground, height: 1.45),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _otp,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: AppText.display(size: 26),
          decoration: const InputDecoration(hintText: 'Code (demo: 1234)'),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: AppText.sans(size: 12.5, color: AppColors.destructive))),
        const SizedBox(height: 14),
        Btn(label: 'Authorise ${rs(widget.amount)}', onTap: _verify),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(onPressed: () => setState(() => _stage = _Stage.form), child: Text('Cancel', style: AppText.sans(color: AppColors.mutedForeground))),
          Text(_timer > 0 ? 'Code expires in ${_timer}s' : 'Code expired — go back and retry', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
        ]),
      ]);

  Widget _processing() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(children: [
          const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: AppColors.maroon, strokeWidth: 3)),
          const SizedBox(height: 18),
          Text('Processing ${rs(widget.amount)}…', style: AppText.display(size: 18)),
          const SizedBox(height: 4),
          Text('Please don’t close the app.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
        ]),
      );

  Widget _done() {
    final r = _record!;
    final pending = r.status == 'pending';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: pending ? AppColors.goldSoft : AppColors.successSoft, shape: BoxShape.circle),
          child: Icon(pending ? Icons.hourglass_top_rounded : Icons.check_rounded, size: 38, color: pending ? AppColors.warning : AppColors.success),
        ),
      ),
      const SizedBox(height: 14),
      Text(pending ? 'Payment submitted' : 'Payment successful', textAlign: TextAlign.center, style: AppText.display(size: 22)),
      const SizedBox(height: 4),
      Text(pending ? 'We’ll confirm your transfer within a few hours.' : '${rs(r.amount)} paid by ${r.reference}', textAlign: TextAlign.center, style: AppText.sans(size: 13.5, color: AppColors.mutedForeground)),
      const SizedBox(height: 16),
      AuraCard(
        child: Column(children: [
          InfoRow('Reference', r.id),
          InfoRow('For', r.purpose),
          InfoRow('Amount', rs(r.amount), bold: true),
          InfoRow('Status', pending ? 'Pending verification' : 'Paid', valueColor: pending ? AppColors.warning : AppColors.success),
        ]),
      ),
      const SizedBox(height: 16),
      Btn(label: 'Continue', onTap: () => Navigator.pop(context, r)),
    ]);
  }
}

class _CardFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final d = newValue.text.replaceAll(' ', '');
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(d[i]);
    }
    final s = b.toString();
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final d = newValue.text.replaceAll('/', '');
    final s = d.length > 2 ? '${d.substring(0, 2)}/${d.substring(2)}' : d;
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}


// ===================================================================== live

const _apiMethod = {PayMethod.jazzcash: 'jazzcash', PayMethod.easypaisa: 'easypaisa', PayMethod.card: 'card', PayMethod.bank: 'bank-transfer'};

/// The real checkout: the customer pays on JazzCash's or Easypaisa's own page
/// (wallet or card) in the browser, or uploads a bank-transfer receipt. The app
/// watches the payment until the server confirms it.
class LivePaymentPanel extends StatefulWidget {
  const LivePaymentPanel({super.key, required this.amount, required this.purpose, required this.target});
  final int amount;
  final String purpose;
  final PayTarget target;
  @override
  State<LivePaymentPanel> createState() => _LivePaymentPanelState();
}

enum _Live { choose, starting, waiting, bank, uploading, done }

class _LivePaymentPanelState extends State<LivePaymentPanel> with WidgetsBindingObserver {
  late PayMethod _method = _methods.firstWhere((m) => AuraStore.i.pay.methods.contains(_apiMethod[m.m]), orElse: () => _methods.first).m;
  _Live _stage = _Live.choose;
  Map<String, dynamic>? _payment;
  String? _startUrl;
  String? _error;
  Timer? _poll;
  List<int>? _slip;
  String _slipName = 'receipt.jpg';
  final _note = TextEditingController();

  int get _amount => ((_payment?['amount'] ?? widget.amount) as num).round();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _note.dispose();
    super.dispose();
  }

  // Coming back from the payment page: check straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Live.waiting) unawaited(_check());
  }

  Future<void> _create() async {
    final t = widget.target;
    final r = await AuraStore.i.createPayment(purpose: t.purpose, refId: t.refId, plan: t.plan, amount: t.amount, method: _apiMethod[_method]!, voucher: t.voucher);
    _payment = Map<String, dynamic>.from(r['payment']);
    _startUrl = r['startUrl'] as String?;
  }

  Future<void> _start() async {
    setState(() {
      _stage = _Live.starting;
      _error = null;
    });
    try {
      // A new payment row per attempt keeps each gateway reference unique.
      await _create();
      if (_method == PayMethod.bank) {
        setState(() => _stage = _Live.bank);
        return;
      }
      await _open();
      setState(() => _stage = _Live.waiting);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    } on ApiException catch (e) {
      setState(() {
        _stage = _Live.choose;
        _error = e.message;
      });
    }
  }

  Future<void> _open() async {
    final url = _startUrl;
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, 'Could not open the payment page. Please try again.', error: true);
  }

  Future<void> _check() async {
    final id = _payment?['id'];
    if (id == null) return;
    try {
      final p = await AuraStore.i.paymentStatus('$id');
      if (!mounted) return;
      _payment = p;
      final st = '${p['status']}';
      if (st == 'paid' || st == 'verifying') {
        _poll?.cancel();
        unawaited(AuraStore.i.afterPayment());
        setState(() => _stage = _Live.done);
      } else if (st == 'failed' || st == 'expired' || st == 'cancelled' || st == 'rejected') {
        _poll?.cancel();
        setState(() {
          _stage = _Live.choose;
          _error = '${p['gatewayMessage'] ?? 'The payment was not completed. No money was taken.'}';
        });
      } else {
        setState(() {});
      }
    } on ApiException {
      // Network blip — the next tick tries again.
    }
  }

  Future<void> _pickSlip() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() {
      _slip = bytes;
      _slipName = f.name.isEmpty ? 'receipt.jpg' : f.name;
    });
  }

  Future<void> _sendSlip() async {
    if (_slip == null) {
      setState(() => _error = 'Attach a photo of the transfer receipt first.');
      return;
    }
    setState(() {
      _stage = _Live.uploading;
      _error = null;
    });
    try {
      _payment = await AuraStore.i.uploadSlip('${_payment!['id']}', _slip!, _slipName, _note.text);
      unawaited(AuraStore.i.afterPayment());
      setState(() => _stage = _Live.done);
    } on ApiException catch (e) {
      setState(() {
        _stage = _Live.bank;
        _error = e.message;
      });
    }
  }

  PaymentRecord _record() {
    final p = _payment!;
    return PaymentRecord(
      id: '${p['paymentNo']}',
      at: DateTime.now(),
      amount: _amount,
      method: _method,
      purpose: widget.purpose,
      status: p['status'] == 'paid' ? 'paid' : 'pending',
      reference: '${p['gatewayRef'] ?? p['paymentNo']}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: switch (_stage) {
        _Live.choose => _chooseView(),
        _Live.starting || _Live.uploading => _busy(_stage == _Live.uploading ? 'Uploading your receipt…' : 'Preparing secure checkout…'),
        _Live.waiting => _waitingView(),
        _Live.bank => _bankView(),
        _Live.done => _doneView(),
      },
    );
  }

  Widget _amountCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: AppGradients.maroon, borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AMOUNT TO PAY', style: AppText.eyebrow(size: 10)),
          const SizedBox(height: 6),
          Text(rs(_amount), style: AppText.display(size: 30, color: Colors.white)),
          Text(widget.purpose, style: AppText.sans(size: 12.5, color: Colors.white70)),
        ]),
      );

  Widget _busy(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(children: [
          const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: AppColors.maroon, strokeWidth: 3)),
          const SizedBox(height: 18),
          Text(text, style: AppText.display(size: 18)),
        ]),
      );

  Widget _chooseView() {
    final allowed = AuraStore.i.pay.methods;
    final list = _methods.where((x) => x.m != PayMethod.salon && allowed.contains(_apiMethod[x.m]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Checkout', style: AppText.display(size: 22)),
      const SizedBox(height: 12),
      _amountCard(),
      const SizedBox(height: 16),
      for (final x in list) ...[
        Pressable(
          onTap: () => setState(() {
            _method = x.m;
            _error = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: _method == x.m ? AppColors.maroon : AppColors.border, width: _method == x.m ? 1.6 : 1),
            ),
            child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: x.color, borderRadius: BorderRadius.circular(12)), child: Icon(x.icon, color: Colors.white, size: 21)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.m.label, style: AppText.sans(size: 14.5, weight: FontWeight.w600)),
                  Text(x.m == PayMethod.bank ? 'Transfer, then upload the receipt' : 'Pay on ${x.m == PayMethod.card ? 'the bank’s' : '${x.m.label}’s'} secure page', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                ]),
              ),
              Icon(_method == x.m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _method == x.m ? AppColors.maroon : AppColors.border),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (list.isEmpty) Text('Online payment is not available right now — please pay at the salon.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: AppText.sans(size: 12.5, color: AppColors.destructive))),
      const SizedBox(height: 12),
      Btn(label: _method == PayMethod.bank ? 'Show bank details' : 'Continue to ${_method.label}', onTap: list.isEmpty ? null : _start),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.lock_rounded, size: 13, color: AppColors.success),
        const SizedBox(width: 6),
        Flexible(child: Text('Your PIN and card number go only to JazzCash / Easypaisa.', style: AppText.sans(size: 11.5, color: AppColors.mutedForeground))),
      ]),
    ]);
  }

  Widget _waitingView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _amountCard(),
        const SizedBox(height: 18),
        const Center(child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: AppColors.maroon, strokeWidth: 3))),
        const SizedBox(height: 14),
        Text('Complete the payment on the ${_method.label} page', textAlign: TextAlign.center, style: AppText.display(size: 18)),
        const SizedBox(height: 6),
        Text('This updates by itself once ${_method.label} confirms it. Then come back to the app.', textAlign: TextAlign.center, style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
        const SizedBox(height: 16),
        Btn(label: 'Open the payment page again', variant: BtnVariant.outline, onTap: _open),
        const SizedBox(height: 8),
        Btn(label: 'I’ve paid — check now', variant: BtnVariant.ghost, onTap: _check),
        TextButton(
          onPressed: () {
            _poll?.cancel();
            Navigator.pop(context, null);
          },
          child: Text('Pay later', style: AppText.sans(color: AppColors.mutedForeground)),
        ),
      ]);

  Widget _bankView() {
    final b = AuraStore.i.pay.bank;
    final rows = [
      ('Bank', b['bankName'] ?? ''),
      ('Account title', b['accountTitle'] ?? ''),
      ('Account no.', b['accountNumber'] ?? ''),
      ('IBAN', b['iban'] ?? ''),
      ('Raast ID', b['raastId'] ?? ''),
      ('Reference', '${_payment?['paymentNo'] ?? ''}'),
    ].where((r) => r.$2.isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Bank transfer', style: AppText.display(size: 22)),
      const SizedBox(height: 12),
      _amountCard(),
      const SizedBox(height: 12),
      AuraCard(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          if (rows.isEmpty) Text('Ask the salon for its bank details.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
          for (final (k, v) in rows)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: v));
                toast(context, '$k copied');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(k, style: AppText.sans(size: 13, color: AppColors.mutedForeground))),
                  Flexible(child: Text(v, textAlign: TextAlign.end, style: AppText.sans(size: 13, weight: FontWeight.w600))),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, size: 14, color: AppColors.mutedForeground),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Text('Send exactly ${rs(_amount)} with the reference above, then upload the receipt. The salon confirms it, usually within a few hours.', style: AppText.sans(size: 12.5, color: AppColors.mutedForeground, height: 1.4)),
      const SizedBox(height: 10),
      Pressable(
        onTap: _pickSlip,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: _slip != null ? AppColors.success : AppColors.border, width: 1.5)),
          child: Column(children: [
            Icon(_slip != null ? Icons.check_circle_rounded : Icons.upload_rounded, color: _slip != null ? AppColors.success : AppColors.mutedForeground),
            const SizedBox(height: 4),
            Text(_slip != null ? 'Receipt attached — tap to change' : 'Upload transfer screenshot', style: AppText.sans(size: 12.5, color: AppColors.mutedForeground)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      TextField(controller: _note, decoration: const InputDecoration(hintText: 'Sender name or transaction ID (optional)')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: AppText.sans(size: 12.5, color: AppColors.destructive))),
      const SizedBox(height: 12),
      Btn(label: 'Send receipt', onTap: _sendSlip),
      TextButton(onPressed: () => setState(() => _stage = _Live.choose), child: Text('Pay another way', style: AppText.sans(color: AppColors.mutedForeground))),
    ]);
  }

  Widget _doneView() {
    final pending = _payment?['status'] != 'paid';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: pending ? AppColors.goldSoft : AppColors.successSoft, shape: BoxShape.circle),
          child: Icon(pending ? Icons.hourglass_top_rounded : Icons.check_rounded, size: 38, color: pending ? AppColors.warning : AppColors.success),
        ),
      ),
      const SizedBox(height: 14),
      Text(pending ? 'Receipt sent' : 'Payment successful', textAlign: TextAlign.center, style: AppText.display(size: 22)),
      const SizedBox(height: 4),
      Text(pending ? 'The salon will confirm your transfer shortly.' : '${rs(_amount)} paid by ${_method.label}', textAlign: TextAlign.center, style: AppText.sans(size: 13.5, color: AppColors.mutedForeground)),
      const SizedBox(height: 16),
      AuraCard(
        child: Column(children: [
          InfoRow('Reference', '${_payment?['paymentNo']}'),
          InfoRow('For', widget.purpose),
          InfoRow('Amount', rs(_amount), bold: true),
          InfoRow('Status', pending ? 'Waiting for the salon' : 'Paid', valueColor: pending ? AppColors.warning : AppColors.success),
          if (_payment?['voucher']?['code'] != null) InfoRow('Voucher code', '${_payment!['voucher']['code']}', bold: true),
        ]),
      ),
      const SizedBox(height: 16),
      Btn(label: 'Continue', onTap: () => Navigator.pop(context, _record())),
    ]);
  }
}
