import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_fase_a_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/utils/feriados_republica_dominicana.dart';
import 'package:flygo_nuevo/widgets/corporativo_proximo_pago_anillo.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_chat_encargado_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_plantilla_editor_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_gestion_ruta_page.dart';
import 'package:flygo_nuevo/servicios/corporativo_chofer_perfil_service.dart';
import 'package:flygo_nuevo/widgets/corporativo_abordaje_encargado_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_chofer_perfil_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_codigo_ayuda_encargado_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_codigo_verificacion_card.dart';
import 'package:flygo_nuevo/widgets/corporativo_estimador_mensual_card.dart';
import 'package:flygo_nuevo/utils/corporativo_ruta_enumeracion.dart';
import 'package:flygo_nuevo/widgets/corporativo_ruta_titulo_numerado.dart';

/// Panel operativo del día para el encargado (Fase A).
class CorporativoDashboardPage extends StatelessWidget {
  const CorporativoDashboardPage({
    super.key,
    required this.empresaId,
    required this.empresa,
  });

  final String empresaId;
  final CorporativoEmpresa empresa;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final hoy = DateTime.now();
    final keyHoy = CorporativoCicloFacturacion.claveFechaCalendario(hoy);
    final feriadoHoy = FeriadosRepublicaDominicana.mapaClavesConNombre()[keyHoy];
    final periodo = empresa.periodoActual;
    final finPeriodo = periodo?.fin;
    final monto = periodo?.montoTotalRd ?? 0;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('empresas_corporativas')
          .doc(empresaId)
          .collection('plantillas_ruta')
          .where('activa', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final todasPlantillas = (snap.data?.docs ?? [])
            .map((d) => CorporativoPlantilla.fromDoc(d))
            .where((pl) => pl.activa)
            .toList();
        final ordenadas = CorporativoRutaEnumeracion.ordenar(todasPlantillas);
        final numerosRuta = CorporativoRutaEnumeracion.mapaNumeros(ordenadas);
        final plantillas = ordenadas
            .where((pl) => CorporativoRutaService.correHoy(pl))
            .toList();

        final alertas = <String>[];
        if (feriadoHoy != null) {
          alertas.add('Hoy es feriado nacional: $feriadoHoy. No se publica ruta.');
        }
        for (final pl in plantillas) {
          final n = numerosRuta[pl.id] ?? 0;
          final titulo = CorporativoRutaEnumeracion.titulo(pl, n);
          if (pl.diasPausaFeriado.contains(keyHoy)) {
            alertas.add('«$titulo» pausada hoy (feriado empresa).');
          }
          if (pl.choferPreferidoUid == null || pl.choferPreferidoUid!.isEmpty) {
            alertas.add('«$titulo» sin chofer asignado.');
          }
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Resumen de hoy',
              style: TextStyle(
                color: p.onCard,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE d MMMM', 'es').format(hoy),
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (finPeriodo != null)
              CorporativoProximoPagoAnillo(
                fechaCorte: finPeriodo,
                cicloDias: empresa.facturacionCicloDias,
                montoRd: monto,
                formaPagoRai: empresa.formaPagoRai,
                fechaInicioPeriodo: periodo?.inicio,
              ),
            if (periodo != null &&
                periodo.codigoAcceso.replaceAll(RegExp(r'\D'), '').length == 6) ...[
              const SizedBox(height: 12),
              CorporativoCodigoVerificacionCard(
                codigo: periodo.codigoAcceso,
                validoHasta: periodo.fin,
                activo: periodo.codigoActivo,
                estadoEtiqueta: periodo.codigoActivo ? 'Activo' : 'Expirado',
                etiquetaCiclo: '${empresa.facturacionCicloDias} días cobrables',
              ),
            ],
            const SizedBox(height: 12),
            CorporativoEstimadorMensualCard(
              plantillas: todasPlantillas,
              tarifaViajeContratadaRd: empresa.tarifaViajeContratadaRd,
            ),
            const SizedBox(height: 16),
            corporativoCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route, color: p.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Rutas de hoy (${plantillas.length})',
                        style: TextStyle(
                          color: p.onCard,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (plantillas.isEmpty)
                    Text(
                      'No hay rutas operativas hoy.',
                      style: TextStyle(color: p.muted),
                    )
                  else
                    ...plantillas.map((pl) {
                      final numeroRuta = numerosRuta[pl.id] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CorporativoRutaTituloNumerado(
                              empresaId: empresaId,
                              plantilla: pl,
                              numeroConocido: numeroRuta,
                              tituloStyle: TextStyle(
                                color: p.onCard,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                fmtHoraStrAmPm(pl.horaRecogidaGrupo),
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder(
                              future: CorporativoChoferPerfilService
                                  .resolverParaPlantilla(pl),
                              builder: (context, perfilSnap) {
                                final perfil = perfilSnap.data;
                                if (perfil == null || !perfil.asignado) {
                                  return Text(
                                    'Chofer pendiente de asignación por RAI',
                                    style: TextStyle(color: p.muted, fontSize: 12),
                                  );
                                }
                                return CorporativoChoferPerfilCard(
                                  perfil: perfil,
                                  compacto: true,
                                );
                              },
                            ),
                            if ((pl.ultimoViajeId ?? '').isNotEmpty) ...[
                              const SizedBox(height: 8),
                              CorporativoCodigoAyudaEncargadoCard(
                                viajeId: pl.ultimoViajeId!,
                                choferUid: pl.choferPreferidoUid ?? '',
                                choferNombre:
                                    pl.choferPreferidoNombre ?? 'Chofer',
                                empresaNombre: empresa.nombre,
                              ),
                              CorporativoAbordajeEncargadoCard(
                                viajeId: pl.ultimoViajeId!,
                                titulo:
                                    'Abordaje · ${CorporativoRutaEnumeracion.titulo(pl, numeroRuta)}',
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (pl.choferPreferidoUid != null &&
                                    pl.choferPreferidoUid!.isNotEmpty &&
                                    (pl.ultimoViajeId ?? '').isNotEmpty)
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              CorporativoChatEncargadoPage(
                                            viajeId: pl.ultimoViajeId!,
                                            choferUid: pl.choferPreferidoUid!,
                                            choferNombre:
                                                pl.choferPreferidoNombre ?? 'Chofer',
                                            empresaNombre: empresa.nombre,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.chat, size: 18),
                                    label: const Text('Chat chofer'),
                                  ),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            CorporativoPlantillaEditorPage(
                                          empresaId: empresaId,
                                          empresaNombre: empresa.nombre,
                                          empresa: empresa,
                                          plantilla: pl,
                                          numeroRuta: numeroRuta,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.edit_road, size: 18),
                                  label: const Text('Editar ruta'),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            CorporativoGestionRutaPage(
                                          empresaId: empresaId,
                                          empresaNombre: empresa.nombre,
                                          empresa: empresa,
                                          plantilla: pl,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.tune_rounded, size: 18),
                                  label: const Text('Gestionar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (alertas.isNotEmpty)
              corporativoCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.orange.shade700, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Alertas (${alertas.length})',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...alertas.map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(a, style: TextStyle(color: p.muted, height: 1.3)),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final n = await CorporativoFaseAService.reenviarCodigoATodos(
                    empresaId,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        n > 0
                            ? 'Código reenviado a $n contacto(s).'
                            : 'No se pudo enviar por push/correo. Verificá contactos.',
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Reenviar código a todos'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        );
      },
    );
  }

  static String fmtHoraStrAmPm(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final dt = DateTime(2000, 1, 1, h, m);
    return DateFormat('h:mm a', 'es').format(dt);
  }
}
