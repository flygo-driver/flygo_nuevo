import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../modelo/pago_taxista.dart';
import '../../widgets/rai_app_bar.dart';

class BloqueadoPorPagos extends StatefulWidget {
  const BloqueadoPorPagos({super.key});

  @override
  State<BloqueadoPorPagos> createState() => _BloqueadoPorPagosState();
}

class _BloqueadoPorPagosState extends State<BloqueadoPorPagos> {
  final user = FirebaseAuth.instance.currentUser;
  final formatter = NumberFormat.currency(locale: 'es', symbol: 'RD\$');
  PagoTaxista? _pagoPendiente;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarPagosPendientes();
  }

  Future<void> _cargarPagosPendientes() async {
    if (user == null) return;

    try {
      final pagos = await PagosTaxistaRepo.streamPagosPorTaxista(user!.uid).first;
      
      PagoTaxista? pendiente;
      try {
        pendiente = pagos.firstWhere(
          (p) => p.estado == 'pendiente' || p.estado == 'vencido',
        );
      } catch (e) {
        pendiente = null;
      }

      if (mounted) {
        setState(() {
          _pagoPendiente = pendiente;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const RaiAppBar(
        title: 'Cuenta Bloqueada',
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
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

                    // Mensaje principal
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'Tu cuenta ha sido bloqueada temporalmente por falta de pago de las comisiones semanales.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

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
                          border: Border.all(color: Colors.redAccent, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.redAccent, size: 24),
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
                                  style: TextStyle(color: Colors.white70, fontSize: 16),
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
                            descripcion: 'Transfiere el monto indicado a la cuenta de la empresa',
                          ),
                          _buildPaso(
                            numero: '2',
                            titulo: 'Sube el comprobante',
                            descripcion: 'Ve a "Mis Pagos" y sube la foto del comprobante',
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

                    // Información bancaria
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.account_balance, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'Datos bancarios',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Banco: Banco de Reservas',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            'Titular: FlyGo RD SRL',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            'Cuenta: 960-123456-7',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            'RNC: 1-31-12345-6',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Botones de acción
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(context, '/mis_pagos');
                            },
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
                      onPressed: _cerrarSesion,  // ✅ Usamos método separado
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
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
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