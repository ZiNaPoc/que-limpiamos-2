import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/service_catalog.dart';
import '../navigation/app_routes.dart';
import '../services/api_client.dart'; // ApiException
import '../services/haptics.dart';
import '../services/session.dart'; // Session
import '../services/solicitud_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'avisos_screen.dart';
import 'service_request_data.dart';

enum _Metodo { tarjeta, efectivo }

/// Paso 5: pago. Se llega desde «Tu cotización».
///
/// Al confirmar se guarda la solicitud en el backend (igual que antes hacía
/// la cotización) y se muestra la confirmación.
///
/// El cobro con tarjeta es SIMULADO: los datos de la tarjeta solo se validan
/// en el teléfono; no se envían ni se guardan.
class PagoScreen extends StatefulWidget {
  const PagoScreen({super.key, required this.request});

  final ServiceRequestData request;

  @override
  State<PagoScreen> createState() => _PagoScreenState();
}

class _PagoScreenState extends State<PagoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _numero = TextEditingController();
  final TextEditingController _titular = TextEditingController();
  final TextEditingController _vence = TextEditingController();
  final TextEditingController _cvv = TextEditingController();

  _Metodo _metodo = _Metodo.tarjeta;
  bool _enviando = false;

  ServiceRequestData get request => widget.request;

  /// Monto que se manda como `total` al backend (precio mínimo estimado).
  int get _total => request.priceMin;

  bool get _conTarjeta => _metodo == _Metodo.tarjeta;

  @override
  void dispose() {
    _numero.dispose();
    _titular.dispose();
    _vence.dispose();
    _cvv.dispose();
    super.dispose();
  }

  // ───────────────────────── VALIDACIONES ─────────────────────────

  static bool _luhn(String digits) {
    var suma = 0;
    var doble = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = digits.codeUnitAt(i) - 48;
      if (doble) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      suma += n;
      doble = !doble;
    }
    return suma % 10 == 0;
  }

  String? _validarNumero(String? v) {
    final d = (v ?? '').replaceAll(' ', '');
    if (d.isEmpty) return 'Escribe el número de tu tarjeta.';
    if (d.length < 15) return 'El número debe tener 15 o 16 dígitos.';
    if (!_luhn(d)) return 'Revisa el número de tu tarjeta.';
    return null;
  }

  String? _validarTitular(String? v) {
    if ((v ?? '').trim().length < 3) {
      return 'Escribe el nombre como aparece en la tarjeta.';
    }
    return null;
  }

  String? _validarVence(String? v) {
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch((v ?? '').trim());
    if (m == null) return 'Usa el formato MM/AA.';
    final mes = int.parse(m.group(1)!);
    final anio = 2000 + int.parse(m.group(2)!);
    if (mes < 1 || mes > 12) return 'El mes no es válido.';
    // Vence al terminar el mes indicado.
    if (!DateTime(anio, mes + 1).isAfter(DateTime.now())) {
      return 'La tarjeta está vencida.';
    }
    return null;
  }

  String? _validarCvv(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 3 || t.length > 4) return 'De 3 o 4 dígitos.';
    return null;
  }

  void _usarTarjetaPrueba() {
    final anio = (DateTime.now().year + 2) % 100;
    setState(() {
      _numero.text = '4242 4242 4242 4242';
      _titular.text = Session.instance.user?.nombre ?? 'Cliente de prueba';
      _vence.text = '12/${anio.toString().padLeft(2, '0')}';
      _cvv.text = '123';
    });
  }

  // ───────────────────────── PAGO Y ENVÍO ─────────────────────────

  Future<void> _pagar() async {
    if (_enviando) return; // evita dobles toques
    FocusScope.of(context).unfocus();

    final user = Session.instance.user;
    if (user == null) {
      showToast(context, 'Inicia sesión con tu cuenta para enviar la solicitud.',
          error: true);
      return;
    }

    final conTarjeta = _conTarjeta;
    if (conTarjeta && !(_formKey.currentState?.validate() ?? false)) {
      showToast(context, 'Revisa los datos de tu tarjeta.', error: true);
      return;
    }

    setState(() => _enviando = true);
    try {
      if (conTarjeta) {
        // Cobro simulado. Aquí iría la pasarela de pago real.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      // Guarda el inmueble y la solicitud en la base de datos.
      await SolicitudApi.crear(request, clienteId: user.id);
      if (!mounted) return;
      Haptics.success(context);
      setState(() => _enviando = false);
      await _terminar(conTarjeta);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      showToast(context, e.message, error: true);
    } catch (e, st) {
      debugPrint('[pago] ERROR inesperado: $e\n$st');
      if (!mounted) return;
      setState(() => _enviando = false);
      showToast(context, 'No se pudo enviar la solicitud. Intenta de nuevo.',
          error: true);
    }
  }

  Future<void> _terminar(bool conTarjeta) async {
    final colaborador = request.collaborator;
    final aviso = colaborador != null
        ? 'Te avisaremos en «Avisos» cuando $colaborador confirme tu servicio.'
        : 'Te avisaremos en «Avisos» cuando asignemos a tu colaborador.';
    final mensaje = conTarjeta
        ? 'Pagaste ${money(_total)} MXN. $aviso'
        : 'Pagarás en efectivo al terminar el servicio. $aviso';

    final verAvisos = await showAppDialog<bool>(
      context,
      dismissible: false,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              builder: (context, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                    color: AppColors.mint, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 40, color: AppColors.successFg),
              ),
            ),
            const SizedBox(height: 14),
            Text(conTarjeta ? '¡Pago realizado!' : '¡Solicitud enviada!',
                style: AppText.title, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(mensaje, textAlign: TextAlign.center, style: AppText.body),
            const SizedBox(height: 18),
            AppButton(
              label: 'Ver mis avisos',
              icon: Icons.notifications_none_rounded,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Ir al inicio',
                  style: AppText.label.copyWith(color: AppColors.inkSoft)),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    final nav = Navigator.of(context);
    if (verAvisos == true) {
      // Igual que la barra inferior: abre Avisos y limpia la pila.
      nav.pushAndRemoveUntil(
        AppRoutes.fade(const AvisosScreen()),
        (route) => false,
      );
    } else {
      // Regresa al inicio para no enviar la misma solicitud dos veces.
      nav.popUntil((route) => route.isFirst);
    }
  }

  // ───────────────────────── INTERFAZ ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);

    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        body: WaveBackground(
          headerHeight: 190,
          child: Column(
            children: [
              Expanded(
                // SingleChildScrollView (no ListView) para que todos los
                // campos sigan montados y el Form los valide.
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const StepHeader(
                          title: 'Pago',
                          step: 5,
                          subtitle: 'Elige cómo quieres pagar.',
                        ),
                        const SizedBox(height: 20),

                        // TOTAL
                        FadeSlideIn(child: _TotalCard(request: request)),
                        const SizedBox(height: 22),

                        // MÉTODO
                        Text('Método de pago', style: AppText.heading),
                        const SizedBox(height: 10),
                        _MetodoOption(
                          icon: Icons.credit_card_rounded,
                          title: 'Tarjeta de crédito o débito',
                          subtitle: 'Paga ahora desde la app',
                          selected: _metodo == _Metodo.tarjeta,
                          onTap: _enviando
                              ? null
                              : () =>
                                  setState(() => _metodo = _Metodo.tarjeta),
                        ),
                        const SizedBox(height: 10),
                        _MetodoOption(
                          icon: Icons.payments_outlined,
                          title: 'Efectivo',
                          subtitle: 'Pagas a tu colaborador al terminar',
                          selected: _metodo == _Metodo.efectivo,
                          onTap: _enviando
                              ? null
                              : () =>
                                  setState(() => _metodo = _Metodo.efectivo),
                        ),
                        const SizedBox(height: 22),

                        // DETALLE DEL MÉTODO
                        AnimatedSize(
                          duration: AppDurations.medium,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _conTarjeta
                              ? _formTarjeta()
                              : _infoEfectivo(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _BarraPago(
                total: _total,
                label: _conTarjeta ? 'Pagar ahora' : 'Confirmar',
                loading: _enviando,
                onPressed: _pagar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formTarjeta() {
    return Column(
      key: const ValueKey('tarjeta'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TarjetaVista(
          numero: _numero.text,
          titular: _titular.text,
          vence: _vence.text,
        ),
        const SizedBox(height: 18),
        AppTextField(
          label: 'Número de tarjeta',
          hint: '0000 0000 0000 0000',
          controller: _numero,
          editable: !_enviando,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.creditCardNumber],
          prefixIcon: Icons.credit_card_rounded,
          inputFormatters: [_NumeroTarjetaFormatter()],
          validator: _validarNumero,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Nombre del titular',
          hint: 'Como aparece en la tarjeta',
          controller: _titular,
          editable: !_enviando,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.creditCardName],
          prefixIcon: Icons.person_outline_rounded,
          validator: _validarTitular,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: 'Vencimiento',
                hint: 'MM/AA',
                controller: _vence,
                editable: !_enviando,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.creditCardExpirationDate],
                prefixIcon: Icons.event_outlined,
                inputFormatters: [_VencimientoFormatter()],
                validator: _validarVence,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: 'CVV',
                hint: '123',
                controller: _cvv,
                editable: !_enviando,
                obscure: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.creditCardSecurityCode],
                prefixIcon: Icons.lock_outline_rounded,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                validator: _validarCvv,
                onSubmitted: (_) => _pagar(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: AppLinkButton(
            label: 'Usar tarjeta de prueba',
            fontSize: 12,
            onPressed: _enviando ? null : _usarTarjetaPrueba,
          ),
        ),
        const SizedBox(height: 6),
        const NoticeBox(
          icon: Icons.shield_outlined,
          message:
              'Pago de demostración: no se hace ningún cargo y los datos de tu tarjeta no se envían ni se guardan.',
        ),
      ],
    );
  }

  Widget _infoEfectivo() {
    return Column(
      key: const ValueKey('efectivo'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: AppColors.fade(AppColors.mint, 0.55),
          shadow: false,
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.payments_outlined,
                    color: AppColors.successFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pago al terminar', style: AppText.subtitle),
                    const SizedBox(height: 2),
                    Text(
                      'Le pagas a tu colaborador en efectivo cuando termine la limpieza.',
                      style: AppText.caption.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const NoticeBox(
          message:
              'El monto final lo confirma tu colaborador al revisar el servicio.',
        ),
      ],
    );
  }
}

// ───────────────────────── WIDGETS ─────────────────────────

/// Total a pagar con el rango estimado y los datos clave de la solicitud.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.request});

  final ServiceRequestData request;

  @override
  Widget build(BuildContext context) {
    final colaborador = request.collaborator ?? 'Asignación automática';
    final dato = AppText.caption.copyWith(color: AppColors.ink);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Total estimado', style: AppText.caption)),
              Pill(
                label: request.serviceTitle,
                background: AppColors.ice,
                foreground: AppColors.primaryStrong,
                dense: true,
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: money(request.priceMin),
                style: AppText.display.copyWith(color: AppColors.primaryStrong),
                children: [
                  TextSpan(
                    text: ' MXN',
                    style:
                        AppText.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          Text(
            'Puede ajustarse hasta ${money(request.priceMax)} al confirmar el precio final.',
            style: AppText.caption,
          ),
          const Divider(height: 22, color: AppColors.divider),
          Row(
            children: [
              const Icon(Icons.event_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${request.dateText} · ${request.timeText}',
                    style: dato),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(colaborador,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: dato),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opción de método de pago (estilo radio).
class _MetodoOption extends StatelessWidget {
  const _MetodoOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      color: selected ? AppColors.ice : Colors.white,
      border: selected ? AppColors.primary : AppColors.divider,
      shadow: selected,
      radius: AppRadius.lg,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppDurations.medium,
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryStrong : AppColors.ice,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 22,
                color: selected ? Colors.white : AppColors.primaryStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.bodyStrong
                        .copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: AppText.caption.copyWith(color: AppColors.inkSoft)),
              ],
            ),
          ),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? AppColors.primaryStrong : AppColors.inkMuted,
          ),
        ],
      ),
    );
  }
}

/// Vista previa de la tarjeta con los datos que se van escribiendo.
class _TarjetaVista extends StatelessWidget {
  const _TarjetaVista({
    required this.numero,
    required this.titular,
    required this.vence,
  });

  final String numero;
  final String titular;
  final String vence;

  static String _marca(String d) {
    if (d.startsWith('4')) return 'VISA';
    if (d.startsWith('5') || d.startsWith('2')) return 'MASTERCARD';
    if (d.startsWith('34') || d.startsWith('37')) return 'AMEX';
    return '';
  }

  static String _numeroVisible(String d) {
    final relleno = d.padRight(16, '•');
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i > 0 && i % 4 == 0) b.write('  ');
      b.write(relleno[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final digitos = numero.replaceAll(' ', '');
    final etiqueta = AppText.overline
        .copyWith(color: AppColors.frost, fontSize: 10, letterSpacing: 1);
    final valor = AppText.label.copyWith(color: Colors.white);

    return AspectRatio(
      aspectRatio: 1.7,
      child: HeroPanel(
        seed: 21,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.fade(Colors.white, 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.memory_rounded,
                      size: 20, color: AppColors.primaryStrong),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: AppDurations.fast,
                  child: Text(
                    _marca(digitos),
                    key: ValueKey(_marca(digitos)),
                    style: AppText.heading
                        .copyWith(color: Colors.white, letterSpacing: 1),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _numeroVisible(digitos),
                style: AppText.title
                    .copyWith(color: Colors.white, letterSpacing: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TITULAR', style: etiqueta),
                      Text(
                        titular.trim().isEmpty
                            ? 'NOMBRE APELLIDO'
                            : titular.trim().toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: valor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('VENCE', style: etiqueta),
                    Text(vence.isEmpty ? 'MM/AA' : vence, style: valor),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra inferior con el total y el botón de pagar/confirmar.
class _BarraPago extends StatelessWidget {
  const _BarraPago({
    required this.total,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final int total;
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          22, 16, 18, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(
            color: AppColors.fade(AppColors.primaryStrong, 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total', style: AppText.caption),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      text: money(total),
                      style: AppText.title.copyWith(fontSize: 24),
                      children: [
                        TextSpan(
                          text: ' MXN',
                          style: AppText.caption
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: label,
            icon: Icons.lock_rounded,
            expand: false,
            height: 48,
            loading: loading,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── FORMATOS ─────────────────────────

/// «4242424242424242» → «4242 4242 4242 4242» (máx. 16 dígitos).
class _NumeroTarjetaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 16) d = d.substring(0, 16);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(d[i]);
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// «1228» → «12/28».
class _VencimientoFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 4) d = d.substring(0, 4);
    final text = d.length > 2 ? '${d.substring(0, 2)}/${d.substring(2)}' : d;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}