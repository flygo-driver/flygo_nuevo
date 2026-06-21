import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../navegacion/taxista_finanzas_nav.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../modelo/pago_taxista.dart';
import '../../widgets/cuenta_open_ask_deposito_panel.dart';
import '../../widgets/rai_app_bar.dart';
import '../../config/plataforma_economia.dart';
import '../../servicios/logout.dart';

class BloqueadoPorPagos extends StatefulWidget {
  const BloqueadoPorPagos({super.key});

  @override
  State<BloqueadoPorPagos> createState() => _BloqueadoPorPagosState();
}

class _BloqueadoPorPagosState extends State<BloqueadoPorPagos> {
  final user = FirebaseAuth.instance.currentUser;
  final formatter = NumberFormat.currency(locale: 'es', symbol: 'RD\$');
  PagoTaxista? _pagoPendiente;
  Map<String, dynamic>? _billeData;
  Map<String, dynamic>? _usuarioData;
  bool _deudaSemanalVencida = false;
  bool _cargando = true;
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    _cargarPagosPendientes();
  }

  Future<void> _cargarPagosPendientes() async {
    if (user == null) return;

    if (mounted) {
      setState(() {
        _cargando = true;
        _errorCarga = null;
      });
    }

    try {
      final uid = user!.uid;
      final results = await Future.wait<Object?>([
        FirebaseFirestore.instance
            .collection('billeteras_taxista')
            .doc(uid)
            .get(),
        FirebaseFirestore.instance.collection('usuarios').doc(uid).get(),
        PagosTaxistaRepo.tieneDeudaSemanalVencida(uid),
        PagosTaxistaRepo.obtenerPagosAbiertosTaxista(uid),
      ]);

      final bille = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final usr = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final deudaSemanal = results[2] as bool;
      final pagos = results[3] as List<PagoTaxista>;

      PagoTaxista? pendiente;
      for (final p in pagos) {
        if (p.estado == 'pendiente' || p.estado == 'vencido') {
          pendiente = p;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _pagoPendiente = pendiente;
          _billeData = bille.data();
          _usuarioData = usr.data();
          _deudaSemanalVencida = deudaSemanal;
          _cargando = false;
          _errorCarga = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _errorCarga =
              'No pudimos cargar todos los datos. Podés ir a Mis pagos para recargar.';
        });
      }
    }
  }

  String _textoBloqueoPrincipal() {
    return PagosTaxistaRepo.mensajeCuentaBloqueadaOperativo(
      deudaSemanalVencida: _deudaSemanalVencida,
      billeData: _billeData,
      usuarioData: _usuarioData,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No hay sesión activa',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final pctCom = PlataformaEconomia.comisionViajePorcentaje;
    final pctComStr = pctCom == pctCom.roundToDouble()
        ? pctCom.round().toString()
        : pctCom.toStringAsFixed(1);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: 'Cuenta Bloqueada',
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(
                child: CircularProgressIndicator(color: Colors.greenAccent))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icono de bloqueo animado
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: Colors.redAccent,
                        size: 70,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Título
                    const Text(
                      'ACCESO BLOQUEADO',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_errorCarga != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade700),
                        ),
                        child: Text(
                          _errorCarga!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),

                    // Mensaje principal
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _textoBloqueoPrincipal(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(
                        _billeData))
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade700),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              PagosTaxistaRepo.comisionPendienteDesdeBilletera(
                                          _billeData) >=
                                      PagosTaxistaRepo
                                              .umbralComisionLegacyBloqueoRd -
                                          1e-6
                                  ? 'Comisión legacy (tope alcanzado)'
                                  : 'Saldo prepago insuficiente',
                              style: TextStyle(
                                color: Colors.amber.shade200,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Saldo prepago: ${formatter.format(PagosTaxistaRepo.saldoPrepagoComisionDesdeBilletera(_billeData))} '
                              '(mín. RD\$${PagosTaxistaRepo.minSaldoPrepagoComisionRd.toStringAsFixed(0)})',
                              style: TextStyle(
                                color: Colors.amber.shade100,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (PagosTaxistaRepo
                                    .comisionPendienteDesdeBilletera(
                                        _billeData) >
                                1e-6) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Legacy pendiente: ${formatter.format(PagosTaxistaRepo.comisionPendienteDesdeBilletera(_billeData))}',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 14),
                              ),
                            ],
                            if (PagosTaxistaRepo.bloqueoPorComisionLegacyTope(
                                _billeData)) ...[
                              const SizedBox(height: 10),
                              Builder(
                                builder: (context) {
                                  final pend = PagosTaxistaRepo
                                      .comisionPendienteDesdeBilletera(
                                          _billeData);
                                  final minSalir = PagosTaxistaRepo
                                      .montoMinimoRecargaParaSalirBloqueoLegacyRd(
                                          pend);
                                  final minCero = PagosTaxistaRepo
                                      .montoParaLiquidarLegacyCompletoRd(pend);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Montos orientativos (recarga verificada; primero paga legacy):',
                                        style: TextStyle(
                                          color: Colors.amber.shade100,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '• Mínimo para bajar legacy debajo del tope (RD\$${PagosTaxistaRepo.umbralComisionLegacyBloqueoRd.toStringAsFixed(0)}) y poder operar: ${formatter.format(minSalir)}.',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                              alpha: 0.9),
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                      if (minCero > minSalir + 0.01)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            '• Para dejar legacy en cero: ${formatter.format(minCero)}.',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                  alpha: 0.88),
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Salidas por cupos: si además tenés comisión de salida pendiente de admin, puede aplicarse otro tope; revisá Mis pagos.',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                              alpha: 0.72),
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              'Recarga desde Mis pagos: al aprobar el admin, el monto verificado paga primero '
                              'la comisión legacy pendiente (si hay) y el resto suma a tu prepago; el $pctComStr% '
                              'de cada viaje en efectivo se descuenta del prepago disponible.',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),

                    // Tarjeta de deuda
                    if (_pagoPendiente != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade900.withValues(alpha: 0.3),
                              Colors.red.shade900.withValues(alpha: 0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.redAccent, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber,
                                    color: Colors.redAccent, size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'DEUDA PENDIENTE',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Semana:',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  _pagoPendiente!.semana,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Período:',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  '${DateFormat('dd/MM').format(_pagoPendiente!.fechaInicio)} - ${DateFormat('dd/MM').format(_pagoPendiente!.fechaFin)}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(color: Colors.redAccent),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total a pagar:',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 16),
                                ),
                                Text(
                                  formatter.format(_pagoPendiente!.comision),
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Pasos a seguir
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📋 Pasos para recuperar tu acceso:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildPaso(
                            numero: '1',
                            titulo: 'Realiza el pago',
                            descripcion:
                                'Transfiere el monto indicado a la cuenta de la empresa',
                          ),
                          _buildPaso(
                            numero: '2',
                            titulo: 'Sube el comprobante',
                            descripcion:
                                'Ve a "Mis Pagos": pago semanal (URL) o recarga de comisión en efectivo (foto + monto).',
                          ),
                          _buildPaso(
                            numero: '3',
                            titulo: 'Espera verificación',
                            descripcion: 'El admin revisará y aprobará tu pago',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    const CuentaOpenAskDepositoPanel(
                      fondoOscuro: true,
                      mostrarNota: true,
                    ),

                    const SizedBox(height: 24),

                    // Botones de acción
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => TaxistaFinanzasNav.abrirMisPagos(
                              context,
                              scrollToRecargaSection: true,
                            ),
                            icon: const Icon(Icons.payment),
                            label: const Text('IR A MIS PAGOS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(context, '/soporte');
                            },
                            icon: const Icon(Icons.support_agent),
                            label: const Text('CONTACTAR SOPORTE'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // 🔥 Cerrar sesión - DEFINITIVAMENTE LIMPIO
                    TextButton(
                      onPressed: _cerrarSesion, // ✅ Usamos método separado
                      child: const Text(
                        'Cerrar sesión',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ✅ Método separado para cerrar sesión (elimina el warning)
  Future<void> _cerrarSesion() async {
    await cerrarSesion(context);
  }

  static const _gradientePaso = LinearGradient(
    colors: [Colors.redAccent, Colors.orangeAccent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  Widget _buildPaso({
    required String numero,
    required String titulo,
    required String descripcion,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              gradient: _gradientePaso,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                numero,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
