// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/auto_trip_router.dart'; // TaxistaTripRouter

class _Item {
  final Viaje v;
  final DateTime fecha;
  final DateTime acceptAfter;
  final bool esAhora;
  const _Item(this.v, this.fecha, this.acceptAfter, this.esAhora);
}

class ViajeDisponible extends StatefulWidget {
  const ViajeDisponible({super.key});
  @override
  State<ViajeDisponible> createState() => _ViajeDisponibleState();
}

class _ViajeDisponibleState extends State<ViajeDisponible>
    with WidgetsBindingObserver {
  final Set<String> _aceptandoIds = <String>{};
  final Set<String> _vistosParaTimbre = <String>{};
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreAhora;
  StreamSubscription<fs.QuerySnapshot<Map<String, dynamic>>>? _subTimbreProg;

  bool _usarFallbackSinIndiceAhora = false;
  bool _usarFallbackSinIndiceProg = false;

  bool _ignorarPrimeraEmisionTimbreAhora = true;
  bool _ignorarPrimeraEmisionTimbreProg = true;

  static const List<String> _kEstadosPend = <String>[
    EstadosViaje.pendiente,
    'pendiente_pago',
    'pendientePago',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    Future.microtask(() => NotificationService.I.ensureInited());
    Future.microtask(() async {
      await _probarIndices();
      _arrancarTimbres();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subTimbreAhora?.cancel();
    _subTimbreProg?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _arrancarTimbres();
    }
  }

  // ===== QUERIES (con y sin índice) =====

  fs.Query<Map<String, dynamic>> _qPoolAhora() {
    return fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: _kEstadosPend)
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: true)
        .where('publishAt', isLessThanOrEqualTo: fs.Timestamp.now())
        .where('acceptAfter', isLessThanOrEqualTo: fs.Timestamp.now())
        .orderBy('publishAt', descending: false); // asc
  }

  fs.Query<Map<String, dynamic>> _qPoolProgramados() {
    return fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: _kEstadosPend)
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: false)
        .where('publishAt', isLessThanOrEqualTo: fs.Timestamp.now())
        .where('acceptAfter', isLessThanOrEqualTo: fs.Timestamp.now())
        .orderBy('fechaHora', descending: false); // asc
  }

  // Fallback simple (sin índice): traemos recientes y filtramos en memoria
  fs.Query<Map<String, dynamic>> _qFallbackBase() {
    return fs.FirebaseFirestore.instance
        .collection('viajes')
        .orderBy('updatedAt', descending: true);
  }

  Future<void> _probarIndices() async {
    try {
      await _qPoolAhora().limit(1).get(const fs.GetOptions(source: fs.Source.server));
      _usarFallbackSinIndiceAhora = false;
    } on fs.FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      _usarFallbackSinIndiceAhora = e.code == 'failed-precondition' || msg.contains('index');
    } catch (_) {
      _usarFallbackSinIndiceAhora = false;
    }

    try {
      await _qPoolProgramados().limit(1).get(const fs.GetOptions(source: fs.Source.server));
      _usarFallbackSinIndiceProg = false;
    } on fs.FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      _usarFallbackSinIndiceProg = e.code == 'failed-precondition' || msg.contains('index');
    } catch (_) {
      _usarFallbackSinIndiceProg = false;
    }

    if (!mounted) return;
    setState(() {});
  }

  // ===== TIMBRES =====

  void _arrancarTimbres() {
    _subTimbreAhora?.cancel();
    _subTimbreProg?.cancel();

    final fs.Query<Map<String, dynamic>> qA =
        _usarFallbackSinIndiceAhora ? _qFallbackBase() : _qPoolAhora();
    final fs.Query<Map<String, dynamic>> qP =
        _usarFallbackSinIndiceProg ? _qFallbackBase() : _qPoolProgramados();

    _subTimbreAhora = qA.limit(60).snapshots().listen((snap) async {
      if (_ignorarPrimeraEmisionTimbreAhora) {
        _ignorarPrimeraEmisionTimbreAhora = false;
        return;
      }
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      for (final ch in snap.docChanges) {
        if (ch.type != fs.DocumentChangeType.added) continue;
        final data = ch.doc.data();
        if (data == null) continue;

        if (_usarFallbackSinIndiceAhora && !_pasaFiltroAhoraLocal(data)) continue;
        if (!_disponibleParaMi(data, myUid)) continue;

        final id = ch.doc.id;
        if (_vistosParaTimbre.contains(id)) continue;
        _vistosParaTimbre.add(id);

        await NotificationService.I.notifyNuevoViaje(
          viajeId: id,
          titulo: 'Nuevo viaje disponible',
          cuerpo: '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        );
      }
    });

    _subTimbreProg = qP.limit(80).snapshots().listen((snap) async {
      if (_ignorarPrimeraEmisionTimbreProg) {
        _ignorarPrimeraEmisionTimbreProg = false;
        return;
      }
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      for (final ch in snap.docChanges) {
        if (ch.type != fs.DocumentChangeType.added) continue;
        final data = ch.doc.data();
        if (data == null) continue;

        if (_usarFallbackSinIndiceProg && !_pasaFiltroProgLocal(data)) continue;
        if (!_disponibleParaMi(data, myUid)) continue;

        final id = ch.doc.id;
        if (_vistosParaTimbre.contains(id)) continue;
        _vistosParaTimbre.add(id);

        await NotificationService.I.notifyNuevoViaje(
          viajeId: id,
          titulo: 'Viaje programado disponible',
          cuerpo: '${(data['origen'] ?? 'Origen')} → ${(data['destino'] ?? 'Destino')}',
        );
      }
    });
  }

  bool _disponibleParaMi(Map<String, dynamic> data, String myUid) {
    if ((data['uidTaxista'] ?? '').toString().isNotEmpty) return false;
    final estado = (data['estado'] ?? '').toString();
    if (!_kEstadosPend.contains(estado)) return false;

    final ignorados = (data['ignoradosPor'] as List?)?.cast<String>() ?? const <String>[];
    if (myUid.isNotEmpty && ignorados.contains(myUid)) return false;

    final reservadoPor = (data['reservadoPor'] ?? '').toString();
    final rh = data['reservadoHasta'];
    DateTime? vence;
    if (rh is fs.Timestamp) vence = rh.toDate();
    if (rh is DateTime) vence = rh;
    final bool reservaVigente = reservadoPor.isNotEmpty && (vence == null || vence.isAfter(DateTime.now()));
    if (reservaVigente) return false;

    return true;
  }

  // Fallback local (replica publishAt<=now y acceptAfter<=now)
  bool _pasaFiltroAhoraLocal(Map<String, dynamic> d) {
    final esAhora = (d['esAhora'] == true);
    DateTime? pub, acc;
    final publishAt = d['publishAt'];
    if (publishAt is fs.Timestamp) pub = publishAt.toDate();
    if (publishAt is DateTime) pub = publishAt;
    final rawA = d['acceptAfter'];
    if (rawA is fs.Timestamp) acc = rawA.toDate();
    if (rawA is DateTime) acc = rawA;
    final now = DateTime.now();
    return esAhora && pub != null && !now.isBefore(pub) && (acc == null || !now.isBefore(acc));
  }

  bool _pasaFiltroProgLocal(Map<String, dynamic> d) {
    final esAhora = (d['esAhora'] == true);
    if (esAhora) return false;
    DateTime? pub, acc;
    final rawP = d['publishAt'];
    if (rawP is fs.Timestamp) pub = rawP.toDate();
    if (rawP is DateTime) pub = rawP;
    final rawA = d['acceptAfter'];
    if (rawA is fs.Timestamp) acc = rawA.toDate();
    if (rawA is DateTime) acc = rawA;
    final now = DateTime.now();
    return (pub != null && !now.isBefore(pub)) && (acc == null || !now.isBefore(acc));
  }

  // ===== ACEPTAR =====
  Future<void> _aceptarViaje(
    Viaje v, {
    required bool disponible,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    final taxista = FirebaseAuth.instance.currentUser;

    if (taxista == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (!disponible) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Activa tu disponibilidad para aceptar.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    if (_aceptandoIds.contains(v.id)) return;

    if (mounted) setState(() => _aceptandoIds.add(v.id));
    try {
      await ViajesRepo.ensureTaxistaLibre(taxista.uid);
      await ViajesRepo.ensureSiguienteCoherente(taxista.uid);

      final res = await ViajesRepo.claimTripWithReason(
        viajeId: v.id,
        uidTaxista: taxista.uid,
        nombreTaxista: taxista.displayName ?? taxista.email ?? 'taxista',
        telefono: '',
        placa: '',
      );

      if (!mounted) return;

      if (res == 'ok') {
        await fs.FirebaseFirestore.instance.collection('usuarios').doc(taxista.uid).set({
          'siguienteViajeId': '',
          'updatedAt': fs.FieldValue.serverTimestamp(),
          'actualizadoEn': fs.FieldValue.serverTimestamp(),
        }, fs.SetOptions(merge: true));

        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('✅ Viaje aceptado. (pantalla de curso pendiente)'), backgroundColor: Colors.green),
        );
        return;
      }

      if (res == 'taxista-ocupado') {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tienes un viaje activo. Te enviaremos a la pantalla de curso cuando esté lista.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }

      final msg = () {
        switch (res) {
          case 'no-existe': return 'El viaje ya no existe.';
          case 'estado-no-pendiente': return 'El viaje ya no está pendiente.';
          case 'ya-asignado': return 'Ese viaje ya fue asignado.';
          case 'acceptAfter-futuro': return 'Aún no se libera (acceptAfter en el futuro).';
          case 'publish-futuro': return 'Aún no se publica (publishAt en el futuro).';
          case 'reservado-otro': return 'Reservado por otro taxista.';
          case 'taxista-ocupado': return 'Tienes un viaje activo. Finalízalo o cancélalo.';
          default:
            if (res.startsWith('permiso:')) return 'Permisos/reglas Firestore: ${res.split(':').last}';
            return 'No se pudo aceptar: $res';
        }
      }();

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('❌ No se pudo aceptar: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (!mounted) return;
      setState(() => _aceptandoIds.remove(v.id));
    }
  }

  // ===== Helpers =====
  DateTime _fechaDe(Map<String, dynamic> data) {
    final fh = data['fechaHora'];
    if (fh is fs.Timestamp) return fh.toDate();
    if (fh is DateTime) return fh;
    if (fh is String) return DateTime.tryParse(fh) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _acceptAfterDe(Map<String, dynamic> data, DateTime fecha) {
    final raw = data['acceptAfter'];
    if (raw is fs.Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      final p = DateTime.tryParse(raw);
      if (p != null) return p;
    }
    return fecha.subtract(const Duration(hours: 2));
  }

  bool _calcEsAhora(DateTime fecha) => !fecha.isAfter(DateTime.now().add(const Duration(minutes: 15)));

  String _shortPlace(String s) {
    var out = s.trim();
    if (out.isEmpty) return out;

    final reps = <RegExp, String>{
      RegExp(r'aeropuerto.*(las\s*a(m|́)e?ricas|sdq)', caseSensitive: false): 'AILA',
      RegExp(r'\b(sdq)\b', caseSensitive: false): 'AILA',
      RegExp(r'aeropuerto.*cibao', caseSensitive: false): 'Aeropuerto Cibao',
      RegExp(r'aeropuerto.*punta\s*cana|puj', caseSensitive: false): 'Aeropuerto Punta Cana',
      RegExp(r'\bsto\.?\s*dgo\.?\b', caseSensitive: false): 'Santo Domingo',
      RegExp(r'distrito\s*nacional', caseSensitive: false): 'Santo Domingo',
      RegExp(r'rep(ú|u)blica\s*dominicana|dominican\s*republic|\brd\b', caseSensitive: false): '',
    };
    reps.forEach((re, sub) => out = out.replaceAll(re, sub).trim());

    final firstSeg = out.split(',').first.trim();
    if (firstSeg.isNotEmpty && firstSeg.length <= 28) out = firstSeg;

    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (out.length > 28) out = '${out.substring(0, 27).trimRight()}…';
    return out;
  }

  Widget _badgeModo({
    required bool esAhora,
    required DateTime fecha,
    required bool estaLiberado,
    required DateTime acceptAfter,
  }) {
    final icon = esAhora ? Icons.flash_on : Icons.schedule;
    final color = esAhora ? Colors.greenAccent : Colors.orangeAccent;

    String txt;
    if (esAhora) {
      txt = 'Ahora';
    } else if (!estaLiberado) {
      txt = 'Se libera ${DateFormat('HH:mm').format(acceptAfter)}';
    } else {
      txt = 'Programado ${DateFormat('HH:mm').format(fecha)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: esAhora ? const Color.fromRGBO(0, 255, 0, 0.12) : const Color.fromRGBO(255, 165, 0, 0.12),
        border: Border.all(
          color: esAhora ? const Color.fromRGBO(0, 255, 0, 0.7) : const Color.fromRGBO(255, 165, 0, 0.7),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(txt, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _chipInfo(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _bannerNoDisponible() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 152, 0, 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 152, 0, 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orangeAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estás en "No disponible". No podrás aceptar viajes hasta activarlo.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerFallback(bool usarFallback) {
    if (!usarFallback) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(33, 150, 243, 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(33, 150, 243, 0.5)),
      ),
      child: const Text(
        'Modo sin índice: filtrando/ordenando en el dispositivo mientras el índice se crea.',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildLista({
    required Stream<fs.QuerySnapshot<Map<String, dynamic>>> stream,
    required bool disponible,
    required String myUid,
    required bool Function(Map<String, dynamic>) filtroLocalSiFallback,
    required bool ordenarAscEnMemoria,
    required bool usandoFallback,
    required bool esTabAhora,
  }) {
    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error al cargar viajes: ${snapshot.error}',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No hay viajes en este momento.', style: TextStyle(fontSize: 18, color: Colors.white70)),
          );
        }

        final docs = snapshot.data!.docs.toList();
        final items = <_Item>[];

        for (final d in docs) {
          final data = d.data();

          if (usandoFallback && !filtroLocalSiFallback(data)) continue;
          if (!_disponibleParaMi(data, myUid)) continue;

          final v = Viaje.fromMap(d.id, Map<String, dynamic>.from(data));
          final fecha = _fechaDe(data);
          final acceptAfter = _acceptAfterDe(data, fecha);

          final bool esAhoraDoc =
              (data['esAhora'] is bool) ? (data['esAhora'] as bool) : _calcEsAhora(fecha);
          if (esTabAhora && !esAhoraDoc) continue;
          if (!esTabAhora && esAhoraDoc) continue;

          items.add(_Item(v, fecha, acceptAfter, esAhoraDoc));
        }

        if (items.isEmpty) {
          return const Center(
            child: Text('No hay viajes disponibles ahora.', style: TextStyle(fontSize: 18, color: Colors.white70)),
          );
        }

        if (ordenarAscEnMemoria) {
          items.sort((a, b) => a.fecha.compareTo(b.fecha));
        } else if (usandoFallback) {
          items.sort((a, b) => a.acceptAfter.compareTo(b.acceptAfter));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final it = items[index];
            final v = it.v;
            final fecha = it.fecha;
            final acceptAfter = it.acceptAfter;
            final esAhora = it.esAhora;
            final aceptando = _aceptandoIds.contains(v.id);

            final bool estaLiberado = esAhora || !DateTime.now().isBefore(acceptAfter);

            final distanciaKm = DistanciaService.calcularDistancia(
              v.latCliente, v.lonCliente, v.latDestino, v.lonDestino,
            );
            final precioTotal = v.precio;
            final ganancia = (v.gananciaTaxista > 0) ? v.gananciaTaxista : (precioTotal * 0.80);

            return Card(
              color: const Color(0xFF121212),
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message: '${v.origen} → ${v.destino}',
                            waitDuration: const Duration(milliseconds: 500),
                            child: Text(
                              "${_shortPlace(v.origen)} → ${_shortPlace(v.destino)}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _badgeModo(
                              esAhora: esAhora,
                              fecha: fecha,
                              estaLiberado: estaLiberado,
                              acceptAfter: acceptAfter,
                            ),
                            const SizedBox(height: 6),
                            _CountdownChip(
                              fecha: esAhora ? fecha : (estaLiberado ? fecha : acceptAfter),
                              label: esAhora ? 'sale' : (estaLiberado ? 'sale' : 'se libera'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    Text(
                      DateFormat('EEE d MMM, HH:mm', 'es').format(fecha),
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chipInfo(Icons.straighten, "Dist.: ${FormatosMoneda.km(distanciaKm)}"),
                        _chipInfo(Icons.credit_card, v.metodoPago),
                        if (!esAhora) _chipInfo(Icons.event, DateFormat('dd/MM HH:mm').format(fecha)),
                        if (v.tipoVehiculo.isNotEmpty) _chipInfo(Icons.local_taxi, v.tipoVehiculo),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Total", style: TextStyle(color: Colors.white54, fontSize: 12)),
                              Text(
                                FormatosMoneda.rd(precioTotal),
                                style: const TextStyle(
                                  fontSize: 22, color: Colors.yellow, fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("Ganas", style: TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(
                              FormatosMoneda.rd(ganancia),
                              style: const TextStyle(
                                fontSize: 18, color: Colors.greenAccent, fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (aceptando || !disponible || (!esAhora && !estaLiberado))
                            ? null
                            : () => _aceptarViaje(v, disponible: disponible),
                        icon: aceptando
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle, size: 22, color: Colors.green),
                        label: Text(
                          aceptando
                              ? "Aceptando..."
                              : (!disponible
                                  ? "No disponible"
                                  : (!esAhora && !estaLiberado ? "Todavía no disponible" : "Aceptar viaje")),
                          style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

    if (u == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Viajes Disponibles', style: TextStyle(color: Colors.white)),
          centerTitle: true,
        ),
        body: const Center(child: Text('Inicia sesión', style: TextStyle(color: Colors.white70))),
      );
    }

    final streamAhora = _usarFallbackSinIndiceAhora
        ? _qFallbackBase().limit(120).snapshots()
        : _qPoolAhora().limit(120).snapshots();

    final streamProg = _usarFallbackSinIndiceProg
        ? _qFallbackBase().limit(200).snapshots()
        : _qPoolProgramados().limit(200).snapshots();

    return TaxistaTripRouter(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.black,
          drawer: const TaxistaDrawer(),
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: 'Menú',
              ),
            ),
            title: const Text(
              'Viajes Disponibles',
              style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: const [SaldoGananciasChip()],
            bottom: const TabBar(
              indicatorColor: Colors.greenAccent,
              tabs: [Tab(text: 'AHORA'), Tab(text: 'PROGRAMADOS')],
            ),
          ),
          body: StreamBuilder<bool?>(
            stream: RolesService.streamDisponibilidad(u.uid),
            builder: (context, dispSnap) {
              final disponible = dispSnap.data ?? false;

              return Column(
                children: [
                  if (!disponible) _bannerNoDisponible(),
                  _bannerFallback(_usarFallbackSinIndiceAhora || _usarFallbackSinIndiceProg),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildLista(
                          stream: streamAhora,
                          disponible: disponible,
                          myUid: u.uid,
                          filtroLocalSiFallback: _pasaFiltroAhoraLocal,
                          ordenarAscEnMemoria: false,
                          usandoFallback: _usarFallbackSinIndiceAhora,
                          esTabAhora: true,
                        ),
                        _buildLista(
                          stream: streamProg,
                          disponible: disponible,
                          myUid: u.uid,
                          filtroLocalSiFallback: _pasaFiltroProgLocal,
                          ordenarAscEnMemoria: true,
                          usandoFallback: _usarFallbackSinIndiceProg,
                          esTabAhora: false,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final DateTime fecha;
  final String label;
  const _CountdownChip({required this.fecha, this.label = 'sale'});

  String _fmt(Duration d) {
    if (d.inSeconds <= 0) return 'ahora';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h <= 0) return 'en ${m}m';
    return 'en ${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(const Duration(seconds: 30), (_) => DateTime.now()),
      initialData: DateTime.now(),
      builder: (context, snap) {
        final now = snap.data ?? DateTime.now();
        final txt = _fmt(fecha.difference(now));

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 255, 255, 0.12),
            border: Border.all(color: const Color.fromRGBO(0, 255, 255, 0.7)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 6),
              Text('$label $txt', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }
}
