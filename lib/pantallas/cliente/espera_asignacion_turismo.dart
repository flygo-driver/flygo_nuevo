import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class EsperaAsignacionTurismo extends StatefulWidget {
  final String viajeId;
  const EsperaAsignacionTurismo({super.key, required this.viajeId});

  @override
  State<EsperaAsignacionTurismo> createState() =>
      _EsperaAsignacionTurismoState();
}

class _EsperaAsignacionTurismoState extends State<EsperaAsignacionTurismo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getTipoVehiculoLabel(String tipo) {
    switch (tipo) {
      case 'carro':
        return '🚗 Carro Turismo';
      case 'jeepeta':
        return '🚙 Jeepeta Turismo';
      case 'minivan':
        return '🚐 Minivan Turismo';
      case 'bus':
        return '🚌 Bus Turismo';
      default:
        return tipo;
    }
  }

  String _formatFecha(Timestamp? timestamp) {
    if (timestamp == null) return '—';
    final fecha = timestamp.toDate();
    return DateFormat('dd/MM/yyyy - HH:mm', 'es').format(fecha);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: '🏝️ Turismo RAI',
        backWhenCanPop: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('viajes')
            .doc(widget.viajeId)
            .snapshots(),
        builder: (BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildLoadingState();
          }

          final Map<String, dynamic> data =
              snapshot.data!.data() as Map<String, dynamic>;
          final String estado = (data['estado'] ?? '').toString();
          final String taxistaId =
              (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
          final String estadoNorm = EstadosViaje.normalizar(estado);

          if (EstadosViaje.esCancelado(estado)) {
            return _buildErrorState(
              'Este viaje turístico fue cancelado. Puedes solicitar uno nuevo cuando quieras.',
            );
          }

          if (EstadosViaje.esCompletado(estado)) {
            return _buildCompletadoState();
          }

          // Chofer asignado por ADM: mismo flujo que viajes normales (aceptado → en curso)
          if (taxistaId.isNotEmpty &&
              EstadosViaje.activos.contains(estadoNorm)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (BuildContext innerContext) =>
                      const ViajeEnCursoCliente(),
                ),
              );
            });
            return const SizedBox.shrink();
          }

          return _buildWaitingScreen(data);
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1B3D), Colors.black],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 24),
            Text(
              'Preparando tu experiencia turística...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF330000), Colors.black],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                '¡Ups! Algo salió mal',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletadoState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B3D2A), Colors.black],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.greenAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Viaje finalizado',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Este viaje turístico ya se completó. Gracias por confiar en RAI.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (context.mounted) {
                    Navigator.of(context)
                        .popUntil((Route<dynamic> r) => r.isFirst);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metodoPagoLabel(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('transfer')) return 'Transferencia bancaria';
    if (s.contains('efect')) return 'Efectivo';
    if (raw.trim().isEmpty) return '—';
    return raw.trim();
  }

  String? _pasajerosDesdeExtras(Map<String, dynamic> data) {
    final dynamic ex = data['extras'];
    if (ex is! Map) return null;
    final Map map = ex;
    final dynamic p =
        map['pasajeros'] ?? map['numPasajeros'] ?? map['pasajeros_count'];
    if (p == null) return null;
    final String t = p.toString().trim();
    return t.isEmpty ? null : t;
  }

  Widget _buildWaitingScreen(Map<String, dynamic> data) {
    final destino = data['destino'] ?? 'Destino no especificado';
    final origen = data['origen'] ?? 'Origen no especificado';
    final fechaHora = data['fechaHora'] as Timestamp?;
    final precio = (data['precio'] ?? 0).toDouble();
    final tipoVehiculo =
        _getTipoVehiculoLabel(data['subtipoTurismo'] ?? 'carro');
    final distancia = (data['distanciaKm'] ?? 0).toDouble();
    final String estadoRaw = (data['estado'] ?? '').toString();
    final String? pasajeros = _pasajerosDesdeExtras(data);
    final String metodoPago =
        _metodoPagoLabel((data['metodoPago'] ?? '').toString());

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1B3D), Color(0xFF1A0F2A), Colors.black],
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: SizedBox(height: 8), // Espacio después del AppBar
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Ilustración animada
                  SizedBox(
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (BuildContext context, Widget? child) {
                            return Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.purple.withValues(
                                    alpha: _pulseAnimation.value * 0.3),
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.purple.withValues(alpha: 0.2),
                            border: Border.all(color: Colors.purple, width: 2),
                          ),
                          child: const Icon(
                            Icons.beach_access,
                            color: Colors.purple,
                            size: 50,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Mensaje principal
                  Center(
                    child: Text(
                      estadoRaw.toLowerCase() == 'pendiente_admin'
                          ? 'Tu viaje esta en ADM'
                          : '✅ ¡Viaje solicitado!',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: Text(
                      estadoRaw.toLowerCase() == 'pendiente_admin'
                          ? 'Solicitud recibida correctamente.\nEn breve te asignamos un chofer de turismo.'
                          : 'Buscando el mejor chofer para ti',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        height: 1.35,
                      ),
                    ),
                  ),

                  if (estadoRaw.toLowerCase() == 'pendiente_admin') ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  Colors.purpleAccent.withValues(alpha: 0.5)),
                        ),
                        child: const Text(
                          'Estado: pendiente de asignacion por ADM',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Barra de progreso
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (BuildContext context, Widget? child) {
                            return LinearProgressIndicator(
                              value: _controller.value * 0.5,
                              backgroundColor: Colors.white10,
                              color: Colors.purple,
                              minHeight: 8,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Asignando chofer...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            Text(
                              '⏳ 2-5 min',
                              style: TextStyle(
                                color: Colors.purple.shade200,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Detalles del viaje
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: [
                        // Viaje ID
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.purple),
                              ),
                              child: Text(
                                '#${widget.viajeId.substring(0, 8)}',
                                style: const TextStyle(
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Origen y destino
                        _infoRow(Icons.flag, 'Origen', origen),
                        const SizedBox(height: 8),
                        _infoRow(Icons.flag, 'Destino', destino,
                            color: Colors.greenAccent),

                        const SizedBox(height: 12),

                        // Más detalles
                        if (fechaHora != null) ...[
                          _infoRow(Icons.calendar_today, 'Fecha',
                              _formatFecha(fechaHora)),
                          const SizedBox(height: 8),
                        ],

                        _infoRow(
                            Icons.directions_car, 'Vehículo', tipoVehiculo),

                        if (pasajeros != null) ...[
                          const SizedBox(height: 8),
                          _infoRow(
                              Icons.people_outline, 'Pasajeros', pasajeros),
                        ],

                        const SizedBox(height: 8),
                        _infoRow(Icons.payments_outlined, 'Método de pago',
                            metodoPago),

                        if (distancia > 0) ...[
                          const SizedBox(height: 8),
                          _infoRow(Icons.straighten, 'Distancia',
                              FormatosMoneda.km(distancia)),
                        ],

                        const Divider(color: Colors.white24, height: 24),

                        // Precio
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Total',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                FormatosMoneda.rd(precio),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Botón Cancelar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showCancelDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'CANCELAR VIAJE',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Soporte
                  const Center(
                    child: Text(
                      '¿Necesitas ayuda? Contacta a soporte',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color color = Colors.white70}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCancelDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final onSurface = cs.onSurface;
        final muted = onSurface.withValues(alpha: 0.72);
        return AlertDialog(
          backgroundColor: cs.surface,
          title: Text(
            'Cancelar viaje',
            style: TextStyle(color: onSurface),
          ),
          content: Text(
            '¿Estás seguro que deseas cancelar este viaje turístico?',
            style: TextStyle(color: muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: cs.primary),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sí, cancelar'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para cancelar.')),
      );
      return;
    }

    try {
      await ViajesRepo.cancelarPorCliente(
        viajeId: widget.viajeId,
        uidCliente: user.uid,
        motivo: 'Cancelado desde espera turismo',
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }
}
