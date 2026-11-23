import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_request.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/formatters.dart';
import '../services/haptics.dart';
import '../services/photo_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/client_profile_dialog.dart';
import '../widgets/common.dart';
import '../widgets/mini_map.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/status_badge.dart';
import 'request_actions.dart';

/// Conversación con el cliente sobre una solicitud (local, sin servidor).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: AppDurations.medium, curve: Curves.easeOutCubic);
      }
    });
  }

  void _send(AppState state, ServiceRequest r) {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    Haptics.tap(context);
    state.sendMessage(r.id, text);
    _input.clear();
    _scrollToBottom();
  }

  Future<void> _sendPhoto(AppState state, ServiceRequest r) async {
    final path = await PhotoPicker.pick(context, title: 'Enviar foto');
    if (path == null || !mounted) return;
    state.sendPhoto(r.id, path);
    _scrollToBottom();
  }

  Future<void> _shareLocation(AppState state, ServiceRequest r) async {
    final ok = await confirmAction(
      context,
      title: 'Compartir ubicación',
      message:
          'Se agregará a la conversación una ubicación aproximada de demostración (no se usa el GPS).',
      confirmLabel: 'Compartir',
      icon: Icons.near_me_outlined,
    );
    if (!ok || !mounted) return;
    state.shareLocation(r.id);
    _scrollToBottom();
  }

  /// «Confirmar precio»: según el estado abre la propuesta o la confirmación.
  Future<void> _confirmPrice(AppState state, ServiceRequest r) async {
    if (state.canPropose(r).allowed) {
      await RequestActions.propose(context, r);
    } else if (r.status == RequestStatus.aceptada) {
      await RequestActions.confirm(context, r);
    } else {
      showToast(
        context,
        r.status.isScheduled || r.status == RequestStatus.finalizada
            ? 'El precio ya está confirmado: ${Fmt.money(r.agreedPrice ?? 0)} MXN.'
            : state.canPropose(r).reason ?? 'No disponible en este estado.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    _scrollToBottom();
  }

  void _call(ServiceRequest r) {
    showAppSheet<void>(
      context,
      title: 'Llamar a ${r.client.firstName}',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            shadow: false,
            border: AppColors.divider,
            child: Row(
              children: [
                const Icon(Icons.phone_outlined, color: AppColors.primaryStrong),
                const SizedBox(width: 12),
                Expanded(child: Text(r.client.phone, style: AppText.heading)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Las llamadas se realizan desde la app de teléfono de tu dispositivo. Copia el número para marcar.',
            style: AppText.body,
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Copiar número',
            icon: Icons.copy_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: r.client.phone));
              if (ctx.mounted) {
                showToast(ctx, 'Número copiado.');
                Navigator.of(ctx).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = state.byId(widget.requestId);
    if (r == null) {
      return const Scaffold(body: Center(child: Text('Conversación no encontrada')));
    }
    final chatCheck = state.canChat(r);
    final messages = r.messages.reversed.toList();
    final pad = AppSpacing.screen(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _ChatHeader(
            request: r,
            onBack: () => Navigator.of(context).maybePop(),
            onCall: chatCheck.allowed ? () => _call(r) : null,
            onProfile: () => showClientProfile(context, r),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
              itemCount: messages.length + 1,
              itemBuilder: (context, i) {
                if (i == messages.length) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Pill(
                          label: 'Conversación sobre «${r.cleaningType}»',
                          background: AppColors.mint,
                          foreground: AppColors.successFg,
                          icon: Icons.forum_outlined,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Demostración: los mensajes se guardan solo en este dispositivo.',
                          textAlign: TextAlign.center,
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  );
                }
                final m = messages[i];
                return FadeSlideIn(
                  key: ValueKey(m.id),
                  offset: 10,
                  child: _MessageBubble(
                    message: m,
                    request: r,
                    now: state.now,
                    onAcceptOffer: () =>
                        RequestActions.acceptCounterOffer(context, r),
                  ),
                );
              },
            ),
          ),
          if (chatCheck.allowed) ...[
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: pad),
                children: [
                  _QuickChip(
                    icon: Icons.sell_outlined,
                    label: r.status == RequestStatus.aceptada
                        ? 'Confirmar servicio'
                        : 'Confirmar precio',
                    onTap: () => _confirmPrice(state, r),
                  ),
                  _QuickChip(
                    icon: Icons.near_me_outlined,
                    label: 'Compartir ubicación',
                    onTap: () => _shareLocation(state, r),
                  ),
                  _QuickChip(
                    icon: Icons.photo_camera_outlined,
                    label: 'Enviar foto',
                    onTap: () => _sendPhoto(state, r),
                  ),
                ],
              ),
            ),
            _InputBar(
              controller: _input,
              hasText: _hasText,
              onAttach: () => _sendPhoto(state, r),
              onSend: () => _send(state, r),
            ),
          ] else
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 4, pad, 12),
                child: NoticeBox(
                  icon: Icons.lock_outline_rounded,
                  message: chatCheck.reason!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.request,
    required this.onBack,
    required this.onCall,
    required this.onProfile,
  });

  final ServiceRequest request;
  final VoidCallback onBack;
  final VoidCallback? onCall;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final c = request.client;
    return Container(
      padding: EdgeInsets.fromLTRB(
          10, MediaQuery.paddingOf(context).top + 8, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Regresar',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.ink),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: onProfile,
              child: Row(
                children: [
                  AvatarCircle(initials: c.initials, size: 46),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.heading),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(request.cleaningType,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption),
                            ),
                            const SizedBox(width: 6),
                            StatusBadge(request: request),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          CircleIconButton(
            icon: Icons.phone_in_talk_outlined,
            tooltip: 'Llamar',
            background: AppColors.ice,
            onPressed: onCall,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.request,
    required this.now,
    required this.onAcceptOffer,
  });

  final ChatMessage message;
  final ServiceRequest request;
  final DateTime now;
  final VoidCallback onAcceptOffer;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.kind == MessageKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.fade(AppColors.mint, 0.8),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(m.text,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(
                    color: AppColors.successFg, fontWeight: FontWeight.w500)),
          ),
        ),
      );
    }

    final mine = m.fromWorker;
    final bg = mine ? AppColors.primaryStrong : Colors.white;
    final fg = mine ? Colors.white : AppColors.ink;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;

    Widget content = const SizedBox.shrink();
    switch (m.kind) {
      case MessageKind.price:
        final isCurrentOffer = !mine &&
            request.status == RequestStatus.enNegociacion &&
            request.clientOffer == m.amount;
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(mine ? Icons.sell_outlined : Icons.swap_horiz_rounded,
                    size: 16, color: fg),
                const SizedBox(width: 6),
                Text(m.text, style: AppText.caption.copyWith(color: fg)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${Fmt.money(m.amount ?? 0)} MXN',
                style: AppText.title.copyWith(color: fg)),
            if (isCurrentOffer) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: FilledButton(
                  onPressed: onAcceptOffer,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryStrong,
                    shape: const StadiumBorder(),
                  ),
                  child: Text('Aceptar contraoferta',
                      style: AppText.label.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ],
        );
      case MessageKind.location:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: maxWidth - 28,
              child: MiniMap(exact: true, height: 110, seed: m.id.hashCode),
            ),
            const SizedBox(height: 6),
            Text('Mi ubicación (demostración)',
                style: AppText.caption.copyWith(color: fg)),
          ],
        );
      case MessageKind.photo:
        final path = m.imagePath ?? '';
        content = GestureDetector(
          onTap: () => showPhotoGallery(context, [path]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: maxWidth - 28,
              height: 160,
              child: AppImage(path: path, isAsset: m.imageIsAsset, cacheWidth: 600),
            ),
          ),
        );
      case MessageKind.text:
      case MessageKind.system:
        content = Text(m.text, style: AppText.bodyStrong.copyWith(color: fg));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(mine ? 20 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 20),
                ),
                boxShadow: mine ? null : AppShadows.soft,
              ),
              child: content,
            ),
          ),
          const SizedBox(height: 3),
          Text(Fmt.ago(m.time, now), style: AppText.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: AppColors.successFg),
        label: Text(label),
        labelStyle: AppText.caption.copyWith(
            color: AppColors.successFg, fontWeight: FontWeight.w700),
        backgroundColor: AppColors.mint,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        onPressed: () {
          Haptics.tap(context);
          onTap();
        },
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.onAttach,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool hasText;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(pad, 6, pad, 10),
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadows.lifted,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Adjuntar foto',
              onPressed: onAttach,
              icon: const Icon(Icons.attach_file_rounded, color: AppColors.inkSoft),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: AppText.bodyStrong,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje…',
                  hintStyle: AppText.body,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            AnimatedScale(
              scale: hasText ? 1 : 0.85,
              duration: AppDurations.fast,
              child: CircleIconButton(
                icon: Icons.send_rounded,
                tooltip: 'Enviar',
                size: 44,
                background: hasText ? AppColors.primaryStrong : AppColors.cloud,
                foreground: Colors.white,
                onPressed: hasText ? onSend : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
