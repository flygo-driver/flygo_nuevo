import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

/// Banner para el conductor cuando pausó un viaje Bola Ahorro operativo.
class TaxistaBolaViajeRetomarBanner extends StatelessWidget {
  const TaxistaBolaViajeRetomarBanner({
    super.key,
    required this.uid,
  });

  final String uid;

  static String _etiquetaEstado(String estadoRaw) {
    final String st = estadoRaw.trim().toLowerCase();
    if (st == 'acordada') return 'Recogida pendiente';
    if (st == 'en_curso') return 'Viaje en ruta';
    return 'Viaje Bola activo';
  }

  Future<void> _retomar(BuildContext context, String bolaId) async {
    ActiveTripService.cancelarForzarInicioTaxistaShellBola();
    ActiveTripService.mantenerOverlayViajeEnShell(const Duration(seconds: 120));
    ActiveTripService.bloquearShellTaxistaTrasAceptar(
      const Duration(seconds: 90),
    );
    ShellTabController.taxistaIrARecibir();
    ActiveTripService.notificarRebuildShell();
    await BolaPuebloDialogs.abrirViajeEnCursoOperativoBola(
      bolaId: bolaId,
      esTaxista: true,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ActiveTripService.debeForzarInicioTaxistaShellBola) {
      return const SizedBox.shrink();
    }

    final String bolaIdPausado =
        ActiveTripService.bolaIdTaxistaPausado.trim();
    if (bolaIdPausado.isEmpty) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bolas_pueblo')
            .where('uidTaxista', isEqualTo: uid)
            .where('estado', whereIn: <String>['acordada', 'en_curso'])
            .limit(1)
            .snapshots(),
        builder: (
          BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap,
        ) {
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const SizedBox.shrink();
          }
          return _banner(
            context,
            bolaId: snap.data!.docs.first.id,
            data: snap.data!.docs.first.data(),
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bolas_pueblo')
          .doc(bolaIdPausado)
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
      ) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final Map<String, dynamic> d = snap.data!.data() ?? {};
        final String estado = (d['estado'] ?? '').toString().trim();
        if (estado != 'acordada' && estado != 'en_curso') {
          return const SizedBox.shrink();
        }
        return _banner(context, bolaId: bolaIdPausado, data: d);
      },
    );
  }

  Widget _banner(
    BuildContext context, {
    required String bolaId,
    required Map<String, dynamic> data,
  }) {
    final String estado = (data['estado'] ?? '').toString().trim();
    final String destino = (data['destino'] ?? data['destinoLabel'] ?? '')
        .toString()
        .trim();
    final String estadoLabel = _etiquetaEstado(estado);

    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[
              Color(0xFF0D47A1),
              Color(0xFF1565C0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF0D47A1).withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: () => _retomar(context, bolaId),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Bola Ahorro en curso',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destino.isNotEmpty
                            ? '$estadoLabel · $destino'
                            : estadoLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _retomar(context, bolaId),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0D47A1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Retomar',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
