// Centro de operaciones ADM: cola de trabajo diaria con contadores en vivo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../servicios/pagos_taxista_repo.dart';
import '../../servicios/turismo_control_adm_repo.dart';
import '../../widgets/admin_drawer.dart';
import '../../widgets/admin_app_bar.dart';
import 'admin_expediente_chofer_utils.dart';
import 'admin_alertas.dart';
import 'admin_bola_pueblo_ops.dart';
import 'admin_home.dart';
import 'admin_torre_control.dart';
import 'admin_ui_theme.dart';
import 'admin_turismo_control.dart';
import 'aprobar_choferes_turismo.dart';
import 'gestionar_usuarios_admin.dart';
import 'revision_documentos_admin.dart';
import 'taxistas_turismo_admin.dart';
import 'verificar_pagos.dart';

class AdminCentroOperaciones extends StatelessWidget {
  const AdminCentroOperaciones({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: const AdminAppBar(
        title: 'Centro de operaciones',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _MetricasLiveBanner(),
          const SizedBox(height: 16),
          Text(
            'Operación en vivo',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          _MetricasColaCard(
            metricKey: 'viajesActivos',
            icon: Icons.radar,
            color: Colors.lightBlueAccent,
            titulo: 'Torre de control',
            subtitulo: 'Viajes en curso ahora',
            detalleFallback: 'Monitoreo en tiempo real',
            onTap: () => _push(context, const AdminTorreControl()),
          ),
          const SizedBox(height: 10),
          _MetricasColaCard(
            metricKey: 'alertasNoLeidas',
            icon: Icons.notifications_active,
            color: Colors.redAccent,
            titulo: 'Alertas operativas',
            subtitulo: 'Umbrales y resumen horario',
            detalleFallback: 'Sin alertas nuevas',
            onTap: () => _push(context, const AdminAlertasPage()),
          ),
          const SizedBox(height: 10),
          _MetricasColaCard(
            metricKey: 'bolasAbiertas',
            icon: Icons.hub_outlined,
            color: Colors.tealAccent,
            titulo: 'Bola Pueblo',
            subtitulo: 'Publicaciones abiertas',
            detalleFallback: 'Ver tablero completo',
            onTap: () => _push(context, const AdminBolaPuebloOps()),
          ),
          const SizedBox(height: 24),
          Text(
            'Prepago y bloqueos',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recargas de comisión y taxistas bloqueados por saldo prepago.',
            style: TextStyle(color: AdminUi.secondary(context), fontSize: 13),
          ),
          const SizedBox(height: 12),
          _ColaRecargasPrepagoCard(
            onTap: () => _push(
              context,
              const VerificarPagos(
                initialTabIndex: 0,
                initialFiltroRecarga: 'pendiente_verificacion',
              ),
            ),
          ),
          const SizedBox(height: 10),
          _MetricasColaCard(
            metricKey: 'bloqueosComision',
            icon: Icons.lock_clock,
            color: Colors.amber,
            titulo: 'Taxistas bloqueados',
            subtitulo: 'tienePagoPendiente · prepago bajo',
            detalleFallback: 'Sin bloqueos por comisión',
            onTap: () => _push(
              context,
              const GestionarUsuariosAdmin(modoInicial: 'bloqueados'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Colas de aprobación',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Prioriza lo pendiente. Turismo y taxistas normales/motor/bola '
            'tienen flujos separados.',
            style: TextStyle(color: AdminUi.secondary(context), fontSize: 13),
          ),
          const SizedBox(height: 16),
          _ColaExpedientesCard(onTap: () => _push(context, const RevisionDocumentosAdmin())),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          _ColaTurismoPedidosCard(
            onTap: () => _push(context, const AdminTurismoControl()),
          ),
          const SizedBox(height: 10),
          _ColaTurismoCard(onTap: () => _push(context, const AprobarChoferesTurismo())),
          const SizedBox(height: 10),
          _ColaLiquidacionesCard(onTap: () => _push(context, const AdminHome())),
          const SizedBox(height: 10),
          _ColaPagosCard(
            onTap: () => _push(
              context,
              const VerificarPagos(initialTabIndex: 1),
            ),
          ),
          const SizedBox(height: 10),
          const _ColaGirasRaiCard(),
          const SizedBox(height: 10),
          _AccesoSecundario(
            icon: Icons.account_balance_outlined,
            titulo: 'Conciliación banco RAI',
            subtitulo: 'Extracto Popular · ref RAI-V y RAI-P · confirmar pagos',
            onTap: () => _push(
              context,
              const VerificarPagos(initialTabIndex: 4),
            ),
          ),
          const SizedBox(height: 10),
          _AccesoSecundario(
            icon: Icons.tour_outlined,
            titulo: 'Giras RAI · recaudo central',
            subtitulo: 'Verificar pagos clientes · liquidar neto organizador',
            onTap: () => _push(
              context,
              const VerificarPagos(initialTabIndex: 5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Flota y usuarios',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          _AccesoSecundario(
            icon: Icons.manage_accounts_outlined,
            titulo: 'Gestionar usuarios',
            subtitulo: 'Bloqueos, roles y choferes aprobados',
            onTap: () => _push(context, const GestionarUsuariosAdmin()),
          ),
          const SizedBox(height: 8),
          _AccesoSecundario(
            icon: Icons.tour_outlined,
            titulo: 'Choferes turismo activos',
            subtitulo: 'Flota turística ya aprobada',
            onTap: () => _push(context, const TaxistasTurismoAdmin()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class _ColaExpedientesCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ColaExpedientesCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .where('docsEstado', isEqualTo: 'en_revision')
          .limit(300)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final filtrados = docs
            .map((e) => e.data())
            .where(AdminExpedienteChoferUtils.esExpedienteTaxistaOperativo)
            .toList();
        final motores = AdminExpedienteChoferUtils.contarPorLinea(
          filtrados,
          AdminLineaChoferFiltro.motor,
        );
        final bola = AdminExpedienteChoferUtils.contarPorLinea(
          filtrados,
          AdminLineaChoferFiltro.bolaAhorro,
        );
        return _ColaCard(
          icon: Icons.folder_shared_outlined,
          color: const Color(0xFF66BB6A),
          titulo: 'Expedientes choferes',
          subtitulo: 'Normal · Motor · Bola Ahorro',
          count: filtrados.length,
          detalle: filtrados.isEmpty
              ? 'Sin pendientes'
              : '$motores motor · $bola bola · ${filtrados.length - motores - bola} normal',
          onTap: onTap,
        );
      },
    );
  }
}

class _ColaTurismoPedidosCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ColaTurismoPedidosCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: TurismoControlAdmRepo.streamViajesTurismo(limit: 80),
      builder: (context, snapViajes) {
        int sinChofer = 0;
        for (final doc in snapViajes.data?.docs ?? const []) {
          final d = doc.data();
          final uid =
              (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
          if (uid.isNotEmpty) continue;
          final estado = (d['estado'] ?? '').toString();
          if (estado == 'cancelado' ||
              estado == 'completado' ||
              d['completado'] == true) {
            continue;
          }
          sinChofer++;
        }
        return StreamBuilder<int>(
          stream: TurismoControlAdmRepo.streamConteoMensajesNoLeidos(),
          builder: (context, snapMsg) {
            final msg = snapMsg.data ?? 0;
            final detalle = msg > 0
                ? '$sinChofer sin chofer · $msg mensaje${msg == 1 ? '' : 's'} nuevo${msg == 1 ? '' : 's'}'
                : sinChofer == 0
                    ? 'Sin pedidos pendientes de chofer'
                    : '$sinChofer pedido${sinChofer == 1 ? '' : 's'} sin chofer';
            return _ColaCard(
              icon: Icons.radar,
              color: Colors.deepPurpleAccent,
              titulo: 'Control turismo',
              subtitulo: 'Pedidos cliente en vivo + mensajes',
              count: sinChofer + msg,
              detalle: detalle,
              onTap: onTap,
            );
          },
        );
      },
    );
  }
}

class _ColaTurismoCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ColaTurismoCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('solicitudes_turismo')
          .where('estado', isEqualTo: 'pendiente')
          .snapshots(),
      builder: (context, snap) {
        final n = snap.data?.docs.length ?? 0;
        return _ColaCard(
          icon: Icons.pending_actions,
          color: Colors.deepPurpleAccent,
          titulo: 'Solicitudes turismo',
          subtitulo: 'Registro y documentos turísticos',
          count: n,
          detalle: n == 0 ? 'Sin pendientes' : 'Revisar vehículos y documentos',
          onTap: onTap,
        );
      },
    );
  }
}

class _ColaLiquidacionesCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ColaLiquidacionesCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('liquidaciones')
          .where('estado', isEqualTo: 'pendiente')
          .snapshots(),
      builder: (context, snap) {
        final n = snap.data?.docs.length ?? 0;
        return _ColaCard(
          icon: Icons.receipt_long_outlined,
          color: AdminUi.accentGreen(context),
          titulo: 'Liquidaciones',
          subtitulo: 'Comisiones por revisar',
          count: n,
          detalle: n == 0 ? 'Al día' : 'Abrir panel de liquidaciones',
          onTap: onTap,
        );
      },
    );
  }
}

