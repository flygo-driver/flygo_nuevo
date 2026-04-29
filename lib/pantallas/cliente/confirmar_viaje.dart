// lib/pantallas/cliente/confirmar_viaje.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_programado_pendiente.dart';

class ConfirmarViajePage extends StatefulWidget {
  final String origenTexto;
  final String destinoTexto;
  final double latOrigen;
  final double lonOrigen;
  final double latDestino;
  final double lonDestino;
  final double precioCalculado;
  final DateTime? fechaSugerida;
  final String metodoPagoInicial;
  final String tipoVehiculoInicial;
  final bool idaYVueltaInicial;

  const ConfirmarViajePage({
    super.key,
    required this.origenTexto,
    required this.destinoTexto,
    required this.latOrigen,
    required this.lonOrigen,
    required this.latDestino,
    required this.lonDestino,
    required this.precioCalculado,
    this.fechaSugerida,
    this.metodoPagoInicial = 'Efectivo',
    this.tipoVehiculoInicial = 'Carro',
    this.idaYVueltaInicial = false,
  });

  @override
  State<ConfirmarViajePage> createState() => _ConfirmarViajePageState();
}

class _ConfirmarViajePageState extends State<ConfirmarViajePage> {
  late DateTime _fechaHora;
  late String _metodoPago;
  late String _tipoVehiculo;
  late bool _idaYVuelta;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _fechaHora = widget.fechaSugerida ?? DateTime.now();
    _metodoPago = widget.metodoPagoInicial;
    _tipoVehiculo = widget.tipoVehiculoInicial;
    _idaYVuelta = widget.idaYVueltaInicial;
  }

  bool _validLatLon(double lat, double lon) =>
      lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;

  Future<void> _elegirFechaHora() async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _fechaHora.isAfter(now) ? _fechaHora : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Selecciona la fecha',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.greenAccent,
            surface: Colors.black,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted || pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _fechaHora.isAfter(now) ? _fechaHora : now,
      ),
      helpText: 'Selecciona la hora',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.greenAccent,
            surface: Colors.black,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted || pickedTime == null) return;

    setState(() {
      _fechaHora = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _confirmar() async {
    if (_cargando) return;

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para confirmar.')),
      );
      return;
    }

    // Validaciones rápidas de UI
    if (widget.precioCalculado <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El precio debe ser mayor que 0.')),
      );
      return;
    }
    if (!_validLatLon(widget.latOrigen, widget.lonOrigen) ||
        !_validLatLon(widget.latDestino, widget.lonDestino)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordenadas inválidas.')),
      );
      return;
    }

    setState(() => _cargando = true);
    try {
      // 1) Asegura doc de usuario con rol por defecto cliente (si no existe)
      await RolesService.ensureUserDoc(u.uid, defaultRol: Roles.cliente);
      if (!mounted) return;

      // 2) Verifica ROL explícito: solo clientes pueden confirmar
      final rol = (await RolesService.getRol(u.uid))?.toLowerCase().trim();
      if (!mounted) return;
      if (rol != Roles.cliente) {
        // Mensaje claro y sin confundir
        final msg = (rol == Roles.taxista || rol == Roles.admin)
            ? 'Esta cuenta es de $rol. Usa una cuenta de cliente para solicitar viajes.'
            : 'Tu cuenta no es de cliente. Cambia de cuenta para solicitar viajes.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      // 3) Fecha en UTC para guardar (consistente con ProgramarViaje)
      final DateTime fechaUtc = _fechaHora.toUtc();

      // 4) Crear viaje pendiente
      final id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: widget.origenTexto,
        destino: widget.destinoTexto,
        latOrigen: widget.latOrigen,
        lonOrigen: widget.lonOrigen,
        latDestino: widget.latDestino,
        lonDestino: widget.lonDestino,
        fechaHora: fechaUtc,
        precio: widget.precioCalculado,
        metodoPago: _metodoPago,
        tipoVehiculo: _tipoVehiculo,
        idaYVuelta: _idaYVuelta,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Viaje confirmado: ${id.substring(0, 6)}…')),
      );
      final bool esProgramadoConfirm =
          _fechaHora.isAfter(DateTime.now().add(const Duration(minutes: 10)));
      if (esProgramadoConfirm) {
        await NavigationService.clearAndGo(
          ViajeProgramadoPendiente(viajeId: id),
        );
      } else {
        await NavigationService.clearAndGo(const ViajeEnCursoCliente());
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Firestore (${e.code}): ${e.message ?? e}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error al confirmar: $e')),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool esProgramado =
        _fechaHora.isAfter(DateTime.now().add(const Duration(minutes: 10)));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Confirmar viaje',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Origen/Destino
          Card(
            color: const Color(0xFF121212),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Trayecto',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.radio_button_checked,
                          size: 16, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.origenTexto,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.destinoTexto,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Fecha/Hora
          Card(
            color: const Color(0xFF121212),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    esProgramado ? Icons.schedule : Icons.flash_on,
                    color:
                        esProgramado ? Colors.orangeAccent : Colors.greenAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          esProgramado ? 'Programado para' : 'Para ahora',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('EEE d MMM, HH:mm', 'es')
                              .format(_fechaHora),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _elegirFechaHora,
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Método de pago y tipo de vehículo
          Card(
            color: const Color(0xFF121212),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.credit_card, color: Colors.white70),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          dropdownColor: const Color(0xFF1E1E1E),
                          value: _metodoPago,
                          items: const [
                            DropdownMenuItem(
                                value: 'Efectivo', child: Text('Efectivo')),
                            DropdownMenuItem(
                                value: 'Transferencia',
                                child: Text('Transferencia')),
                          ],
                          onChanged: (v) =>
                              setState(() => _metodoPago = v ?? 'Efectivo'),
                          decoration: const InputDecoration(
                            labelText: 'Método de pago',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  Row(
                    children: [
                      const Icon(Icons.local_taxi, color: Colors.white70),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          dropdownColor: const Color(0xFF1E1E1E),
                          value: _tipoVehiculo,
                          items: const [
                            DropdownMenuItem(
                                value: 'Carro', child: Text('Carro')),
                            DropdownMenuItem(value: 'SUV', child: Text('SUV')),
                            DropdownMenuItem(
                                value: 'Moto', child: Text('Moto')),
                          ],
                          onChanged: (v) =>
                              setState(() => _tipoVehiculo = v ?? 'Carro'),
                          decoration: const InputDecoration(
                            labelText: 'Tipo de vehículo',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  SwitchListTile(
                    value: _idaYVuelta,
                    onChanged: (v) => setState(() => _idaYVuelta = v),
                    title: const Text('Ida y vuelta',
                        style: TextStyle(color: Colors.white)),
                    activeColor: Colors.greenAccent,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Total
          Card(
            color: const Color(0xFF121212),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Total',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                  Text(
                    FormatosMoneda.rd(widget.precioCalculado),
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Botón Confirmar
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _cargando ? null : _confirmar,
              icon: _cargando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle, color: Colors.green),
              label: Text(
                _cargando ? 'Confirmando...' : 'Confirmar viaje',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
