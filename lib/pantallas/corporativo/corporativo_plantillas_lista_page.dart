import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_gestion_ruta_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_plantilla_editor_page.dart'
    show CorporativoPlantillaEditorPage, corporativoFmtHoraStrAmPm;
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_chofer_perfil_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/widgets/corporativo_chofer_perfil_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_codigo_verificacion_card.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/utils/corporativo_recurrencia_helper.dart';
import 'package:flygo_nuevo/utils/corporativo_ruta_enumeracion.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';
import 'package:flygo_nuevo/widgets/corporativo_ruta_titulo_numerado.dart';

class CorporativoPlantillasListaPage extends StatelessWidget {
  const CorporativoPlantillasListaPage({
    super.key,
    required this.empresaId,
    required this.empresa,
  });

  final String empresaId;
  final CorporativoEmpresa empresa;

  String _fmtRd(double monto) => NumberFormat.currency(
        locale: 'es_DO',
        symbol: 'RD\$',
        decimalDigits: 0,
      ).format(monto);

  String _resumenPrecioOperacion(double precioAcordado) {
    final liq =
        CorporativoRutaService.liquidacionDesdePrecioAcordado(precioAcordado);
    return 'Factura ${_fmtRd(liq.montoTotalFacturaRd)} · '
        'neto chofer ${_fmtRd(liq.pagoChoferRd)}';
  }

  String _lineaUltimoEnvio(
    Map<String, dynamic> h,
    DateFormat fmtHora,
  ) {
    final precio = (h['precio'] as num?)?.toDouble() ?? 0;
    final ts = h['fechaRecogida'];
    var hora = '';
    if (ts is Timestamp) {
      hora = fmtHora.format(ts.toDate().toLocal());
    }
    if (hora.isEmpty) return 'Enviada · ${_fmtRd(precio)}';
    return 'Enviada · $hora · ${_fmtRd(precio)}';
  }

  String _fmtDiaCorto(String ymd) {
    final p = ymd.split('-');
    if (p.length != 3) return ymd;
    return '${p[2]}/${p[1]}';
  }

  bool _puedeEnviar(CorporativoPlantilla pl, CorporativoEmpresa empresa) {
    if (!pl.activa || pl.pasajerosActivos.isEmpty) return false;
    if (!empresa.contratoVigente || !empresa.contratoDigitalFirmado) {
      return false;
    }
    if (pl.choferPreferidoUid == null || pl.choferPreferidoUid!.trim().isEmpty) {
      return false;
    }
    if (pl.esFijo && !CorporativoRutaService.correHoy(pl)) return false;
    return true;
  }

  String? _motivoNoEnviar(CorporativoPlantilla pl, CorporativoEmpresa empresa) {
    if (!empresa.contratoDigitalFirmado) {
      return 'Firmá el contrato digital antes de enviar rutas.';
    }
    if (!empresa.contratoVigente) {
      return 'RAI aún no activó el servicio de esta empresa.';
    }
    if (!pl.activa) return 'La ruta está pausada.';
    if (pl.pasajerosActivos.isEmpty) {
      return 'No hay pasajeros activos en la ruta.';
    }
    if (pl.choferPreferidoUid == null || pl.choferPreferidoUid!.trim().isEmpty) {
      return 'RAI debe asignar un conductor fijo antes de enviar la ruta. '
          'Contactá al administrador.';
    }
    if (pl.esFijo && !CorporativoRutaService.correHoy(pl)) {
      if (CorporativoRutaService.esDiaPausaFeriado(pl, DateTime.now())) {
        return 'Hoy es feriado/pausa en esta ruta. No se envía viaje.';
      }
      return 'Hoy no opera esta ruta según sus días. Esperá un día programado.';
    }
    return null;
  }

  Future<void> _lanzar(
    BuildContext context,
    CorporativoPlantilla plantilla,
    CorporativoEmpresa empresaActiva, {
    int numeroRuta = 0,
  }) async {
    final p = context.corporativoPalette;
    final bloqueo = _motivoNoEnviar(plantilla, empresaActiva);
    if (bloqueo != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bloqueo),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }

