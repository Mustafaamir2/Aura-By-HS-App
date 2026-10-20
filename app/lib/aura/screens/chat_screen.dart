import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/mock_data.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/shell.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.threadId});
  final String threadId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (AuraStore.i.live) {
      _refresh();
      // Replies from the salon arrive within a few seconds while the chat is open.
      _poll = Timer.periodic(const Duration(seconds: 6), (_) => _refresh());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => AuraStore.i.markRead(widget.threadId));
    AuraStore.i.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AuraStore.i.unread(widget.threadId) > 0) AuraStore.i.markRead(widget.threadId);
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _refresh() async {
    try {
      await AuraStore.i.loadMessages(widget.threadId);
    } on ApiException catch (e) {
      if (mounted && e.needsSignIn) toast(context, e.message, error: true);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    AuraStore.i.removeListener(_onChange);
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final v = (text ?? _c.text).trim();
    if (v.isEmpty || _sending) return;
    setState(() => _sending = true);
    final before = _c.text;
    _c.clear();
    try {
      await AuraStore.i.sendMessage(widget.threadId, v);
    } on ApiException catch (e) {
      _c.text = before;
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1400);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    try {
      await AuraStore.i.sendMessage(widget.threadId, '', imageBytes: bytes, filename: f.name.isEmpty ? 'photo.jpg' : f.name);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PhoneFrame(
      child: ListenableBuilder(
        listenable: AuraStore.i,
        builder: (context, _) {
          final t = AuraStore.i.thread(widget.threadId);
          final msgs = t.messages.reversed.toList();
          final b = t.branchId == null ? null : branchById(t.branchId!);
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Column(children: [
              ScreenHeader(
                back: true,
                title: t.title,
                subtitle: t.readOnly ? 'Official updates · read only' : b != null ? '${b.timings} · usually replies in 15 min' : 'Online · usually replies in 15 min',
              ),
              Expanded(
                child: msgs.isEmpty
                    ? const EmptyState(icon: Icons.forum_outlined, title: 'Say hello 👋', body: 'Ask about availability, prices, packages or share reference photos.')
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) {
                          final m = msgs[i];
                          final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                          final newDay = older == null || older.at.day != m.at.day || older.at.month != m.at.month;
                          return Column(children: [
                            if (newDay)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(20)),
                                  child: Text(_dayLabel(m.at), style: AppText.sans(size: 11, color: AppColors.mutedForeground, weight: FontWeight.w600)),
                                ),
                              ),
                            _Bubble(m: m),
                          ]);
                        },
                      ),
              ),
              if (t.readOnly)
                Container(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.secondary,
                  child: SafeArea(top: false, child: Text('Only Aura by HS can post here. Message the Concierge for help.', textAlign: TextAlign.center, style: AppText.sans(size: 12.5, color: AppColors.mutedForeground))),
                )
              else ...[
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: quickReplies.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Center(child: ChipPill(quickReplies[i], selected: false, onTap: () => _send(quickReplies[i]))),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.border))),
                  child: SafeArea(
                    top: false,
                    child: Row(children: [
                      IconButton(tooltip: 'Attach photo', onPressed: _attach, icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.maroon)),
                      Expanded(
                        child: TextField(
                          controller: _c,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(hintText: 'Type a message', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(tooltip: 'Send', style: IconButton.styleFrom(backgroundColor: AppColors.maroon), onPressed: _send, icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
                    ]),
                  ),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }

  String _dayLabel(DateTime d) {
    final n = DateTime.now();
    final diff = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    return diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : fmtDate(d);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m});
  final ChatMessage m;
  @override
  Widget build(BuildContext context) {
    final mine = m.mine;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width.clamp(0, 480) * 0.78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: mine ? AppColors.maroon : AppColors.card,
            border: mine ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(mine ? 18 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine) Text(m.author, style: AppText.sans(size: 11, weight: FontWeight.w700, color: AppColors.gold)),
            if (m.imagePath != null) Padding(padding: const EdgeInsets.only(top: 4, bottom: 6), child: AuraImage(m.imagePath!, height: 150, width: double.infinity, radius: 12)),
            if (m.imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(m.imageUrl!, height: 170, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image_outlined)))),
                ),
              ),
            if (m.imageBytes != null)
              Padding(padding: const EdgeInsets.only(top: 4, bottom: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(Uint8List.fromList(m.imageBytes!), height: 170, fit: BoxFit.cover))),
            if (m.text.isNotEmpty) Text(m.text, style: AppText.sans(size: 14, color: mine ? Colors.white : AppColors.foreground, height: 1.35)),
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fmtClock(m.at), style: AppText.sans(size: 10, color: mine ? Colors.white70 : AppColors.mutedForeground)),
              if (mine) ...[const SizedBox(width: 4), const Icon(Icons.done_all_rounded, size: 14, color: AppColors.goldLight)],
            ]),
          ]),
        ),
      ),
    );
  }
}
