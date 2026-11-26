import 'package:flutter/material.dart';

import '../services/ciclo_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';
import 'service_request_data.dart';

/// «Mis inmuebles» (docs/backend/25 v2 §3): sin límite, cada uno con nombre. Editar o eliminar
/// (archivar) un inmueble NUNCA cambia las solicitudes que ya lo usaron: cada una tiene su copia.
class MisInmueblesScreen extends StatefulWidget {
  const MisInmueblesScreen({super.key});

  @override
  State<MisInmueblesScreen> createState() => _MisInmueblesScreenState();
}

class _MisInmueblesScreenState extends State<MisInmueblesScreen> {
  List<Inmueble>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final l = await InmueblesApi.listar();
      if (mounted) setState(() => _lista = l);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDelCiclo(e));
    }
  }

  Future<void> _editar([Inmueble? actual]) async {
    final r = await showModalBottomSheet<(String, PropertyData)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FormularioInmueble(actual: actual),
    );
    if (r == null || !mounted) return;
    try {
      if (actual == null) {
        await InmueblesApi.crear(r.$1, r.$2);
      } else {
        await InmueblesApi.editar(actual.id, r.$1, r.$2);
      }
      if (!mounted) return;
      showToast(context, actual == null ? 'Inmueble guardado.' : 'Inmueble actualizado. Tus solicitudes anteriores no cambian.');
      await _cargar();
    } catch (e) {
      if (mounted) showToast(context, mensajeDelCiclo(e), error: true);
    }
  }

  Future<void> _eliminar(Inmueble i) async {
    final ok = await confirmAction(context, title: 'Eliminar «${i.nombre}»', message: 'Ya no aparecerá en tu lista. Las solicitudes que lo usaron conservan sus datos.', confirmLabel: 'Eliminar', destructive: true);
    if (!ok) return;
    try {
      await InmueblesApi.eliminar(i.id);
      if (!mounted) return;
      showToast(context, 'Inmueble eliminado.');
      await _cargar();
    } catch (e) {
      if (mounted) showToast(context, mensajeDelCiclo(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);
    final lista = _lista;
    return Scaffold(
      body: WaveBackground(
        headerHeight: 190,
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, MediaQuery.paddingOf(context).bottom + 28),
            children: [
              const StepHeader(title: 'Mis inmuebles', subtitle: 'Guárdalos para pedir más rápido.'),
              const SizedBox(height: 16),
              if (_error != null) NoticeBox.error(message: _error!, action: AppLinkButton(label: 'Reintentar', onPressed: _cargar)),
              if (lista == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (lista != null && lista.isEmpty)
                const EmptyState(icon: Icons.home_work_outlined, title: 'Aún no tienes inmuebles', message: 'Guarda tu casa, oficina o departamento con un nombre.'),
              for (final i in lista ?? const <Inmueble>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(children: [
                      const Icon(Icons.home_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i.nombre, style: AppText.bodyStrong),
                          Text(i.resumen, style: AppText.caption),
                          Text(i.direccion, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _editar(i)),
                      IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _eliminar(i)),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              AppButton(label: 'Agregar inmueble', icon: Icons.add_rounded, onPressed: () => _editar()),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormularioInmueble extends StatefulWidget {
  const _FormularioInmueble({this.actual});

  final Inmueble? actual;

  @override
  State<_FormularioInmueble> createState() => _FormularioInmuebleState();
}

class _FormularioInmuebleState extends State<_FormularioInmueble> {
  late final TextEditingController _nombre = TextEditingController(text: widget.actual?.nombre ?? '');
  late final TextEditingController _direccion = TextEditingController(text: widget.actual?.direccion ?? '');
  late String _tipo = widget.actual?.tipoApp ?? 'Casa';
  late final List<int> _n = [widget.actual?.habitaciones ?? 1, widget.actual?.banos ?? 1, widget.actual?.mediosBanos ?? 0, widget.actual?.pisos ?? 1];
  String? _error;

  static const _etiquetas = ['Habitaciones', 'Baños completos', 'Medios baños', 'Pisos o niveles'];
  static const _minimos = [0, 0, 0, 1];
  static const _maximos = [20, 20, 20, 10];

  @override
  void dispose() {
    _nombre.dispose();
    _direccion.dispose();
    super.dispose();
  }

  void _guardar() {
    final nombre = _nombre.text.trim();
    final direccion = _direccion.text.trim();
    if (nombre.isEmpty) return setState(() => _error = 'Ponle un nombre (p. ej. «Casa Playa»).');
    if (direccion.length < 5) return setState(() => _error = 'Escribe la dirección completa.');
    Navigator.of(context).pop((nombre, PropertyData(type: _tipo, rooms: _n[0], fullBaths: _n[1], halfBaths: _n[2], floors: _n[3], address: direccion)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.actual == null ? 'Nuevo inmueble' : 'Editar inmueble', style: AppText.title),
            const SizedBox(height: 12),
            TextField(controller: _nombre, maxLength: 100, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Airbnb Centro')),
            Wrap(spacing: 8, children: [
              for (final t in const ['Casa', 'Oficina', 'Departamento']) ChoiceChip(label: Text(t), selected: _tipo == t, onSelected: (_) => setState(() => _tipo = t)),
            ]),
            for (var i = 0; i < 4; i++)
              Row(children: [
                Expanded(child: Text(_etiquetas[i])),
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: _n[i] > _minimos[i] ? () => setState(() => _n[i]--) : null),
                Text('${_n[i]}', style: AppText.bodyStrong),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _n[i] < _maximos[i] ? () => setState(() => _n[i]++) : null),
              ]),
            TextField(controller: _direccion, maxLength: 255, maxLines: 2, decoration: const InputDecoration(labelText: 'Dirección')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: AppText.caption.copyWith(color: Colors.red))),
            const SizedBox(height: 12),
            AppButton(label: 'Guardar', icon: Icons.check_rounded, onPressed: _guardar),
          ],
        ),
      ),
    );
  }
}