    DateTime fecha = DateTime.now().add(const Duration(hours: 1));
    if (plantilla.esFijo) {
      final hoy = CorporativoRutaService.recogidaHoy(plantilla);
      if (hoy == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Hoy no toca esta ruta. No se puede «Enviar ahora».',
            ),
            backgroundColor: Colors.red.shade800,
          ),
        );
        return;
      }
      fecha = CorporativoRutaService.fechaRecogidaParaPublicarAhora(plantilla);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: p.card,
          title: Text(
            'Enviar ruta al chofer',
            style: TextStyle(color: p.onCard, fontWeight: FontWeight.w800),
          ),
          content: Text(
            '${CorporativoRutaEnumeracion.titulo(plantilla, numeroRuta)}\n'
            '${plantilla.pasajerosActivos.length} pasajero(s) activos\n'
            'Precio en operación: ${_resumenPrecioOperacion(plantilla.precioAcordado)}\n'
            'Recogida: ${DateFormat('EEE d MMM · HH:mm', 'es').format(fecha)}',
            style: TextStyle(color: p.muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;

    try {
      await CorporativoRutaService.lanzarDesdePlantilla(
        plantilla: plantilla,
        empresa: empresaActiva,
        fechaRecogida: fecha,
      );
      if (!context.mounted) return;
      final tieneFijo = plantilla.choferPreferidoNombre != null &&
          plantilla.choferPreferidoNombre!.trim().isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tieneFijo
                ? 'Ruta enviada al chofer ${plantilla.choferPreferidoNombre}.'
                : 'Ruta publicada. RAI asignó el chofer fijo a esta ruta.',
          ),
          backgroundColor: p.success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Widget _plantillaCard(
    BuildContext context,
    CorporativoPlantilla pl,
    CorporativoEmpresa empresaActiva, {
    required String codigo,
    required int numeroRuta,
    bool destacarHoy = false,
  }) {
    final p = context.corporativoPalette;

    return corporativoCard(
      context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CorporativoRutaNumeroBadge(numero: numeroRuta),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CorporativoRutaTituloNumerado(
                      empresaId: empresaId,
                      plantilla: pl,
                      numeroConocido: numeroRuta,
                      tituloStyle: TextStyle(
                        color: p.onCard,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (destacarHoy)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Hoy',
                        style: TextStyle(
                          color: p.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (pl.esFijo)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Fijo ${corporativoFmtHoraStrAmPm(pl.horaRecogida)}',
                        style: TextStyle(
                          color: p.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (!pl.activa)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Pausada',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (pl.activa &&
                      CorporativoRutaService.esDiaPausaFeriado(
                          pl, DateTime.now()))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Feriado hoy',
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (pl.referencia.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Ref: ${pl.referencia} · ${pl.clienteNombre}',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '📍 ${pl.origenLabel}\n'
            '⏰ Recogida grupo: ${corporativoFmtHoraStrAmPm(pl.horaRecogidaGrupo)}\n'
            '🔎 ${CorporativoRutaService.resumenEstadoOperativo(pl)}',
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final pas in pl.pasajeros)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: pas.activo
                        ? p.success.withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: pas.activo
                          ? p.success.withValues(alpha: 0.35)
                          : Colors.red.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pas.activo ? Icons.person : Icons.person_off,
                        size: 13,
                        color: pas.activo ? p.success : Colors.red.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        pas.activo ? pas.nombre : '✕ ${pas.nombre}',
                        style: TextStyle(
                          color: pas.activo ? p.onCard : Colors.red.shade800,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          decoration:
                              pas.activo ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (CorporativoRutaService.proximosFeriados(pl).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Días con ✕ (no toca / feriado):',
              style: TextStyle(
                color: p.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in CorporativoRutaService.proximosFeriados(pl))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.deepOrange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      '✕ ${_fmtDiaCorto(d)}',
                      style: TextStyle(
                        color: Colors.deepOrange.shade800,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (pl.precioAcordado > 0) ...[
            const SizedBox(height: 6),
            Text(
              '💰 Precio guardado: ${_resumenPrecioOperacion(pl.precioAcordado)}',
              style: TextStyle(
                color: p.onCard,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (codigo.length == 6) ...[
            const SizedBox(height: 6),
            Text(
              '🔐 Código pasajeros: $codigo',
              style: TextStyle(
                color: p.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
          if (pl.choferPreferidoUid != null &&
              pl.choferPreferidoUid!.isNotEmpty) ...[
            const SizedBox(height: 10),
            FutureBuilder<CorporativoChoferPerfil?>(
              future: CorporativoChoferPerfilService.resolverParaPlantilla(pl),
              builder: (context, perfilSnap) {
                final perfil = perfilSnap.data;
                if (perfil == null) {
                  return Text(
                    '🚗 Conductor RAI: ${pl.choferPreferidoNombre ?? 'Asignado'}',
                    style: TextStyle(
                      color: p.onCard,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }
                return CorporativoChoferPerfilCard(
                  perfil: perfil,
                  compacto: true,
                );
              },
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              '⏳ Sin chofer fijo — pedí a RAI que asigne conductor',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (pl.ultimoErrorPublicacion != null &&
              pl.ultimoErrorPublicacion!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Text(
                '⚠️ ${pl.ultimoErrorPublicacion}',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (!empresaActiva.contratoVigente ||
              !empresaActiva.contratoDigitalFirmado) ...[
            const SizedBox(height: 6),
            Text(
              !empresaActiva.contratoDigitalFirmado
                  ? '📄 Firma el contrato corporativo en Cuenta para enviar rutas'
                  : '⏳ RAI debe activar el contrato corporativo',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (pl.esFijo) ...[
            const SizedBox(height: 6),
            Text(
              '📅 ${CorporativoPatronRecurrencia.etiqueta(pl.patronRecurrencia)}'
              '${pl.publicacionAutomatica ? ' · publicación auto cada día' : ''}',
              style: TextStyle(color: p.accent, fontSize: 12),
            ),
            Text(
              'Próxima: ${DateFormat('EEE d MMM · HH:mm', 'es').format(CorporativoRutaService.proximaRecogida(pl))}',
              style: TextStyle(color: p.success, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => CorporativoGestionRutaPage(
                        empresaId: empresaId,
                        empresaNombre: empresaActiva.nombre,
                        empresa: empresaActiva,
                        plantilla: pl,
                        numeroRuta: numeroRuta,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.event_busy, size: 18),
                label: const Text('Pausa / feriado'),
              ),
              if (!pl.activa)
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await CorporativoRutaService.setPlantillaActiva(
                        empresaId: empresaId,
                        plantillaId: pl.id,
                        activa: true,
                        causa: CorporativoPausaCausa.reactivar,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Ruta reactivada'),
                          backgroundColor: p.success,
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$e'),
                          backgroundColor: Colors.red.shade800,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Reactivar'),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CorporativoPlantillaEditorPage(
                        empresaId: empresaId,
                        empresaNombre: empresaActiva.nombre,
                        empresa: empresaActiva,
                        plantilla: pl,
                        numeroRuta: numeroRuta,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
              ),
              TextButton.icon(
                onPressed: () => ejecutarEliminarRutaCorporativo(
                  context,
                  empresaId: empresaId,
                  plantilla: pl,
                ),
                icon: Icon(Icons.delete_outline, size: 18, color: p.danger),
                label: Text('Eliminar', style: TextStyle(color: p.danger)),
              ),
              if (pl.googleMapsRutaUrl.isNotEmpty ||
                  MultiparadaRutaHelper.coordsValidas(
                      pl.origenLat, pl.origenLon))
                OutlinedButton.icon(
                  onPressed: () => CorporativoRutaService.abrirRutaEnMaps(pl),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Ver mapa'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await CorporativoRutaService.abrirRecogidaEnWaze(pl);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$e'),
                        backgroundColor: Colors.red.shade800,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.navigation_outlined, size: 18),
                label: const Text('Waze'),
              ),
              FilledButton.icon(
                onPressed: _puedeEnviar(pl, empresaActiva)
                    ? () => _lanzar(
                          context,
                          pl,
                          empresaActiva,
                          numeroRuta: numeroRuta,
                        )
                    : () {
                        final m = _motivoNoEnviar(pl, empresaActiva);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              m ??
                                  'No se puede enviar ahora. Revisá día, pasajeros y contrato.',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Enviar ahora'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seccionHoy(
    BuildContext context,
    List<CorporativoPlantilla> plantillas,
    List<Map<String, dynamic>> historialHoy, {
    required String codigo,
    required CorporativoEmpresa empresaActiva,
    required Map<String, int> numerosRuta,
  }) {
    final p = context.corporativoPalette;
    final fmtHora = DateFormat('HH:mm', 'es');
    final panelHoy = CorporativoRutaService.plantillasPanelHoy(plantillas);
    final ultimosPorPlantilla =
        CorporativoRutaService.ultimoHistorialPorPlantilla(historialHoy);
    final panelIds = panelHoy.map((pl) => pl.id).toSet();
    final historialOtros = CorporativoRutaService.historialHoyFueraDePanel(
      historialHoy,
      panelIds,
    );

    if (panelHoy.isEmpty && historialOtros.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        corporativoSectionTitle(context, 'Rutas de hoy'),
        const SizedBox(height: 8),
        if (panelHoy.isNotEmpty)
          ...panelHoy.map((pl) {
            final numeroRuta = numerosRuta[pl.id] ?? 0;
            final estado = CorporativoRutaService.estadoChipHoy(pl);
            final recogida =
                CorporativoRutaService.horaRecogidaEnDia(pl, DateTime.now());
            final ultimoEnvio = ultimosPorPlantilla[pl.id];
            final publicada = ultimoEnvio != null;
            final nEnvios = CorporativoRutaService.contarEnviosHoyPlantilla(
              historialHoy,
              pl.id,
            );
            final apagada =
                estado == 'pausada' || estado == 'feriado' || estado == 'sin_pasajeros';
            final puedeEnviar =
                !publicada && !apagada && _puedeEnviar(pl, empresaActiva);

            Color chipBg;
            Color chipFg;
            String chipLabel;
            switch (estado) {
              case 'pausada':
                chipBg = Colors.orange.withValues(alpha: 0.15);
                chipFg = Colors.orange.shade900;
                chipLabel = '✕ Pausada hoy';
              case 'feriado':
                chipBg = Colors.deepOrange.withValues(alpha: 0.15);
                chipFg = Colors.deepOrange.shade900;
                chipLabel = '✕ Feriado · no toca';
              case 'sin_pasajeros':
                chipBg = Colors.red.withValues(alpha: 0.12);
                chipFg = Colors.red.shade800;
                chipLabel = '✕ Sin pasajeros';
              default:
                chipBg = publicada
                    ? p.success.withValues(alpha: 0.15)
                    : p.primarySoft;
                chipFg = publicada ? p.success : p.accent;
                chipLabel = publicada ? 'Publicada' : 'Programada';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: corporativoCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CorporativoRutaNumeroBadge(numero: numeroRuta, compacto: true),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CorporativoRutaTituloNumerado(
                            empresaId: empresaId,
                            plantilla: pl,
                            numeroConocido: numeroRuta,
                            tituloStyle: TextStyle(
                              color: p.onCard,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              decoration: apagada
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: chipBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            chipLabel,
                            style: TextStyle(
                              color: chipFg,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      recogida != null
                          ? '⏰ Hoy ${fmtHora.format(recogida)}'
                              '${apagada ? ' · no se busca' : ''}'
                          : (apagada
                              ? 'Hoy no se busca el grupo'
                              : 'Ruta de hoy'),
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final pas in pl.pasajeros)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: pas.activo
                                  ? p.success.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pas.activo ? pas.nombre : '✕ ${pas.nombre}',
                              style: TextStyle(
                                color: pas.activo
                                    ? p.onCard
                                    : Colors.red.shade800,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                decoration: pas.activo
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (pl.precioAcordado > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '💰 ${_resumenPrecioOperacion(pl.precioAcordado)}',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (publicada) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: p.success,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _lineaUltimoEnvio(ultimoEnvio, fmtHora),
                                style: TextStyle(
                                  color: p.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (nEnvios > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 26),
                          child: Text(
                            '$nEnvios envíos hoy · vigente el último',
                            style: TextStyle(
                              color: p.muted,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ),
                    ],
                    if (codigo.length == 6 && !apagada)
                      Text(
                        '🔐 Código empleados: $codigo',
                        style: TextStyle(
                          color: p.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    if (apagada)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          estado == 'pausada'
                              ? 'Tocá Reactivar en la tarjeta o en Pausa / feriado.'
                              : estado == 'feriado'
                                  ? 'Tocá Pausa / feriado → quitá el ✕ del día y Guardar.'
                                  : 'Reactivá o agregá pasajeros para que vuelva a operar.',
                          style: TextStyle(
                            color: Colors.deepOrange.shade800,
                            fontSize: 11,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (pl.publicacionAutomatica && !publicada && !apagada)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Automático: ~90 min antes se envía al chofer.',
                          style: TextStyle(
                            color: p.accent,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => CorporativoGestionRutaPage(
                                  empresaId: empresaId,
                                  empresaNombre: empresaActiva.nombre,
                                  empresa: empresaActiva,
                                  plantilla: pl,
                                  numeroRuta: numeroRuta,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.event_busy, size: 18),
                          label: const Text('Pausa / feriado'),
                        ),
                        if (!pl.activa)
                          FilledButton.icon(
                            onPressed: () async {
                              try {
                                await CorporativoRutaService.setPlantillaActiva(
                                  empresaId: empresaId,
                                  plantillaId: pl.id,
                                  activa: true,
                                  causa: CorporativoPausaCausa.reactivar,
                                );
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Reactivar'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              CorporativoRutaService.abrirRutaEnMaps(pl),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Ver mapa'),
                        ),
                        TextButton.icon(
                          onPressed: () => ejecutarEliminarRutaCorporativo(
                            context,
                            empresaId: empresaId,
                            plantilla: pl,
                          ),
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: p.danger,
                          ),
                          label: Text(
                            'Eliminar',
                            style: TextStyle(color: p.danger),
                          ),
                        ),
                        if (puedeEnviar)
                          FilledButton.icon(
                            onPressed: () => _lanzar(
                                  context,
                                  pl,
                                  empresaActiva,
                                  numeroRuta: numeroRuta,
                                ),
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: const Text('Enviar ahora'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        if (historialOtros.isNotEmpty) ...[
          if (panelHoy.isNotEmpty) const SizedBox(height: 8),
          corporativoSectionTitle(context, 'Otros envíos de hoy'),
          const SizedBox(height: 6),
          ...historialOtros.map((h) {
            final nombre = (h['plantillaNombre'] ?? 'Ruta').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: corporativoCard(
                context,
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: p.success, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: TextStyle(
                              color: p.onCard,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _lineaUltimoEnvio(h, fmtHora),
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;

    return StreamBuilder<CorporativoEmpresa?>(
      stream: CorporativoRutaService.streamEmpresa(empresaId),
      initialData: empresa,
      builder: (context, empSnap) {
        final emp = empSnap.data ?? empresa;
        final codigo = (emp.periodoActual?.codigoAcceso ?? '').trim();

        return StreamBuilder<List<CorporativoPlantilla>>(
          stream: CorporativoRutaService.streamPlantillas(empresaId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: p.primary));
            }
            final items = snap.data ?? [];
            final ordenadas = CorporativoRutaEnumeracion.ordenar(items);
            final numerosRuta = CorporativoRutaEnumeracion.mapaNumeros(ordenadas);

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: CorporativoRutaService.streamHistorialHoy(empresaId),
              builder: (context, hoySnap) {
                final historialHoy = hoySnap.data ?? [];

                if (items.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      CorporativoCodigoVerificacionCard(
                        codigo: codigo,
                        etiquetaCiclo: CorporativoCicloFacturacion.descripcion(
                          emp.facturacionCicloDias,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Al programar una ruta, comparte el código vigente con tus empleados.',
                        style: TextStyle(color: p.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.alt_route_rounded,
                                size: 48, color: p.muted),
                            const SizedBox(height: 12),
                            Text(
                              'Crea tu primera ruta corporativa',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: p.onCard,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Precio fijo. Opera los días que programes.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: p.muted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return ListView(
                  // Extra abajo: NavigationBar (~64) no debe tapar «Pausa / feriado».
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    CorporativoCodigoVerificacionCard(
                      codigo: codigo,
                      etiquetaCiclo: CorporativoCicloFacturacion.descripcion(
                        emp.facturacionCicloDias,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mismo código en todas las rutas hasta que paguen o cierre '
                      'el ciclo. Después la app genera uno nuevo.',
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    _seccionHoy(
                      context,
                      ordenadas,
                      historialHoy,
                      codigo: codigo,
                      empresaActiva: emp,
                      numerosRuta: numerosRuta,
                    ),
                    corporativoSectionTitle(context, 'Rutas guardadas'),
                    const SizedBox(height: 8),
                    ...ordenadas.map(
                      (pl) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _plantillaCard(
                          context,
                          pl,
                          emp,
                          codigo: codigo,
                          numeroRuta: numerosRuta[pl.id] ?? 0,
                          destacarHoy: CorporativoRutaService.correHoy(pl),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
