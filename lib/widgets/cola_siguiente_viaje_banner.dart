import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';

/// Muestra origen, destino, ventana y ganancia del viaje reservado / encolado (mismos campos existentes).
class ColaSiguienteViajeBannerTaxista extends StatelessWidget {
  const ColaSiguienteViajeBannerTaxista({super.key, required this.uidTaxista});

  final String uidTaxista;

  @override
  Widget build(BuildContext context) {
    if (uidTaxista.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uidTaxista)
          .snapshots(),
      builder: (context, uSnap) {
        if (!uSnap.hasData || !uSnap.data!.exists) {
          return const SizedBox.shrink();
        }
        final ud = uSnap.data!.data() ?? {};
        final sig = (ud['siguienteViajeId'] ?? '').toString();
        final enc = (ud['viajeEncoladoId'] ?? '').toString();
        final nextId = sig.isNotEmpty ? sig : enc;
        if (nextId.isEmpty) return const SizedBox.shrink();

        final bool reservaFormal = sig.isNotEmpty;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('viajes')
              .doc(nextId)
              .snapshots(),
          builder: (context, vSnap) {
            if (!vSnap.hasData || !vSnap.data!.exists) {
              return _shell(
                reservaFormal,
                'Cargando próximo viaje…',
                '',
                '',
                '',
                '',
              );
            }
            final m = vSnap.data!.data() ?? {};
            final origen = (m['origen'] ?? 'Origen').toString();
            final destino = (m['destino'] ?? 'Destino').toString();
            final g = m['gananciaTaxista'];
            final p = m['precio'];
            double ganancia = g is num ? g.toDouble() : 0.0;
            final precio = p is num ? p.toDouble() : 0.0;
            if (ganancia <= 0 && precio > 0) {
              ganancia = precio * 0.80;
            }
            final ganTxt = FormatosMoneda.rd(ganancia > 0 ? ganancia : precio);

            DateTime? fh;
            final ts = m['fechaHora'];
            if (ts is Timestamp) fh = ts.toDate();
            final sw = m['startWindowAt'];
            if (fh == null && sw is Timestamp) fh = sw.toDate();
            String ventana = '';
            if (fh != null) {
              ventana = DateFormat('dd/MM/yyyy · HH:mm').format(fh);
            }

            final titulo = reservaFormal
                ? 'Al terminar este viaje, tu siguiente recogida es:'
                : 'Próximo en cola (se activa al finalizar el actual):';

            return _shell(
              reservaFormal,
              titulo,
              origen,
              destino,
              ventana.isEmpty ? '' : 'Ventana: $ventana',
              'Ganancia estimada: $ganTxt',
            );
          },
        );
      },
    );
  }

  Widget _shell(
    bool reservaFormal,
    String titulo,
    String origen,
    String destino,
    String ventanaLine,
    String gananciaLine,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reservaFormal
              ? Colors.lightBlueAccent
              : Colors.amber.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.queue_play_next,
                color:
                    reservaFormal ? Colors.lightBlueAccent : Colors.amberAccent,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: reservaFormal
                        ? Colors.lightBlueAccent
                        : Colors.amberAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (origen.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              origen,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
            if (destino.isNotEmpty)
              Text(
                '→ $destino',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
          ],
          if (ventanaLine.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(ventanaLine,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          if (gananciaLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(gananciaLine,
                style:
                    const TextStyle(color: Colors.greenAccent, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
