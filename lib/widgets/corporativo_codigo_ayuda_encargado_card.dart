import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/corporativo/corporativo_chat_encargado_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_fase_a_service.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

/// Alerta al encargado cuando el chofer necesita el código o el viaje quedó bloqueado.
class CorporativoCodigoAyudaEncargadoCard extends StatelessWidget {
  const CorporativoCodigoAyudaEncargadoCard({
    super.key,
    required this.viajeId,
    required this.choferUid,
    required this.choferNombre,
    this.empresaNombre = '',
  });

  final String viajeId;
  final String choferUid;
  final String choferNombre;
  final String empresaNombre;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? <String, dynamic>{};
        final estado = EstadosViaje.normalizar((d['estado'] ?? '').toString());
        final esperando = d['esperandoCodigo'] == true ||
            estado == EstadosViaje.esperandoCodigoEncargado;
        final bloqueado =
            d['codigoBloqueado'] == true || estado == EstadosViaje.codigoBloqueado;
        final pendiente = estado == EstadosViaje.pendienteCodigo;

        if (!esperando && !bloqueado && !pendiente) {
          return const SizedBox.shrink();
        }

        String titulo = 'Código solicitado';
        String detalle =
            'El chofer necesita el código para iniciar la ruta. Envíalo por chat.';
        Color color = Colors.orange;
        if (bloqueado) {
          titulo = 'Código bloqueado (3 intentos)';
          detalle =
              'El chofer falló el código 3 veces. Genera un código de respaldo y envíalo.';
          color = Colors.redAccent;
        } else if (pendiente) {
          titulo = 'Código enviado — esperando chofer';
          detalle = 'El chofer puede retomar la ruta desde su app.';
          color = Colors.teal;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: p.onCard,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(detalle, style: TextStyle(color: p.muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: choferUid.isEmpty
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => CorporativoChatEncargadoPage(
                                  viajeId: viajeId,
                                  choferUid: choferUid,
                                  choferNombre: choferNombre,
                                  empresaNombre: empresaNombre,
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('Chat chofer'),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await CorporativoFaseAService.encargadoEnviarCodigo(
                          viajeId: viajeId,
                          generarCodigoRespaldo: bloqueado,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              bloqueado
                                  ? 'Código de respaldo enviado al chofer.'
                                  : 'Código del período enviado al chofer.',
                            ),
                          ),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: Text(bloqueado ? 'Código respaldo' : 'Enviar código'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
