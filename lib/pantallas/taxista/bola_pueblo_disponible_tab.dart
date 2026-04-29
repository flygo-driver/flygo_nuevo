// Pestaña "Bola" en Viaje disponible (conductor): una sola lista desplazable (evita overflow).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_viaje_activo_page.dart';
import 'package:flygo_nuevo/utilidades/constante.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';

class BolaPuebloDisponibleTab extends StatelessWidget {
  const BolaPuebloDisponibleTab({
    super.key,
    required this.user,
    required this.disponible,
    required this.disponibilidadCargando,
  });

  final User user;

  /// Mismo criterio que pestañas AHORA / PROGRAMADOS del pool.
  final bool disponible;
  final bool disponibilidadCargando;

  static Widget _paso(BuildContext context, String n, String texto) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BolaPuebloTheme.accent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              n,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: BolaPuebloUi.panelBody(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnap) {
        final ud = userSnap.data?.data() ?? const <String, dynamic>{};
        final nombre = (ud['nombre'] ?? 'Usuario').toString();
        final rol = (ud['rol'] ?? 'cliente').toString();

        final bool puedeOperarPool = !disponibilidadCargando && disponible;

        final List<Widget> head = [
          Padding(
            padding: BolaPuebloUi.paddingTabHeader,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolaPuebloUi.boardHeader(
                  context,
                  subtitle:
                      'Deslizá todo el panel: arriba ayuda, abajo el tablero en vivo.',
                ),
                if (!disponibilidadCargando && !disponible) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(255, 152, 0, 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color.fromRGBO(255, 152, 0, 0.45),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'En «No disponible» no podés enviar ni aceptar ofertas en Bola. '
                            'Activá disponibilidad en tu cuenta para operar aquí.',
                            style: BolaPuebloUi.panelBody(context).copyWith(
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                BolaPuebloUi.actionPanel(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BolaPuebloUi.sectionLabel(
                          context, 'Cómo negociar (conductor)'),
                      _paso(
                        context,
                        '1',
                        'Publicá «Voy para» (ruta y monto) o abrí el mapa completo. Los pasajeros ven primero a los conductores con ruta.',
                      ),
                      _paso(
                        context,
                        '2',
                        'En cada bola abierta mandá tu propuesta. Chat y teléfono aparecen al acordar.',
                      ),
                      _paso(
                        context,
                        '3',
                        'Cuando aceptan tu oferta, usá chat, llamada o WhatsApp en la tarjeta.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: BolaPuebloUi.contentGutter),
            child: _VoyParaTaxistaCta(
              user: user,
              nombre: nombre,
              rol: rol,
              enabled: puedeOperarPool,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: BolaPuebloUi.contentGutter),
            child: FilledButton.icon(
              style: BolaPuebloUi.filledPrimary,
              onPressed: puedeOperarPool
                  ? () {
                      Navigator.of(context, rootNavigator: true)
                          .pushNamed(rutaBolaPueblo);
                    }
                  : null,
              icon: const Icon(Icons.map_rounded, size: 22),
              label: const Text('Abrir mapa y tablero completo'),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: BolaPuebloUi.contentGutter),
            child: Text(
              'TABLERO EN VIVO',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ];

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: BolaPuebloRepo.streamTablero(),
          builder: (context, snap) {
            final safeBottom = MediaQuery.of(context).padding.bottom;
            if (snap.connectionState == ConnectionState.waiting) {
              final cs = Theme.of(context).colorScheme;
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  ...head,
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 3,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.12),
                      color: BolaPuebloTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }
            final docsAll = snap.data?.docs ?? const [];
            final docs = docsAll.where((d) {
              final m = d.data();
              final estado = (m['estado'] ?? '').toString();
              final ownerUid = (m['createdByUid'] ?? '').toString();
              final uidTx = (m['uidTaxista'] ?? '').toString();
              final uidCli = (m['uidCliente'] ?? '').toString();
              if (estado == 'abierta' || estado == 'en_curso') return true;
              if (estado == 'acordada') {
                return ownerUid == user.uid ||
                    uidTx == user.uid ||
                    uidCli == user.uid;
              }
              return false;
            }).toList();

            if (docs.isEmpty) {
              return ListView(
                padding: EdgeInsets.only(bottom: 24 + safeBottom),
                children: [
                  ...head,
                  BolaPuebloUi.emptyBoard(
                    context,
                    icon: Icons.inbox_rounded,
                    message:
                        'Publicá tu ruta con «Voy para…» arriba o esperá pedidos de pasajeros; las tarjetas aparecerán acá.',
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: EdgeInsets.fromLTRB(
                BolaPuebloUi.contentGutter,
                0,
                BolaPuebloUi.contentGutter,
                24 + safeBottom,
              ),
              itemCount: head.length + docs.length,
              itemBuilder: (context, i) {
                if (i < head.length) return head[i];
                final d = docs[i - head.length];
                return BolaPuebloPublicacionCard(
                  docId: d.id,
                  data: d.data(),
                  user: user,
                  nombre: nombre,
                  rol: rol,
                  puedeOperarEnPool: puedeOperarPool,
                  onAbrirModoViaje: (bolaId) {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BolaPuebloViajeActivoPage(bolaId: bolaId),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _VoyParaTaxistaCta extends StatefulWidget {
  const _VoyParaTaxistaCta({
    required this.user,
    required this.nombre,
    required this.rol,
    required this.enabled,
  });

  final User user;
  final String nombre;
  final String rol;
  final bool enabled;

  @override
  State<_VoyParaTaxistaCta> createState() => _VoyParaTaxistaCtaState();
}

class _VoyParaTaxistaCtaState extends State<_VoyParaTaxistaCta> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BolaPuebloUi.sectionLabel(context, 'Conductor · publicá tu ruta'),
        Text(
          'Ej.: estoy en La Vega → voy para la capital. Los pasajeros lo ven en su lista.',
          style: BolaPuebloUi.panelBody(context),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: BolaPuebloUi.filledPrimary.copyWith(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
          onPressed: !widget.enabled || _busy
              ? null
              : () {
                  BolaPuebloDialogs.crearPublicacion(
                    context: context,
                    uid: widget.user.uid,
                    rol: widget.rol,
                    nombre: widget.nombre,
                    tipo: 'oferta',
                    onBusy: (b) {
                      if (mounted) setState(() => _busy = b);
                    },
                  );
                },
          icon: const Icon(Icons.route_rounded, size: 24),
          label: Text(
            _busy ? 'Abriendo…' : 'Voy para…',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
