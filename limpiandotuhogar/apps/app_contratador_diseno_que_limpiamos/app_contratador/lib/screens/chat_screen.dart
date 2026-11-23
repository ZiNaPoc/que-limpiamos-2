import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/organic.dart';

class _Msg {
  const _Msg(this.texto, {required this.mio, this.saludo = false});

  final String texto;
  final bool mio;
  final bool saludo; // el primer mensaje lleva el nombre en cursiva
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.nombre = 'Colaborador'});

  final String nombre;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_Msg> _mensajes = [
    const _Msg('', mio: false, saludo: true),
    const _Msg('Hola. Tengo dos mascotas en casa, solo para avisar.',
        mio: true),
    const _Msg('Perfecto, lo tomo en cuenta', mio: false),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _iniciales {
    final partes = widget.nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  int get _seed => widget.nombre.codeUnits.fold<int>(0, (a, b) => a + b);

  void _bajar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Agrega mi mensaje y simula la respuesta del colaborador
  void _enviar(String texto, {String? respuesta}) {
    final t = texto.trim();
    if (t.isEmpty) return;

    setState(() => _mensajes.add(_Msg(t, mio: true)));
    _controller.clear();
    _bajar();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _mensajes.add(
          _Msg(respuesta ?? 'Perfecto, lo tomo en cuenta', mio: false),
        );
      });
      _bajar();
    });
  }

  void _llamar() {
    showToast(context, 'Llamando a ${widget.nombre}...',
        icon: Icons.phone_in_talk_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _encabezado(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(pad, 14, pad, 14),
              itemCount: _mensajes.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _avisoAsignado(),
                  );
                }
                final m = _mensajes[i - 1];
                return FadeSlideIn(
                  key: ValueKey('msg-${i - 1}'),
                  offset: 10,
                  child: _Burbuja(mensaje: m, nombre: widget.nombre),
                );
              },
            ),
          ),
          _chipsRapidos(),
          _BarraEscribir(
            controller: _controller,
            onSend: () => _enviar(_controller.text),
            onSubmitted: (v) => _enviar(v),
          ),
        ],
      ),
    );
  }

  Widget _encabezado() {
    return Container(
      padding:
          EdgeInsets.fromLTRB(6, MediaQuery.paddingOf(context).top + 8, 14, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ice, AppColors.frost],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Regresar',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.ink),
          ),
          BlobAvatar(
            seed: _seed,
            initials: _iniciales,
            icon: _iniciales.isEmpty ? Icons.person_outline_rounded : null,
            size: 48,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.heading),
                Text('Tu colaborador', style: AppText.caption),
              ],
            ),
          ),
          CircleIconButton(
            icon: Icons.phone_in_talk_outlined,
            tooltip: 'Llamar',
            onPressed: _llamar,
          ),
        ],
      ),
    );
  }

  Widget _avisoAsignado() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text.rich(
          TextSpan(
            style: AppText.caption.copyWith(
                color: AppColors.successFg, fontWeight: FontWeight.w700),
            children: [
              const TextSpan(text: 'Se asignó a '),
              TextSpan(
                text: widget.nombre,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              const TextSpan(text: ' a tu servicio'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _chipsRapidos() {
    final pad = AppSpacing.screen(context);
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        children: [
          _ChipRapido(
            icon: Icons.payments_outlined,
            label: 'Confirmar precio',
            onTap: () => _enviar(
              '¿Me confirmas el precio del servicio?',
              respuesta: 'Claro, el total acordado es de \$350. ¿Te parece bien?',
            ),
          ),
          _ChipRapido(
            icon: Icons.near_me_outlined,
            label: 'Compartir ubicación',
            onTap: () => _enviar(
              '📍 Ubicación compartida',
              respuesta: 'Recibida, ya tengo tu ubicación',
            ),
          ),
          _ChipRapido(
            icon: Icons.photo_camera_outlined,
            label: 'Enviar foto',
            onTap: () => _enviar(
              '📷 Foto enviada',
              respuesta: 'Gracias por la foto, la reviso',
            ),
          ),
        ],
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje, required this.nombre});

  final _Msg mensaje;
  final String nombre;

  @override
  Widget build(BuildContext context) {
    final m = mensaje;
    final mio = m.mio;
    final bg = mio ? AppColors.primaryStrong : AppColors.frost;
    final fg = mio ? Colors.white : AppColors.ink;
    final base = AppText.bodyStrong.copyWith(color: fg);

    final Widget contenido = m.saludo
        ? Text.rich(
            TextSpan(
              style: base,
              children: [
                const TextSpan(text: 'Hola, soy '),
                TextSpan(
                  text: nombre,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                const TextSpan(
                    text: ' ¿Hay algo que deba de saber antes de llegar?'),
              ],
            ),
          )
        : Text(m.texto, style: base);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Align(
        alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.76,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(22),
                topRight: const Radius.circular(22),
                bottomLeft: Radius.circular(mio ? 22 : 6),
                bottomRight: Radius.circular(mio ? 6 : 22),
              ),
              boxShadow: AppShadows.soft,
            ),
            child: contenido,
          ),
        ),
      ),
    );
  }
}

class _ChipRapido extends StatelessWidget {
  const _ChipRapido(
      {required this.icon, required this.label, required this.onTap});

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
        labelStyle: AppText.caption
            .copyWith(color: AppColors.successFg, fontWeight: FontWeight.w700),
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

class _BarraEscribir extends StatelessWidget {
  const _BarraEscribir({
    required this.controller,
    required this.onSend,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onSubmitted;

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
            const Padding(
              padding: EdgeInsets.all(12),
              child:
                  Icon(Icons.attach_file_rounded, color: AppColors.inkSoft),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: onSubmitted,
                style: AppText.bodyStrong,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  hintStyle: AppText.body,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final has = value.text.trim().isNotEmpty;
                return AnimatedScale(
                  scale: has ? 1 : 0.85,
                  duration: AppDurations.fast,
                  child: CircleIconButton(
                    icon: Icons.send_rounded,
                    tooltip: 'Enviar',
                    background: has ? AppColors.primaryStrong : AppColors.cloud,
                    foreground: Colors.white,
                    onPressed: has ? onSend : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
