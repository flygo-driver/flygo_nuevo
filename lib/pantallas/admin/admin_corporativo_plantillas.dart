import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/servicios/corporativo_admin_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_chofer_perfil_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/widgets/admin_corporativo_pasajeros_lista.dart';
import 'package:flygo_nuevo/utils/corporativo_ruta_enumeracion.dart';
import 'package:flygo_nuevo/widgets/corporativo_ruta_titulo_numerado.dart';
import 'package:flygo_nuevo/widgets/corporativo_chofer_perfil_card.dart';
import 'package:flygo_nuevo/widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

/// Admin: asignar conductor RAI a cada plantilla corporativa.
class AdminCorporativoPlantillasPage extends StatefulWidget {
  const AdminCorporativoPlantillasPage({
    super.key,
    this.empresaId,
    this.empresaNombre,
  });

  /// Si es null, muestra todas las empresas (hub de asignación).
  final String? empresaId;
  final String? empresaNombre;

  bool get todasLasEmpresas =>
      empresaId == null || empresaId!.trim().isEmpty;

  @override
  State<AdminCorporativoPlantillasPage> createState() =>
      _AdminCorporativoPlantillasPageState();
}

class _AdminCorporativoPlantillasPageState
    extends State<AdminCorporativoPlantillasPage> {
  String? _procesandoPlantillaId;

  String _mensajeErrorFirebase(Object e) {
    if (e is FirebaseFunctionsException) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty && msg.toLowerCase() != 'internal') return msg;
      return switch (e.code) {
        'internal' =>
          'Error del servidor al asignar chofer. Reintentá en unos segundos.',
        'permission-denied' => 'Solo administración RAI puede asignar choferes.',
        'not-found' => 'Conductor o ruta no encontrados en RAI.',
        'failed-precondition' =>
          msg.isNotEmpty ? msg : 'No se pudo asignar el chofer.',
        _ => 'Error (${e.code})',
      };
    }
    return e.toString();
  }

  Future<void> _ejecutarAsignacion(
    CorporativoPlantilla pl, {
    required String empresaId,
    required String empresaNombre,
    String? choferUid,
    String? busqueda,
    String tipoBusqueda = 'auto',
    String? telefonoChofer,
    bool forzar = false,
  }) async {
    setState(() => _procesandoPlantillaId = pl.id);
    try {
      var res = await CorporativoAdminService.asignarChoferPlantilla(
        empresaId: empresaId,
        plantillaId: pl.id,
        choferUid: choferUid,
        busqueda: busqueda,
        tipoBusqueda: tipoBusqueda,
        telefonoChofer: telefonoChofer,
        forzar: forzar,
      );
      if (!mounted) return;

      if (res['requiereConfirmacion'] == true) {
        final conflictos = (res['conflictos'] as List?) ?? const [];
        final detalle = conflictos.map((c) {
          if (c is! Map) return '• Choque de horario';
          final emp = (c['empresaNombre'] ?? 'Empresa').toString();
          final ruta = (c['plantillaNombre'] ?? 'Ruta').toString();
          final hora = (c['hora'] ?? '').toString();
          final diff = c['diferenciaMinutos'];
          final margen = c['margenMinutos'];
          return '• $emp · $ruta · $hora'
              '${diff != null ? ' (sep. $diff min / min. $margen)' : ''}';
        }).join('\n');

        final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AdminUi.dialogSurface(ctx),
            title: const Text('Choque de horario'),
            content: Text(
              'Este conductor ya tiene ruta(s) que chocan con '
              '«${pl.nombre}» (${pl.horaRecogidaGrupo}):\n\n'
              '$detalle\n\n'
              '¿Asignar igual de todos modos a esta ruta?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Asignar igual'),
              ),
            ],
          ),
        );
        if (confirmar != true || !mounted) return;
        res = await CorporativoAdminService.asignarChoferPlantilla(
          empresaId: empresaId,
          plantillaId: pl.id,
          choferUid: (res['choferUid'] ?? choferUid ?? '').toString().isNotEmpty
              ? (res['choferUid'] ?? choferUid).toString()
              : null,
          busqueda: busqueda,
          tipoBusqueda: tipoBusqueda,
          telefonoChofer: telefonoChofer,
          forzar: true,
        );
        if (!mounted) return;
      }

      if (res['asignado'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((res['mensaje'] ?? 'No se asignó').toString()),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return;
      }

      final syncError = (res['syncError'] ?? '').toString().trim();
      final viajeId = (res['viajeId'] ?? '').toString().trim();
      final viajeCreado = res['viajeCreadoEnSync'] == true;
      final horaTxt = pl.horaRecogidaGrupo;

      if (syncError.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Chofer amarrado, pero el viaje de hoy no sincronizó: $syncError\n'
              'El encargado puede usar «Enviar ahora» o reintentá en unos segundos.',
            ),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 6),
          ),
        );
      } else if (viajeCreado && viajeId.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Chofer amarrado para $empresaNombre · '
              '${pl.pasajerosActivos.length} pasajero(s) · recogida $horaTxt\n'
              'Viaje de hoy listo en la app del chofer.',
            ),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Chofer amarrado para $empresaNombre · '
              '${pl.pasajerosActivos.length} pasajero(s) · recogida $horaTxt\n'
              'El viaje se abre ~90 min antes de la recogida o cuando el encargado toque «Enviar ahora».',
            ),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeErrorFirebase(e)),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoPlantillaId = null);
    }
  }

  Future<void> _asignarChofer(
    CorporativoPlantilla pl, {
    required String empresaId,
    required String empresaNombre,
  }) async {
    final esCambio =
        pl.choferPreferidoUid != null && pl.choferPreferidoUid!.isNotEmpty;
    final resultado = await showDialog<_AsignarChoferResultado>(
      context: context,
      builder: (ctx) => _DialogAsignarChoferCorp(
        plantilla: pl,
        empresaNombre: empresaNombre,
        esCambio: esCambio,
        mensajeError: _mensajeErrorFirebase,
      ),
    );
    if (resultado == null || !mounted) return;

    await _ejecutarAsignacion(
      pl,
      empresaId: empresaId,
      empresaNombre: empresaNombre,
      choferUid: resultado.choferUid,
      busqueda: resultado.busqueda,
      tipoBusqueda: resultado.tipoBusqueda,
      telefonoChofer: resultado.telefonoChofer,
    );
  }

  Future<void> _desasignarChofer(
    CorporativoPlantilla pl, {
    required String empresaId,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: const Text('Quitar conductor'),
        content: Text(
          '¿Quitar el conductor de «${pl.nombre}»? La ruta no podrá publicarse hasta asignar otro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesandoPlantillaId = pl.id);
    try {
      await CorporativoAdminService.desasignarChoferPlantilla(
        empresaId: empresaId,
        plantillaId: pl.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conductor quitado de «${pl.nombre}»'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeErrorFirebase(e)),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoPlantillaId = null);
    }
  }

  Future<void> _eliminarRuta(
    CorporativoPlantilla pl, {
    required String empresaId,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ruta'),
        content: Text(
          '¿Eliminar «${pl.nombre}» por completo?\n\n'
          'Se borran pasajeros y configuración. Si hoy ya se envió al chofer '
          'y el viaje no ha empezado, se cancela automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _procesandoPlantillaId = pl.id);
    try {
      final cancelados = await CorporativoAdminService.eliminarPlantilla(
        empresaId: empresaId,
        plantillaId: pl.id,
      );
      if (!mounted) return;
      final extra = cancelados > 0 ? ' Viaje de hoy cancelado.' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ruta eliminada.$extra')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoPlantillaId = null);
    }
  }

  TimeOfDay _horaDesdePlantilla(CorporativoPlantilla pl) {
    final parts = pl.horaRecogidaGrupo.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 7,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  Future<void> _cambiarHora(
    CorporativoPlantilla pl, {
    required String empresaId,
  }) async {
    final horaAnterior = pl.horaRecogidaGrupo;
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaDesdePlantilla(pl),
      helpText: 'Nueva hora de recogida',
    );
    if (picked == null || !mounted) return;

    final horaNueva =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (horaNueva == horaAnterior) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: const Text('Cambiar hora de recogida'),
        content: Text(
          '«${pl.nombre}»\n\n'
          '$horaAnterior → $horaNueva\n\n'
          'El chofer y el encargado de la empresa verán el cambio al instante '
          '(push + Mis rutas).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _procesandoPlantillaId = pl.id);
    try {
      var res = await CorporativoAdminService.actualizarHoraPlantilla(
        empresaId: empresaId,
        plantillaId: pl.id,
        horaNueva: horaNueva,
      );
      if (!mounted) return;

      if (res['requiereConfirmacion'] == true) {
        final conflictos = (res['conflictos'] as List?) ?? const [];
        final detalle = conflictos.map((c) {
          if (c is! Map) return '• Choque de horario';
          final emp = (c['empresaNombre'] ?? 'Empresa').toString();
          final ruta = (c['plantillaNombre'] ?? 'Ruta').toString();
          final hora = (c['hora'] ?? '').toString();
          final diff = c['diferenciaMinutos'];
          final margen = c['margenMinutos'];
          return '• $emp · $ruta · $hora'
              '${diff != null ? ' (sep. $diff min / min. $margen)' : ''}';
        }).join('\n');

        final confirmarConflicto = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AdminUi.dialogSurface(ctx),
            title: const Text('Choque de horario'),
            content: Text(
              'Con la nueva hora ($horaNueva), el chofer asignado choca con:\n\n'
              '$detalle\n\n'
              '¿Cambiar la hora igual de todos modos?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cambiar igual'),
              ),
            ],
          ),
        );
        if (confirmarConflicto != true || !mounted) return;
        res = await CorporativoAdminService.actualizarHoraPlantilla(
          empresaId: empresaId,
          plantillaId: pl.id,
          horaNueva: horaNueva,
          forzar: true,
        );
        if (!mounted) return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (res['mensaje'] ?? 'Hora actualizada a $horaNueva').toString(),
          ),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeErrorFirebase(e)),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesandoPlantillaId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.todasLasEmpresas
        ? 'Asignar chofer · Todas las empresas'
        : 'Rutas · ${widget.empresaNombre}';
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AdminAppBar(
        guiaId: AdminGuiaIds.rutasCorp,
        title: titulo,
      ),
      drawer: const AdminDrawer(),
      body: widget.todasLasEmpresas
          ? _buildTodasLasEmpresas(context)
          : _buildUnaEmpresa(context),
    );
  }

  Widget _buildUnaEmpresa(BuildContext context) {
    return StreamBuilder<List<CorporativoPlantilla>>(
      stream: CorporativoRutaService.streamPlantillas(widget.empresaId!),
      builder: (context, snap) => _buildContenidoPlantillas(
        context,
        snap: snap,
        items: (snap.data ?? [])
            .map(
              (pl) => CorporativoPlantillaConEmpresa(
                empresaId: widget.empresaId!,
                empresaNombre: widget.empresaNombre ?? 'Empresa',
                plantilla: pl,
              ),
            )
            .toList(),
        vacio: 'El encargado aún no creó plantillas en la app cliente.',
      ),
    );
  }

  Widget _buildTodasLasEmpresas(BuildContext context) {
    return StreamBuilder<List<CorporativoPlantillaConEmpresa>>(
      stream: CorporativoAdminService.streamPlantillasTodasEmpresas(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _errorCarga(context, snap.error);
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No hay rutas corporativas activas en ninguna empresa.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            ),
          );
        }
        return _buildContenidoPlantillas(
          context,
          snap: snap,
          items: items,
          vacio: 'No hay rutas corporativas activas.',
          agruparPorEmpresa: true,
        );
      },
    );
  }

  Widget _errorCarga(BuildContext context, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
            const SizedBox(height: 12),
            Text(
              'No se pudo cargar las rutas',
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenidoPlantillas(
    BuildContext context, {
    required AsyncSnapshot snap,
    required List<CorporativoPlantillaConEmpresa> items,
    required String vacio,
    bool agruparPorEmpresa = false,
  }) {
    if (snap.hasError) {
      return _errorCarga(context, snap.error);
    }
    if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            vacio,
            textAlign: TextAlign.center,
            style: TextStyle(color: AdminUi.secondary(context)),
          ),
        ),
      );
    }

    final sinChofer = items.where((e) {
      final uid = e.plantilla.choferPreferidoUid ?? '';
      return uid.trim().isEmpty;
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ResumenChoferesTodasEmpresas(
          filtrarEmpresaId: widget.todasLasEmpresas ? null : widget.empresaId,
          empresaNombre: widget.empresaNombre,
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
          ),
          child: Text(
            widget.todasLasEmpresas
                ? 'Vista en vivo de todas las empresas. '
                    'Revisá pasajeros en orden antes de asignar chofer. '
                    'Si cambiás la hora, se actualiza al instante en ADM, '
                    'encargado y chofer.'
                : 'Asigná, cambiá o quitá chofer por ruta. '
                    'Los pasajeros se muestran en orden de recogida/entrega. '
                    'La hora se sincroniza en tiempo real.',
            style: TextStyle(
              color: AdminUi.secondary(context),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        if (sinChofer > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
            ),
            child: Text(
              '$sinChofer ruta(s) sin chofer asignado. '
              'Asigná conductor en cada tarjeta.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        if (agruparPorEmpresa) ..._buildGruposPorEmpresa(context, items)
        else ...[
          ...() {
            final plantillas =
                items.map((e) => e.plantilla).toList(growable: false);
            final numeros = CorporativoRutaEnumeracion.mapaNumeros(plantillas);
            return items.map(
              (item) => _buildTarjetaRuta(
                context,
                item.plantilla,
                empresaId: item.empresaId,
                empresaNombre: item.empresaNombre,
                numeroRuta: numeros[item.plantilla.id] ?? 0,
              ),
            );
          }(),
        ],
      ],
    );
  }

  List<Widget> _buildGruposPorEmpresa(
    BuildContext context,
    List<CorporativoPlantillaConEmpresa> items,
  ) {
    final grupos = <String, List<CorporativoPlantillaConEmpresa>>{};
    for (final item in items) {
      grupos.putIfAbsent(item.empresaId, () => []).add(item);
    }
    final widgets = <Widget>[];
    for (final entry in grupos.entries) {
      final grupo = entry.value;
      if (grupo.isEmpty) continue;
      final nombreEmp = grupo.first.empresaNombre;
      final pendientes = grupo.where((g) {
        final uid = g.plantilla.choferPreferidoUid ?? '';
        return uid.trim().isEmpty;
      }).length;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Row(
            children: [
              Icon(Icons.business, size: 20, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nombreEmp,
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              if (pendientes > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$pendientes sin chofer',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      final numerosGrupo = CorporativoRutaEnumeracion.mapaNumeros(
        grupo.map((g) => g.plantilla).toList(),
      );
      for (final item in grupo) {
        widgets.add(
          _buildTarjetaRuta(
            context,
            item.plantilla,
            empresaId: item.empresaId,
            empresaNombre: item.empresaNombre,
            mostrarEmpresa: false,
            numeroRuta: numerosGrupo[item.plantilla.id] ?? 0,
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildTarjetaRuta(
    BuildContext context,
    CorporativoPlantilla pl, {
    required String empresaId,
    required String empresaNombre,
    bool mostrarEmpresa = true,
    int numeroRuta = 0,
  }) {
    final fmt = DateFormat('EEE d MMM · HH:mm', 'es');
    final proc = _procesandoPlantillaId == pl.id;
    final tieneChofer =
        pl.choferPreferidoUid != null && pl.choferPreferidoUid!.isNotEmpty;
    final activos = pl.pasajerosActivos.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tieneChofer
              ? Colors.teal.withValues(alpha: 0.45)
              : Colors.orange.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mostrarEmpresa)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                empresaNombre,
                style: TextStyle(
                  color: Colors.teal.shade800,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (numeroRuta > 0) ...[
                CorporativoRutaNumeroBadge(numero: numeroRuta),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  numeroRuta > 0
                      ? CorporativoRutaEnumeracion.titulo(pl, numeroRuta)
                      : pl.nombre,
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '📍 ${pl.origenLabel}\n'
            '⏰ ${pl.horaRecogidaGrupo} · $activos pasajero(s) activos'
            '${pl.precioAcordado > 0 ? '\n💰 RD\$ ${pl.precioAcordado.toStringAsFixed(0)} / viaje' : ''}',
            style: TextStyle(
              color: AdminUi.secondary(context),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (pl.esFijo) ...[
            const SizedBox(height: 4),
            Text(
              'Próxima: ${fmt.format(CorporativoRutaService.proximaRecogida(pl))}'
              '${pl.publicacionAutomatica ? ' · auto' : ''}',
              style: TextStyle(
                color: Colors.teal.shade700,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdminUi.scaffold(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AdminUi.secondary(context).withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pasajeros en orden',
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                AdminCorporativoPasajerosLista(
                  plantilla: pl,
                  compact: true,
                  mostrarInactivos: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (tieneChofer) ...[
            _BadgeAsignadoParaEmpresa(empresaNombre: empresaNombre),
            const SizedBox(height: 8),
            _ChoferAsignadoEnVivo(
              plantilla: pl,
              empresaNombre: empresaNombre,
            ),
          ] else
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sin chofer — asigná por teléfono para operar',
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          if (pl.ultimoErrorPublicacion != null &&
              pl.ultimoErrorPublicacion!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                '⚠️ Publicación: ${pl.ultimoErrorPublicacion}',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: proc
                    ? null
                    : () => _cambiarHora(pl, empresaId: empresaId),
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text('Hora: ${pl.horaRecogidaGrupo}'),
              ),
              if (!tieneChofer)
                FilledButton.icon(
                  onPressed: proc
                      ? null
                      : () => _asignarChofer(
                            pl,
                            empresaId: empresaId,
                            empresaNombre: empresaNombre,
                          ),
                  icon: const Icon(Icons.local_taxi_outlined, size: 18),
                  label: const Text('Asignar chofer'),
                ),
              if (tieneChofer) ...[
                OutlinedButton.icon(
                  onPressed: proc
                      ? null
                      : () => _asignarChofer(
                            pl,
                            empresaId: empresaId,
                            empresaNombre: empresaNombre,
                          ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Cambiar chofer'),
                ),
                OutlinedButton.icon(
                  onPressed: proc
                      ? null
                      : () => _desasignarChofer(pl, empresaId: empresaId),
                  icon: const Icon(Icons.person_remove_outlined, size: 18),
                  label: const Text('Quitar'),
                ),
              ],
            ],
          ),
          if (!widget.todasLasEmpresas) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: proc
                    ? null
                    : () => _eliminarRuta(pl, empresaId: empresaId),
                icon: const Icon(Icons.delete_forever_outlined, size: 20),
                label: const Text(
                  'Eliminar ruta completa',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Resumen en vivo de choferes asignados (todas las empresas o una sola).
class _ResumenChoferesTodasEmpresas extends StatelessWidget {
  const _ResumenChoferesTodasEmpresas({
    this.filtrarEmpresaId,
    this.empresaNombre,
  });

  final String? filtrarEmpresaId;
  final String? empresaNombre;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CorporativoAsignacionRutaAdmin>>(
      stream: CorporativoAdminService.streamAsignacionesRutas(),
      builder: (context, asigSnap) {
        final todas = asigSnap.data ?? const [];
        final visibles = filtrarEmpresaId == null
            ? todas
            : todas.where((a) => a.empresaId == filtrarEmpresaId).toList();
        if (visibles.isEmpty) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
            ),
            child: Text(
              filtrarEmpresaId == null
                  ? 'Ninguna ruta tiene chofer asignado todavía.'
                  : 'Ninguna ruta de ${empresaNombre ?? 'esta empresa'} tiene chofer asignado.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          );
        }
        final porChofer =
            CorporativoAdminService.agruparAsignacionesPorChofer(visibles);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filtrarEmpresaId == null
                    ? 'Choferes asignados · todas las empresas (en vivo)'
                    : 'Choferes asignados a ${empresaNombre ?? 'empresa'}',
                style: TextStyle(
                  color: Colors.teal.shade900,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...porChofer.entries.map((e) {
                final rutas = e.value;
                final c = rutas.first;
                final detalleRutas = rutas.length == 1
                    ? '${rutas.first.empresaNombre} · ${rutas.first.plantillaNombre} · ${rutas.first.horaRecogida}'
                    : rutas
                        .map(
                          (r) =>
                              '${r.empresaNombre} · ${r.plantillaNombre} · ${r.horaRecogida}',
                        )
                        .join('\n   ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${c.choferNombre} (${c.choferTelefono.isNotEmpty ? c.choferTelefono : 'sin tel'})\n'
                    '   $detalleRutas',
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// Estado visible: chofer ya asignado a esta empresa.
class _BadgeAsignadoParaEmpresa extends StatelessWidget {
  const _BadgeAsignadoParaEmpresa({required this.empresaNombre});

  final String empresaNombre;

  @override
  Widget build(BuildContext context) {
    final nombre = empresaNombre.trim().isEmpty ? 'esta empresa' : empresaNombre.trim();
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Conductor asignado para $nombre. '
                'El encargado ya puede enviar la ruta.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        },
        style: FilledButton.styleFrom(
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.centerLeft,
        ),
        icon: const Icon(Icons.check_circle_rounded, size: 22),
        label: Text(
          'Asignado para $nombre',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// Chofer asignado con datos en vivo desde `usuarios/{uid}`.
class _ChoferAsignadoEnVivo extends StatelessWidget {
  const _ChoferAsignadoEnVivo({
    required this.plantilla,
    required this.empresaNombre,
  });

  final CorporativoPlantilla plantilla;
  final String empresaNombre;

  CorporativoChoferPerfil _fusionarPerfil(CorporativoChoferPerfil live) {
    final snap = plantilla.choferAsignadoPerfil;
    return CorporativoChoferPerfil(
      uid: live.uid,
      nombre: live.nombre.isNotEmpty ? live.nombre : (snap?.nombre ?? ''),
      telefono: live.telefono.isNotEmpty
          ? live.telefono
          : (plantilla.choferPreferidoTelefono ?? snap?.telefono ?? ''),
      email: live.email.isNotEmpty ? live.email : (snap?.email ?? ''),
      cedula: live.cedula.isNotEmpty ? live.cedula : (snap?.cedula ?? ''),
      placa: live.placa.isNotEmpty ? live.placa : (snap?.placa ?? ''),
      marca: live.marca.isNotEmpty ? live.marca : (snap?.marca ?? ''),
      modelo: live.modelo.isNotEmpty ? live.modelo : (snap?.modelo ?? ''),
      color: live.color.isNotEmpty ? live.color : (snap?.color ?? ''),
      anio: live.anio.isNotEmpty ? live.anio : (snap?.anio ?? ''),
      tipoVehiculo: live.tipoVehiculo.isNotEmpty
          ? live.tipoVehiculo
          : (snap?.tipoVehiculo ?? ''),
      documentosVerificados:
          live.documentosVerificados || (snap?.documentosVerificados ?? false),
      fotoUrl: live.fotoUrl.isNotEmpty ? live.fotoUrl : (snap?.fotoUrl ?? ''),
      asignadoEn: snap?.asignadoEn,
      calificacionPromedio: live.calificacionPromedio > 0
          ? live.calificacionPromedio
          : (snap?.calificacionPromedio ?? 0),
      aniosExperiencia: live.aniosExperiencia > 0
          ? live.aniosExperiencia
          : (snap?.aniosExperiencia ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = (plantilla.choferPreferidoUid ?? '').trim();
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<CorporativoChoferPerfil?>(
      stream: CorporativoChoferPerfilService.streamPorUid(uid),
      builder: (context, snap) {
        final live = snap.data;
        final perfil = live != null
            ? _fusionarPerfil(live)
            : plantilla.choferAsignadoPerfil;
        final nombre = perfil?.nombre.isNotEmpty == true
            ? perfil!.nombre
            : (plantilla.choferPreferidoNombre ?? 'Conductor RAI');
        final tel = perfil?.telefono.isNotEmpty == true
            ? perfil!.telefono
            : (plantilla.choferPreferidoTelefono ?? '—');
        final email = perfil?.email ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.teal.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.link,
                        size: 18,
                        color: Colors.teal.shade800,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Asignado para $empresaNombre',
                          style: TextStyle(
                            color: Colors.teal.shade900,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (snap.connectionState == ConnectionState.active)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: Colors.green.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'En vivo',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    nombre,
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tel: $tel${email.isNotEmpty ? ' · $email' : ''}',
                    style: TextStyle(
                      color: AdminUi.secondary(context),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'UID …${uid.length > 10 ? uid.substring(uid.length - 10) : uid}',
                    style: TextStyle(
                      color: AdminUi.secondary(context),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Atado a · $empresaNombre · ${plantilla.nombre}',
                    style: TextStyle(
                      color: Colors.teal.shade800,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (perfil != null && perfil.asignado) ...[
              const SizedBox(height: 8),
              CorporativoChoferPerfilCard(
                perfil: perfil,
                compacto: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AsignarChoferResultado {
  const _AsignarChoferResultado({
    this.choferUid,
    this.busqueda,
    this.tipoBusqueda = 'auto',
    this.telefonoChofer,
  });

  final String? choferUid;
  final String? busqueda;
  final String tipoBusqueda;
  final String? telefonoChofer;
}

/// Diálogo simple: buscar por teléfono, correo o nombre y asignar.
class _DialogAsignarChoferCorp extends StatefulWidget {
  const _DialogAsignarChoferCorp({
    required this.plantilla,
    required this.empresaNombre,
    required this.esCambio,
    required this.mensajeError,
  });

  final CorporativoPlantilla plantilla;
  final String empresaNombre;
  final bool esCambio;
  final String Function(Object e) mensajeError;

  @override
  State<_DialogAsignarChoferCorp> createState() =>
      _DialogAsignarChoferCorpState();
}

class _DialogAsignarChoferCorpState extends State<_DialogAsignarChoferCorp> {
  late final TextEditingController _qCtrl;
  List<CorporativoChoferCandidato> _candidatos = const [];
  CorporativoChoferCandidato? _seleccionado;
  var _buscando = false;
  String? _errorBusqueda;
  var _debounce = 0;
  String _tipoBusqueda = 'telefono';

  @override
  void initState() {
    super.initState();
    _qCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String raw) async {
    final q = raw.trim();
    final token = ++_debounce;
    if (q.length < 3) {
      setState(() {
        _candidatos = const [];
        _errorBusqueda = null;
        _buscando = false;
      });
      return;
    }
    setState(() {
      _buscando = true;
      _errorBusqueda = null;
    });
    final tipo = _tipoBusqueda == 'auto'
        ? (q.contains('@')
            ? 'email'
            : (q.replaceAll(RegExp(r'\D'), '').length >= 10
                ? 'telefono'
                : 'nombre'))
        : _tipoBusqueda;
    try {
      final list = await CorporativoAdminService.buscarChoferes(
        busqueda: q,
        tipoBusqueda: tipo,
      );
      if (token != _debounce || !mounted) return;
      setState(() {
        _candidatos = list;
        _buscando = false;
        if (list.length == 1) _seleccionado = list.first;
        if (list.isEmpty) {
          _errorBusqueda =
              'Sin resultados. Probá otro teléfono, correo o nombre.';
        }
      });
    } catch (e) {
      if (token != _debounce || !mounted) return;
      setState(() {
        _buscando = false;
        _errorBusqueda = widget.mensajeError(e);
      });
    }
  }

  bool _puedeConfirmar() {
    if (_seleccionado != null && _seleccionado!.uid.isNotEmpty) return true;
    if (_candidatos.length == 1) return true;
    final q = _qCtrl.text.trim();
    if (q.contains('@') && q.length >= 5) return true;
    if (q.replaceAll(RegExp(r'\D'), '').length >= 10) return true;
    return false;
  }

  void _confirmar() {
    final q = _qCtrl.text.trim();
    final elegido = _seleccionado ??
        (_candidatos.length == 1 ? _candidatos.first : null);
    if (elegido != null && elegido.uid.isNotEmpty) {
      Navigator.pop(
        context,
        _AsignarChoferResultado(
          choferUid: elegido.uid,
          telefonoChofer: elegido.telefono.isNotEmpty ? elegido.telefono : null,
          tipoBusqueda: 'auto',
        ),
      );
      return;
    }
    if (q.contains('@')) {
      Navigator.pop(
        context,
        _AsignarChoferResultado(busqueda: q, tipoBusqueda: 'email'),
      );
      return;
    }
    if (q.replaceAll(RegExp(r'\D'), '').length >= 10) {
      Navigator.pop(
        context,
        _AsignarChoferResultado(
          busqueda: q,
          telefonoChofer: q,
          tipoBusqueda: 'telefono',
        ),
      );
      return;
    }
    if (q.length >= 3) {
      Navigator.pop(
        context,
        _AsignarChoferResultado(busqueda: q, tipoBusqueda: _tipoBusqueda),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pl = widget.plantilla;
    return AlertDialog(
      backgroundColor: AdminUi.dialogSurface(context),
      title: Text(widget.esCambio ? 'Cambiar chofer' : 'Asignar chofer'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pl.nombre,
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Empresa: ${widget.empresaNombre}',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '⏰ Recogida ${pl.horaRecogidaGrupo} · '
                '${pl.pasajerosActivos.length} pasajero(s) · ${pl.origenLabel}',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminUi.scaffold(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AdminUi.secondary(context).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pasajeros en orden (revisá antes de asignar)',
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AdminCorporativoPasajerosLista(
                      plantilla: pl,
                      compact: true,
                    ),
                  ],
                ),
              ),
              if (widget.esCambio) ...[
                const SizedBox(height: 8),
                Text(
                  'Chofer actual: ${pl.choferPreferidoNombre ?? '—'} · '
                  '${pl.choferPreferidoTelefono ?? ''}',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Choferes en la plataforma (pool corporativo)',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tocá un chofer de la lista o buscá arriba. Se asignará a '
                '${widget.empresaNombre}.',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<CorporativoChoferCandidato>>(
                stream: CorporativoAdminService.streamChoferesPoolActivos(),
                builder: (context, poolSnap) {
                  final pool = poolSnap.data ?? const [];
                  if (poolSnap.connectionState == ConnectionState.waiting &&
                      pool.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (pool.isEmpty) {
                    return Text(
                      'No hay choferes en el pool. Habilitálos en «Choferes corporativos».',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 11,
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: pool.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = pool[i];
                        final sel = _seleccionado?.uid == c.uid;
                        return ListTile(
                          dense: true,
                          selected: sel,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          leading: const Icon(Icons.local_taxi_outlined),
                          title: Text(
                            c.nombre.isEmpty ? 'Conductor RAI' : c.nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'Tel: ${c.telefono.isNotEmpty ? c.telefono : '—'} · '
                            'Placa: ${c.placa.isNotEmpty ? c.placa : '—'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => setState(() => _seleccionado = c),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'telefono', label: Text('Teléfono')),
                  ButtonSegment(value: 'email', label: Text('Correo')),
                  ButtonSegment(value: 'nombre', label: Text('Nombre')),
                ],
                selected: {_tipoBusqueda},
                onSelectionChanged: (s) {
                  setState(() {
                    _tipoBusqueda = s.first;
                    _seleccionado = null;
                  });
                  if (_qCtrl.text.trim().length >= 3) _buscar(_qCtrl.text);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _qCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: switch (_tipoBusqueda) {
                    'email' => 'Correo del taxista',
                    'nombre' => 'Nombre del taxista',
                    _ => 'Teléfono del taxista',
                  },
                  hintText: switch (_tipoBusqueda) {
                    'email' => 'chofer@correo.com',
                    'nombre' => 'Juan Pérez',
                    _ => '8095551234',
                  },
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscando
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => _buscar(_qCtrl.text),
                        ),
                ),
                keyboardType: _tipoBusqueda == 'email'
                    ? TextInputType.emailAddress
                    : (_tipoBusqueda == 'nombre'
                        ? TextInputType.name
                        : TextInputType.phone),
                onChanged: (t) {
                  setState(() => _seleccionado = null);
                  _buscar(t);
                },
                onSubmitted: _buscar,
              ),
              const SizedBox(height: 8),
              Text(
                'El chofer entra a RAI Driver con su teléfono, no con el correo '
                'de la empresa. Tocá un resultado de la lista para confirmar.',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              if (_errorBusqueda != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorBusqueda!,
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_candidatos.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _candidatos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _candidatos[i];
                      final sel = _seleccionado?.uid == c.uid;
                      final accent = Theme.of(context).colorScheme.primary;
                      return ListTile(
                        dense: true,
                        selected: sel,
                        selectedTileColor: accent.withValues(alpha: 0.12),
                        leading: Icon(Icons.person_outline, color: accent),
                        title: Text(
                          c.nombre.isEmpty ? 'Conductor RAI' : c.nombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (c.telefono.isNotEmpty) 'Tel: ${c.telefono}',
                                if (c.email.isNotEmpty) 'Correo: ${c.email}',
                                if (c.cedula.isNotEmpty) 'Cédula: ${c.cedula}',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11),
                            ),
                            Text(
                              '${c.enPool ? 'Pool corporativo' : 'Se habilita al asignar'} · '
                              'UID …${c.uid.length > 8 ? c.uid.substring(c.uid.length - 8) : c.uid}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AdminUi.secondary(context),
                              ),
                            ),
                          ],
                        ),
                        onTap: () => setState(() => _seleccionado = c),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _puedeConfirmar() ? _confirmar : null,
          child: Text(
            widget.esCambio
                ? 'Cambiar chofer'
                : 'Asignar a ${widget.empresaNombre.trim().isEmpty ? 'empresa' : widget.empresaNombre.trim()}',
          ),
        ),
      ],
    );
  }
}
