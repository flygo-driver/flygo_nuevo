import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/widgets/taxista_drawer.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class _Item {
  final Viaje v;
  final DateTime fecha;
  const _Item(this.v, this.fecha);
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subTimbres;

  bool _ignorarPrimeraEmisionTimbre = true;
  bool _usarFallbackSinIndice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    FirebaseAuth.instance.currentUser?.getIdToken(true);
    Future.microtask(() => NotificationService.I.ensureInited());
    Future.microtask(_logProyectoFirebase);
    Future.microtask(_probarIndiceYArrancarTimbre);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subTimbres?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _probarIndiceYArrancarTimbre();
    }
  }

  Future<void> _logProyectoFirebase() async {
    try {
      final app = Firebase.app();
      final opts = app.options;
      debugPrint('[FIREBASE] projectId=${opts.projectId} appId=${opts.appId}');
    } catch (_) {}
  }

  Query<Map<String, dynamic>> basePendientes() {
    // Pool: pendientes (incluye pendiente_pago) y sin taxista
    return FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: [
          EstadosViaje.pendiente,
          EstadosViaje.pendientePago,
        ])
        .where('uidTaxista', isEqualTo: '');
  }

  Future<void> _probarIndiceYArrancarTimbre() async {
    try {
      await basePendientes()
          .orderBy('fechaHora', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      _usarFallbackSinIndice = false;
    } on FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      _usarFallbackSinIndice =
          (e.code == 'failed-precondition' || msg.contains('index'));
    } catch (_) {
      _usarFallbackSinIndice = false;
    }
    if (mounted) setState(() {});
    _escucharNuevosPendientesParaTimbre();
  }

  void _escucharNuevosPendientesParaTimbre() {
    _subTimbres?.cancel();
    Query<Map<String, dynamic>> q = basePendientes();
    if (!_usarFallbackSinIndice) {
      q = q.orderBy('fechaHora', descending: true);
    }
    _subTimbres = q.limit(20).snapshots().listen((snap) async {
      if (_ignorarPrimeraEmisionTimbre) {
        _ignorarPrimeraEmisionTimbre = false;
        return;
      }
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final data = ch.doc.data();
        if (data == null) continue;

        final uidTx = (data['uidTaxista'] ?? '').toString();
        if (uidTx.isNotEmpty) continue;

        // No timbrar al taxista que canceló/rechazó previamente
        final ignorados =
            (data['ignoradosPor'] as List?)?.cast<String>() ?? const <String>[];
        if (myUid.isNotEmpty && ignorados.contains(myUid)) continue;

        final id = ch.doc.id;
        if (_vistosParaTimbre.contains(id)) continue;
        _vistosParaTimbre.add(id);

        final origen = (data['origen'] ?? '').toString();
        final destino = (data['destino'] ?? '').toString();

        await NotificationService.I.notifyNuevoViaje(
          viajeId: id,
          titulo: 'Nuevo viaje disponible',
          cuerpo:
              '${origen.isEmpty ? "Origen" : origen} → ${destino.isEmpty ? "Destino" : destino}',
        );
      }
    });
  }

  Future<void> _aceptarViaje(
    Viaje v, {
    required bool disponible,
  }) async {
    final taxista = FirebaseAuth.instance.currentUser;

    if (taxista == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!disponible) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activa tu disponibilidad para aceptar.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    if (_aceptandoIds.contains(v.id)) return;

    setState(() => _aceptandoIds.add(v.id));
    try {
      final ok = await ViajesRepo.claimTrip(
        viajeId: v.id,
        uidTaxista: taxista.uid,
        nombreTaxista: taxista.displayName ?? taxista.email ?? 'taxista',
        telefono: '',
        placa: '',
      );

      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ese viaje ya fue tomado por otro taxista.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Viaje aceptado.'),
          backgroundColor: Colors.green,
        ),
      );

      // Navegar a "Mi viaje en curso"
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ViajeEnCursoTaxista()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ No se pudo aceptar: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) {
        setState(() => _aceptandoIds.remove(v.id));
      }
    }
  }

  DateTime _fechaDe(Map<String, dynamic> data) {
    final fh = data['fechaHora'];
    if (fh is Timestamp) return fh.toDate();
    if (fh is DateTime) return fh;
    if (fh is String) {
      return DateTime.tryParse(fh) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _esAhora(DateTime fecha) =>
      !fecha.isAfter(DateTime.now().add(const Duration(minutes: 10)));

  String _shortPlace(String s) {
    var out = s.trim();
    if (out.isEmpty) return out;

    final reps = <RegExp, String>{
      RegExp(r'aeropuerto.*(las\s*a(m|́)e?ricas|sdq)', caseSensitive: false):
          'AILA',
      RegExp(r'\b(sdq)\b', caseSensitive: false): 'AILA',
      RegExp(r'aeropuerto.*cibao', caseSensitive: false): 'Aeropuerto Cibao',
      RegExp(r'aeropuerto.*punta\s*cana|puj', caseSensitive: false):
          'Aeropuerto Punta Cana',
      RegExp(r'\bsto\.?\s*dgo\.?\b', caseSensitive: false): 'Santo Domingo',
      RegExp(r'distrito\s*nacional', caseSensitive: false): 'Santo Domingo',
      RegExp(r'rep(ú|u)blica\s*dominicana|dominican\s*republic|\brd\b',
              caseSensitive: false)
          : '',
    };
    reps.forEach((re, sub) => out = out.replaceAll(re, sub).trim());

    final firstSeg = out.split(',').first.trim();
    if (firstSeg.isNotEmpty && firstSeg.length <= 28) out = firstSeg;

    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    if (out.length > 28) out = '${out.substring(0, 27).trimRight()}…';
    return out;
  }

  Widget _badgeModo(DateTime fecha) {
    final esAhora = _esAhora(fecha);
    final txt = esAhora
        ? 'Ahora'
        : 'Programado ${DateFormat('HH:mm').format(fecha)}';
    final color = esAhora ? Colors.greenAccent : Colors.orangeAccent;
    final icon = esAhora ? Icons.flash_on : Icons.schedule;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            txt,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
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

  Widget _bannerFallback() {
    if (!_usarFallbackSinIndice) return const SizedBox.shrink();
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
        'Modo sin índice: ordenado en el dispositivo mientras el índice se construye.',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildLista({
    required Query<Map<String, dynamic>> query,
    required bool disponible,
    required bool Function(DateTime fecha) filtroFecha,
    required bool ordenarAscEnMemoria,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent));
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
            child: Text('No hay viajes en este momento.',
                style: TextStyle(fontSize: 18, color: Colors.white70)),
          );
        }

        final docs = snapshot.data!.docs.toList();
        final items = <_Item>[];

        for (final d in docs) {
          final data = d.data();

          final uidTx = (data['uidTaxista'] ?? '').toString();
          if (uidTx.isNotEmpty) continue;

          final v = Viaje.fromMap(d.id, Map<String, dynamic>.from(data));
          final fecha = _fechaDe(data);

          if (!filtroFecha(fecha)) continue;
          items.add(_Item(v, fecha));
        }

        if (items.isEmpty) {
          return const Center(
            child: Text('No hay viajes disponibles ahora.',
                style: TextStyle(fontSize: 18, color: Colors.white70)),
          );
        }

        if (ordenarAscEnMemoria) {
          items.sort((a, b) => a.fecha.compareTo(b.fecha));
        } else if (_usarFallbackSinIndice) {
          items.sort((a, b) => b.fecha.compareTo(a.fecha));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final it = items[index];
            final v = it.v;
            final fecha = it.fecha;
            final aceptando = _aceptandoIds.contains(v.id);

            final distanciaKm = DistanciaService.calcularDistancia(
              v.latCliente,
              v.lonCliente,
              v.latDestino,
              v.lonDestino,
            );
            final precioTotal = v.precio;
            final ganancia = (v.gananciaTaxista > 0)
                ? v.gananciaTaxista
                : (precioTotal * 0.80);

            return Card(
              color: const Color(0xFF121212),
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.greenAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message: '${v.origen} → ${v.destino}',
                              waitDuration:
                                  const Duration(milliseconds: 500),
                              child: Text(
                                "${_shortPlace(v.origen)} → ${_shortPlace(v.destino)}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _badgeModo(fecha),
                              const SizedBox(height: 6),
                              _CountdownChip(fecha: fecha),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('EEE d MMM, HH:mm', 'es').format(fecha),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chipInfo(Icons.straighten,
                              "Dist.: ${FormatosMoneda.km(distanciaKm)}"),
                          _chipInfo(Icons.credit_card, v.metodoPago),
                          if (!_esAhora(fecha))
                            _chipInfo(Icons.event,
                                DateFormat('dd/MM HH:mm').format(fecha)),
                          if (v.tipoVehiculo.isNotEmpty)
                            _chipInfo(Icons.local_taxi, v.tipoVehiculo),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Total",
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                Text(
                                  FormatosMoneda.rd(precioTotal),
                                  style: const TextStyle(
                                      fontSize: 22,
                                      color: Colors.yellow,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text("Ganas",
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                              Text(
                                FormatosMoneda.rd(ganancia),
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (aceptando || !disponible)
                              ? null
                              : () => _aceptarViaje(v, disponible: disponible),
                          icon: aceptando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle,
                                  size: 22, color: Colors.green),
                          label: Text(
                            aceptando
                                ? "Aceptando..."
                                : (disponible
                                    ? "Aceptar viaje"
                                    : "No disponible"),
                            style: const TextStyle(
                                fontSize: 16,
                                color: Colors.green,
                                fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ]),
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

    Query<Map<String, dynamic>> qBase = basePendientes();
    if (!_usarFallbackSinIndice) {
      qBase = qBase.orderBy('fechaHora', descending: true);
    }
    qBase = qBase.limit(100);

    if (u == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Viajes Disponibles',
              style: TextStyle(color: Colors.white)),
          centerTitle: true,
        ),
        body: const Center(
          child:
              Text('Inicia sesión', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return DefaultTabController(
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
            style: TextStyle(
                fontSize: 24, color: Colors.white, fontWeight: FontWeight.w700),
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
                _bannerFallback(),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildLista(
                        query: qBase,
                        disponible: disponible,
                        filtroFecha: (f) => _esAhora(f),
                        ordenarAscEnMemoria: false,
                      ),
                      _buildLista(
                        query: qBase,
                        disponible: disponible,
                        filtroFecha: (f) => !_esAhora(f),
                        ordenarAscEnMemoria: true,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final DateTime fecha;
  const _CountdownChip({required this.fecha});

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
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 30),
        (_) => DateTime.now(),
      ),
      initialData: DateTime.now(),
      builder: (context, snap) {
        final now = snap.data ?? DateTime.now();
        final txt = _fmt(fecha.difference(now));
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withValues(alpha: 0.12),
            border:
                Border.all(color: Colors.cyanAccent.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 6),
              Text(
                txt,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