class _ColaPagosCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ColaPagosCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: PagosTaxistaRepo.streamPagosPendientes(),
      builder: (context, snap) {
        final n = snap.data?.length ?? 0;
        return _ColaCard(
          icon: Icons.verified_outlined,
          color: Colors.deepOrange,
          titulo: 'Pagos taxistas',
          subtitulo: 'Comprobantes por verificar',
          count: n,
          detalle: n == 0 ? 'Sin pagos pendientes' : 'Verificar transferencias',
          onTap: onTap,
        );
      },
    );
  }
}

/// Pagos pool central pendientes + liquidaciones neto al organizador.
class _ColaGirasRaiCard extends StatelessWidget {
  const _ColaGirasRaiCard();

  @override
  Widget build(BuildContext context) {
    final pagosStream = FirebaseFirestore.instance
        .collectionGroup('reservas')
        .where('recaudoDestino', isEqualTo: 'rai')
        .where('estado', isEqualTo: 'reservado')
        .where('estadoPago', isEqualTo: 'pendiente')
        .limit(200)
        .snapshots();
    final liqStream = FirebaseFirestore.instance
        .collection('liquidaciones_pool')
        .where('estado', isEqualTo: 'pendiente_pago')
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pagosStream,
      builder: (context, snapPagos) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: liqStream,
          builder: (context, snapLiq) {
            final nPagos = snapPagos.data?.docs.length ?? 0;
            final nLiq = snapLiq.data?.docs.length ?? 0;
            final total = nPagos + nLiq;
            return _ColaCard(
              icon: Icons.beach_access_outlined,
              color: Colors.cyan,
              titulo: 'Giras RAI · recaudo central',
              subtitulo: 'Pagos clientes + neto organizador',
              count: total,
              detalle: total == 0
                  ? 'Sin pendientes en recaudo central'
                  : '$nPagos pagos · $nLiq liquidaciones',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const VerificarPagos(initialTabIndex: 5),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ColaCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titulo;
  final String subtitulo;
  final int count;
  final String detalle;
  final VoidCallback onTap;

  const _ColaCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.subtitulo,
    required this.count,
    required this.detalle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool urgente = count > 0;
    return Material(
      color: AdminUi.card(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        color: AdminUi.secondary(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detalle,
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: urgente
                      ? color.withValues(alpha: 0.2)
                      : AdminUi.inputFill(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: urgente ? color : AdminUi.muted(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: AdminUi.muted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColaRecargasPrepagoCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ColaRecargasPrepagoCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('recargas_comision_taxista')
          .where('estado', isEqualTo: 'pendiente_verificacion')
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        final n = snap.data?.docs.length ?? 0;
        return _ColaCard(
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.teal,
          titulo: 'Recargas prepago',
          subtitulo: 'Comprobantes por verificar (efectivo)',
          count: n,
          detalle: n == 0
              ? 'Sin recargas en cola'
              : 'Verificar pagos → Recargas prepago',
          onTap: onTap,
        );
      },
    );
  }
}

class _MetricasLiveBanner extends StatelessWidget {
  const _MetricasLiveBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('admin_metrics')
          .doc('live')
          .snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data() ?? const {};
        final activos = (m['viajesActivos'] as num?)?.toInt() ?? 0;
        final buscando = (m['viajesBuscando'] as num?)?.toInt() ?? 0;
        final completados = (m['viajesCompletados24h'] as num?)?.toInt() ?? 0;
        final cancelados = (m['viajesCancelados24h'] as num?)?.toInt() ?? 0;
        final bloqueos = (m['bloqueosComision'] as num?)?.toInt() ?? 0;
        final recargas = (m['recargasPrepagoPendiente'] as num?)?.toInt() ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AdminUi.accentGreen(context).withValues(alpha: 0.12),
                AdminUi.infoFill(context),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminUi.borderSubtle(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RAI — Panel operativo',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$activos en curso · $buscando buscando · 24h: $completados OK / $cancelados cancel.\n'
                'Prepago: $recargas recargas pendientes · $bloqueos taxistas bloqueados.',
                style: TextStyle(color: AdminUi.secondary(context), fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricasColaCard extends StatelessWidget {
  final String metricKey;
  final IconData icon;
  final Color color;
  final String titulo;
  final String subtitulo;
  final String detalleFallback;
  final VoidCallback onTap;

  const _MetricasColaCard({
    required this.metricKey,
    required this.icon,
    required this.color,
    required this.titulo,
    required this.subtitulo,
    required this.detalleFallback,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('admin_metrics')
          .doc('live')
          .snapshots(),
      builder: (context, snap) {
        final count = (snap.data?.data()?[metricKey] as num?)?.toInt() ?? 0;
        return _ColaCard(
          icon: icon,
          color: color,
          titulo: titulo,
          subtitulo: subtitulo,
          count: count,
          detalle: count == 0 ? detalleFallback : 'Revisar ahora',
          onTap: onTap,
        );
      },
    );
  }
}

class _AccesoSecundario extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _AccesoSecundario({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: AdminUi.card(context),
      leading: Icon(icon, color: AdminUi.iconStandard(context)),
      title: Text(
        titulo,
        style: TextStyle(
          color: AdminUi.onCard(context),
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitulo, style: TextStyle(color: AdminUi.secondary(context))),
      trailing: Icon(Icons.chevron_right, color: AdminUi.muted(context)),
      onTap: onTap,
    );
  }
}
