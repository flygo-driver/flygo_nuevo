// lib/pantallas/admin/admin_negocios_aliados.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_codigo.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_letrero_export.dart';
import 'package:flygo_nuevo/servicios/negocios_aliados_repo.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_negocio_aliado_detalle.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';

class AdminNegociosAliados extends StatefulWidget {
  const AdminNegociosAliados({super.key});

  @override
  State<AdminNegociosAliados> createState() => _AdminNegociosAliadosState();
}

class _AdminNegociosAliadosState extends State<AdminNegociosAliados> {
  final _nombreCtrl = TextEditingController();
  final _ciudadCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  bool _guardando = false;
  String _buscar = '';

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _ciudadCtrl.dispose();
    _telCtrl.dispose();
    _codigoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  void _previewCodigo() {
    final auto = NegocioAliadoCodigo.generarDesdeNombreCiudad(
      nombre: _nombreCtrl.text,
      ciudad: _ciudadCtrl.text,
    );
    if (_codigoCtrl.text.trim().isEmpty) {
      _codigoCtrl.text = auto;
    }
    setState(() {});
  }

  Future<void> _crearNegocio() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _snack('Escribe el nombre del negocio.');
      return;
    }
    final ciudad = _ciudadCtrl.text.trim();
    if (ciudad.isEmpty) {
      _snack('Indica el pueblo/ciudad del negocio (necesario para la promo 6.º gratis).');
      return;
    }
    if (_guardando) return;

    setState(() => _guardando = true);
    NegocioAliado? creado;
    try {
      creado = await NegociosAliadosRepo.crear(
        nombre: nombre,
        ciudad: ciudad,
        telefonoContacto: _telCtrl.text.trim(),
        notas: _notasCtrl.text.trim(),
        codigoPreferido: _codigoCtrl.text.trim().isEmpty
            ? null
            : NegocioAliadoCodigo.normalizar(_codigoCtrl.text),
      );
    } catch (e) {
      if (mounted) _snack('Error: $e');
      return;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }

    if (!mounted || creado == null) return;

    _nombreCtrl.clear();
    _ciudadCtrl.clear();
    _telCtrl.clear();
    _codigoCtrl.clear();
    _notasCtrl.clear();
    _snack('Negocio creado: ${creado.codigo}');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mostrarDetalle(creado!);
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _mostrarDetalle(NegocioAliado negocio) async {
    final url = NegocioAliadoConfig.urlDescarga(negocio.codigo);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(negocio.nombre.isEmpty ? negocio.codigo : negocio.nombre),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: url,
                size: 180,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              SelectableText(url, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                'Código: ${negocio.codigo}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Promo: ${NegocioAliadoConfig.promoViajesM} viajes + '
                '${NegocioAliadoConfig.promoViajesK} gratis · '
                '${NegocioAliadoConfig.vigenciaDias} días',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              _snack('Enlace copiado.');
            },
            child: const Text('Copiar enlace'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await NegocioAliadoLetreroExport.descargarPdf(negocio);
              } catch (e) {
                if (mounted) _snack('No se pudo generar PDF: $e');
              }
            },
            child: const Text('Descargar letrero PDF'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdminAppBar(title: 'Negocios aliados (QR)'),
      drawer: const AdminDrawer(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminUi.infoFill(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminUi.infoBorder(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crear negocio aliado',
                            style: AdminUi.titleStyle(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '1. Nombre y ciudad → código automático.\n'
                            '2. Guardar → descarga PDF del letrero.\n'
                            '3. Imprenta A4 color, plastificado.\n'
                            '4. Cliente escanea → 5 viajes + 1 gratis (90 días).',
                            style: AdminUi.bodyStyle(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del negocio *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _previewCodigo(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ciudadCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pueblo / ciudad *',
                        border: OutlineInputBorder(),
                        helperText:
                            'Promo 6.º gratis solo viajes dentro de este pueblo',
                      ),
                      onChanged: (_) => _previewCodigo(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _codigoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Código QR (auto)',
                        border: OutlineInputBorder(),
                        helperText: 'Se genera del nombre; puedes editarlo',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _telCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono contacto',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notasCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notas internas',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Promo fija: ${NegocioAliadoConfig.promoViajesM} viajes + '
                      '${NegocioAliadoConfig.promoViajesK} gratis · '
                      '${NegocioAliadoConfig.vigenciaDias} días\n'
                      'Comisión negocio: ${NegocioAliadoConfig.pctComisionNegocio}% · '
                      'Taxista en esos viajes: ${NegocioAliadoConfig.pctComisionTaxistaReferido}%',
                      style: AdminUi.bodyStyle(context),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _crearNegocio,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_business_outlined),
                      label: const Text('Guardar y generar QR'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar negocio…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _buscar = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<List<NegocioAliado>>(
                      stream: NegociosAliadosRepo.streamTodos(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        var lista = snap.data ?? <NegocioAliado>[];
                        if (_buscar.isNotEmpty) {
                          lista = lista
                              .where(
                                (n) =>
                                    n.nombre.toLowerCase().contains(_buscar) ||
                                    n.codigo.toLowerCase().contains(_buscar) ||
                                    n.ciudad.toLowerCase().contains(_buscar),
                              )
                              .toList();
                        }
                        if (lista.isEmpty) {
                          return const Center(
                            child: Text('Sin negocios aliados aún.'),
                          );
                        }
                        return ListView.separated(
                          itemCount: lista.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final n = lista[i];
                            return ListTile(
                              title: Text(
                                n.nombre.isEmpty ? n.codigo : n.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${n.codigo} · ${n.ciudad.isEmpty ? "—" : n.ciudad}\n'
                                'Clientes: ${n.clientesReferidos} · Viajes: ${n.viajesReferidos}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    n.activo
                                        ? Icons.check_circle
                                        : Icons.pause_circle_outline,
                                    color: n.activo ? Colors.green : Colors.grey,
                                    size: 20,
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'pdf') {
                                        await NegocioAliadoLetreroExport
                                            .descargarPdf(n);
                                      } else if (v == 'ver') {
                                        await _mostrarDetalle(n);
                                      } else if (v == 'detalle') {
                                        await Navigator.push<void>(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                AdminNegocioAliadoDetallePage(
                                              negocio: n,
                                            ),
                                          ),
                                        );
                                      } else if (v == 'toggle') {
                                        await NegociosAliadosRepo.setActivo(
                                          n.codigo,
                                          !n.activo,
                                        );
                                      } else if (v == 'copy') {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: NegocioAliadoConfig
                                                .urlDescarga(n.codigo),
                                          ),
                                        );
                                        _snack('Enlace copiado.');
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'pdf',
                                        child: Text('Descargar letrero PDF'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'detalle',
                                        child: Text('Clientes y comisión 3%'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'ver',
                                        child: Text('Ver QR'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'copy',
                                        child: Text('Copiar enlace'),
                                      ),
                                      PopupMenuItem(
                                        value: 'toggle',
                                        child: Text(
                                          n.activo ? 'Desactivar' : 'Activar',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
