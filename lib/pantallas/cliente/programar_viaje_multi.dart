// lib/pantallas/cliente/programar_viaje_multi.dart
// ✅ CORREGIDO - CÁLCULO AUTOMÁTICO FUNCIONANDO

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:geocoding/geocoding.dart';

import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/places_service.dart';
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/keys.dart' as app_keys;
import 'package:flygo_nuevo/widgets/selector_destinos_turisticos.dart';
import 'package:flygo_nuevo/servicios/turismo_catalogo_rd.dart';

class _LugarSel {
  final String label;
  final double lat;
  final double lon;
  const _LugarSel({required this.label, required this.lat, required this.lon});
}

/// Solo UI: colores por tipo de punto en la ruta (claro / oscuro).
class _EstiloRutaCampo {
  final Color acento;
  final Color fondo;
  final Color borde;
  final IconData icono;
  const _EstiloRutaCampo({
    required this.acento,
    required this.fondo,
    required this.borde,
    required this.icono,
  });
}

class ProgramarViajeMulti extends StatefulWidget {
  const ProgramarViajeMulti({super.key});

  /// Valores estables para Firestore: `ViajePoolTaxistaGate` usa `tipoServicio` + `canalAsignacion`.
  static String normalizarTipoServicioMulti(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'motor':
        return 'motor';
      case 'turismo':
        return 'turismo';
      default:
        return 'normal';
    }
  }

  /// Motor/normal → pool general (`ViajeDisponible`). Turismo → `PoolTurismoTaxista`.
  static String canalAsignacionParaMulti(String tipoNorm) {
    if (tipoNorm == 'turismo') {
      return AsignacionTurismoRepo.canalTurismoPool;
    }
    return 'pool';
  }

  @override
  State<ProgramarViajeMulti> createState() => _ProgramarViajeMultiState();
}

class _ProgramarViajeMultiState extends State<ProgramarViajeMulti> {
  _LugarSel? _origen;
  _LugarSel? _destino;
  final List<_LugarSel?> _paradas = <_LugarSel?>[null];
  DateTime _fechaHora = DateTime.now().add(const Duration(minutes: 30));
  bool _esAhora = true;

  String _tipoServicio = 'normal';
  String _tipoVehiculo = 'Carro';
  String? _tipoVehiculoTurismo = 'carro';
  String _metodoPago = 'Efectivo';

  bool _cargando = false;
  String _mensajeCarga = '';

  double _distKm = 0;
  double _precio = 0;
  double _peaje = 0;
  List<Map<String, dynamic>> _segmentos = [];

  // 🔥 CACHÉ para el contador de viajes
  int? _contadorViajesCache;
  DateTime? _contadorTimestamp;
  Map<String, dynamic>? _promoSnapshotCotizacion;

  // Timer para debounce del cálculo automático
  Timer? _calculoDebounce;

  /// Evita que un cálculo en curso bloquee el siguiente (varios tramos tardan más que el debounce).
  int _calculoSeq = 0;

  /// Resumen compacto tras cotizar (no aplica a turismo).
  bool _vistaResumenCotizada = false;

  Color get _colorServicio {
    switch (_tipoServicio) {
      case 'motor':
        return Colors.orange;
      case 'turismo':
        return Colors.purple;
      default:
        return Colors.greenAccent;
    }
  }

  @override
  void dispose() {
    _calculoDebounce?.cancel();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<int> _obtenerContadorViajes(String uidCliente) async {
    if (_contadorViajesCache != null && 
        _contadorTimestamp != null &&
        DateTime.now().difference(_contadorTimestamp!) < const Duration(minutes: 5)) {
      return _contadorViajesCache!;
    }
    
    try {
      final snapshot = await fs.FirebaseFirestore.instance
          .collection('viajes')
          .where('uidCliente', isEqualTo: uidCliente)
          .where('completado', isEqualTo: true)
          .count()
          .get();
      
      // El MxK se evalúa para el próximo viaje a crear.
      final int contador = (snapshot.count ?? 0) + 1;
      _contadorViajesCache = contador;
      _contadorTimestamp = DateTime.now();
      
      return contador;
    } catch (e) {
      return 1;
    }
  }

  Future<_LugarSel?> _buscarLugar(String titulo) async {
    if (_tipoServicio == 'turismo' && titulo.contains('Destino')) {
      return showModalBottomSheet<_LugarSel?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (bc) => SelectorDestinosTuristicos(
          latOrigen: _origen?.lat,
          lonOrigen: _origen?.lon,
          tipoVehiculoInicial: _tipoVehiculoTurismo,
          onDestinoSeleccionado: (seleccion) {
            String vehiculoValido = seleccion.tipoVehiculo;
            const vehiculosValidos = ['carro', 'jeepeta', 'minivan', 'bus'];
            if (!vehiculosValidos.contains(vehiculoValido)) {
              debugPrint('⚠️ Valor inválido en multi: "$vehiculoValido", usando "carro"');
              vehiculoValido = 'carro';
            }
            
            Navigator.pop(bc, _LugarSel(
              label: seleccion.lugar.nombre,
              lat: seleccion.lugar.lat,
              lon: seleccion.lugar.lon,
            ));
            if (mounted) {
              setState(() {
                _tipoVehiculoTurismo = vehiculoValido;
              });
              _programarCalculoAutomatico();
            }
          },
        ),
      );
    }
    
    return showModalBottomSheet<_LugarSel?>(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bc) => _BuscarLugarSheet(titulo: titulo),
    );
  }

  Future<Map<String, double>> _calcularTramoReal(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    String tramoNombre,
  ) async {
    if (mounted) {
      setState(() {
        _mensajeCarga = 'Calculando ruta: $tramoNombre...';
      });
    }

    try {
      var dir = await DirectionsService.drivingDistanceKm(
        originLat: lat1,
        originLon: lon1,
        destLat: lat2,
        destLon: lon2,
        withTraffic: true,
        region: 'do',
      );

      if (dir == null || dir.km <= 0) {
        dir = await DirectionsService.drivingDistanceKm(
          originLat: lat1,
          originLon: lon1,
          destLat: lat2,
          destLon: lon2,
          withTraffic: false,
          region: 'do',
        );
      }

      double km;
      if (dir != null && dir.km > 0) {
        km = dir.km;
      } else {
        km = DistanciaService.calcularDistancia(lat1, lon1, lat2, lon2);
        if (km > 0) {
          km = (km * 1.15).clamp(0.01, 500.0);
        } else {
          km = 0.05;
        }
      }

      if (km <= 0 || km > 4000) {
        if (mounted) {
          _snack('No se pudo calcular un tramo de la ruta.');
        }
        return <String, double>{'km': 0, 'peaje': 0};
      }

      final double peajeTramo = _estimarPeaje(km, lat1, lon1, lat2, lon2);

      return <String, double>{
        'km': km,
        'peaje': peajeTramo,
      };
    } catch (e) {
      double kmFb = DistanciaService.calcularDistancia(lat1, lon1, lat2, lon2);
      if (kmFb > 0) {
        kmFb = (kmFb * 1.15).clamp(0.05, 500.0);
      } else {
        kmFb = 0.05;
      }
      if (kmFb > 0 && kmFb <= 4000) {
        final double peajeTramo = _estimarPeaje(kmFb, lat1, lon1, lat2, lon2);
        return <String, double>{'km': kmFb, 'peaje': peajeTramo};
      }
      if (mounted) {
        _snack('No se pudo calcular la ruta. Revisa conexión o la API de mapas.');
      }
      return <String, double>{'km': 0, 'peaje': 0};
    }
  }

  double _estimarPeaje(double km, double lat1, double lon1, double lat2, double lon2) {
    const Map<String, Map<String, double>> peajesRD = {
      'las americas': {'lat': 18.45, 'lon': -69.75, 'costo': 150},
      'duarte': {'lat': 19.0, 'lon': -70.5, 'costo': 200},
      'boca chica': {'lat': 18.45, 'lon': -69.63, 'costo': 100},
    };

    double totalPeaje = 0;
    for (final peaje in peajesRD.values) {
      final double distAPeaje = DistanciaService.calcularDistancia(
        lat1,
        lon1,
        peaje['lat']!,
        peaje['lon']!,
      );
      if (distAPeaje < 50) {
        totalPeaje += peaje['costo']!;
      }
    }
    return totalPeaje;
  }

  // ✅ CÁLCULO AUTOMÁTICO - SE EJECUTA CUANDO HAY ORIGEN Y DESTINO
  void _programarCalculoAutomatico() {
    // Solo calcular si tenemos origen Y destino
    if (_origen == null || _destino == null) {
      return;
    }
    
    _calculoDebounce?.cancel();
    _calculoSeq++;
    final int runId = _calculoSeq;
    _calculoDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _calcularConRutasReales(automatico: true, runId: runId);
      }
    });
  }

  void _finCargaMultiSiCorre(int runId) {
    if (!mounted || runId != _calculoSeq) return;
    setState(() {
      _cargando = false;
      _mensajeCarga = '';
    });
  }

  Future<void> _calcularConRutasReales({
    bool automatico = false,
    required int runId,
  }) async {
    if (_origen == null || _destino == null) return;

    setState(() {
      _cargando = true;
      _mensajeCarga = 'Calculando ruta...';
      _vistaResumenCotizada = false;
    });

    try {
      final List<_LugarSel> waypoints = _paradas.whereType<_LugarSel>().toList();
      final List<_LugarSel> ordenParadas = <_LugarSel>[
        _origen!,
        ...waypoints,
        _destino!,
      ];
      final int nTramos = ordenParadas.length - 1;

      final List<Map<String, dynamic>> segmentos = <Map<String, dynamic>>[];
      double totalKm = 0;
      double totalPeaje = 0;

      Future<bool> armarDesdeDirectionsUnaSola() async {
        final List<({double lat, double lon})>? wpCoords = waypoints.isEmpty
            ? null
            : waypoints.map((w) => (lat: w.lat, lon: w.lon)).toList();

        var dir = await DirectionsService.drivingDistanceKm(
          originLat: _origen!.lat,
          originLon: _origen!.lon,
          destLat: _destino!.lat,
          destLon: _destino!.lon,
          waypoints: wpCoords,
          withTraffic: true,
          region: 'do',
        );

        if (dir == null || dir.km <= 0) {
          dir = await DirectionsService.drivingDistanceKm(
            originLat: _origen!.lat,
            originLon: _origen!.lon,
            destLat: _destino!.lat,
            destLon: _destino!.lon,
            waypoints: wpCoords,
            withTraffic: false,
            region: 'do',
          );
        }

        final List<double>? segsRaw = dir?.segmentDistances;
        if (dir == null || dir.km <= 0) {
          return false;
        }

        List<double> segs = <double>[];
        if (segsRaw != null &&
            segsRaw.length == nTramos &&
            segsRaw.every((double s) => s > 0)) {
          segs = List<double>.from(segsRaw);
        } else {
          final List<double> rectas = <double>[];
          double sumRectas = 0;
          for (int i = 0; i < nTramos; i++) {
            final _LugarSel a = ordenParadas[i];
            final _LugarSel b = ordenParadas[i + 1];
            final double h = DistanciaService.calcularDistancia(
              a.lat,
              a.lon,
              b.lat,
              b.lon,
            );
            final double w = h > 0 ? h : 0.01;
            rectas.add(w);
            sumRectas += w;
          }
          if (sumRectas <= 0) {
            return false;
          }
          for (int i = 0; i < nTramos; i++) {
            segs.add(dir.km * (rectas[i] / sumRectas));
          }
        }

        segmentos.clear();
        totalKm = 0;
        totalPeaje = 0;
        for (int i = 0; i < nTramos; i++) {
          final _LugarSel desde = ordenParadas[i];
          final _LugarSel hasta = ordenParadas[i + 1];
          final double kmSeg = segs[i];
          if (kmSeg <= 0) {
            return false;
          }
          final double peajeSeg =
              _estimarPeaje(kmSeg, desde.lat, desde.lon, hasta.lat, hasta.lon);
          segmentos.add(<String, dynamic>{
            'tramo': i + 1,
            'origen': desde.label,
            'destino': hasta.label,
            'km': kmSeg,
            'peaje': peajeSeg,
          });
          totalKm += kmSeg;
          totalPeaje += peajeSeg;
        }
        return true;
      }

      final bool okRuta = await armarDesdeDirectionsUnaSola();

      if (!okRuta) {
        segmentos.clear();
        totalKm = 0;
        totalPeaje = 0;

        double prevLat = _origen!.lat;
        double prevLon = _origen!.lon;
        String prevLabel = _origen!.label;

        for (int i = 0; i < waypoints.length; i++) {
          final _LugarSel w = waypoints[i];
          final Map<String, double> resultado = await _calcularTramoReal(
            prevLat,
            prevLon,
            w.lat,
            w.lon,
            '$prevLabel → ${w.label}',
          );

          if (!mounted || runId != _calculoSeq) return;

          if (resultado['km']! <= 0) {
            if (!automatico && runId == _calculoSeq) {
              _snack('Error en tramo ${i + 1}');
            }
            _finCargaMultiSiCorre(runId);
            return;
          }

          segmentos.add(<String, dynamic>{
            'tramo': i + 1,
            'origen': prevLabel,
            'destino': w.label,
            'km': resultado['km'],
            'peaje': resultado['peaje'],
          });

          totalKm += resultado['km']!;
          totalPeaje += resultado['peaje']!;
          prevLat = w.lat;
          prevLon = w.lon;
          prevLabel = w.label;
        }

        final Map<String, double> resultadoFinal = await _calcularTramoReal(
          prevLat,
          prevLon,
          _destino!.lat,
          _destino!.lon,
          '$prevLabel → ${_destino!.label}',
        );

        if (!mounted || runId != _calculoSeq) return;

        if (resultadoFinal['km']! <= 0) {
          if (!automatico && runId == _calculoSeq) {
            _snack('Error en tramo final');
          }
          _finCargaMultiSiCorre(runId);
          return;
        }

        segmentos.add(<String, dynamic>{
          'tramo': waypoints.length + 1,
          'origen': prevLabel,
          'destino': _destino!.label,
          'km': resultadoFinal['km'],
          'peaje': resultadoFinal['peaje'],
        });

        totalKm += resultadoFinal['km']!;
        totalPeaje += resultadoFinal['peaje']!;
      }

      final TarifaServiceUnificado servicio = TarifaServiceUnificado();
      
      final user = FirebaseAuth.instance.currentUser;
      int contadorViajes = 1;
      if (user != null) {
        contadorViajes = await _obtenerContadorViajes(user.uid);
      }
      if (!mounted || runId != _calculoSeq) return;

      final promoSnapshot =
          await servicio.construirPromoSnapshot(contadorViajes);
      if (!mounted || runId != _calculoSeq) return;
      
      double precio;
      if (_tipoServicio == 'normal') {
        precio = await servicio.calcularPrecio(
          tipoServicio: _tipoServicio,
          tipoVehiculo: _tipoVehiculo,
          distanciaKm: totalKm,
          idaVuelta: false,
          peaje: totalPeaje,
          contadorViajes: contadorViajes,
        );
      } else if (_tipoServicio == 'motor') {
        precio = await servicio.calcularPrecio(
          tipoServicio: _tipoServicio,
          distanciaKm: totalKm,
          idaVuelta: false,
          peaje: totalPeaje,
          contadorViajes: contadorViajes,
        );
      } else {
        String vehiculoValido = _tipoVehiculoTurismo ?? 'carro';
        const vehiculosValidos = ['carro', 'jeepeta', 'minivan', 'bus'];
        if (!vehiculosValidos.contains(vehiculoValido)) {
          vehiculoValido = 'carro';
        }
        
        precio = await servicio.calcularPrecio(
          tipoServicio: _tipoServicio,
          tipoVehiculo: vehiculoValido,
          subtipoTurismo: 'viaje_multi',
          distanciaKm: totalKm,
          idaVuelta: false,
          peaje: totalPeaje,
          contadorViajes: contadorViajes,
        );
      }

      if (!mounted || runId != _calculoSeq) return;

      setState(() {
        _distKm = double.parse(totalKm.toStringAsFixed(2));
        _precio = precio;
        _peaje = totalPeaje;
        _segmentos = segmentos;
        _promoSnapshotCotizacion = promoSnapshot;
        _cargando = false;
        _mensajeCarga = '';
        _vistaResumenCotizada = _tipoServicio != 'turismo';
      });
    } catch (e) {
      if (!automatico && runId == _calculoSeq) {
        _snack('Error calculando rutas: $e');
      }
      _finCargaMultiSiCorre(runId);
    }
  }

  Future<void> _confirmar() async {
    if (_precio <= 0 || _distKm <= 0) {
      _snack('Primero calcula el precio.');
      return;
    }

    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _snack('Debes iniciar sesión.');
      return;
    }

    if (_origen == null || _destino == null) {
      _snack('Selecciona origen y destino.');
      return;
    }

    setState(() => _cargando = true);

    try {
      final List<Map<String, dynamic>> waypoints = <Map<String, dynamic>>[];

      for (final _LugarSel? p in _paradas) {
        if (p == null) continue;
        waypoints.add({
          'lat': p.lat,
          'lon': p.lon,
          'label': p.label,
        });
      }

      final String tipoSrv =
          ProgramarViajeMulti.normalizarTipoServicioMulti(_tipoServicio);
      final String canal =
          ProgramarViajeMulti.canalAsignacionParaMulti(tipoSrv);

      final DateTime nowUtc = DateTime.now().toUtc();
      final DateTime fechaHoraViaje = _esAhora
          ? nowUtc.add(const Duration(minutes: 10))
          : _fechaHora.toUtc();

      DateTime? publishAtArg;
      DateTime? acceptAfterArg;
      if (!_esAhora) {
        publishAtArg =
            ViajesRepo.poolOpensAtForScheduledPickup(fechaHoraViaje, nowUtc);
        acceptAfterArg = publishAtArg;
      }

      final String id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: _origen!.label,
        destino: _destino!.label,
        latOrigen: _origen!.lat,
        lonOrigen: _origen!.lon,
        latDestino: _destino!.lat,
        lonDestino: _destino!.lon,
        fechaHora: fechaHoraViaje,
        precio: _precio,
        metodoPago: _metodoPago,
        tipoVehiculo: tipoSrv == 'turismo'
            ? _mapTipoVehiculoTurismo(_tipoVehiculoTurismo ?? 'carro')
            : tipoSrv == 'motor'
                ? 'Motor'
                : _tipoVehiculo,
        idaYVuelta: false,
        categoria: 'multi',
        tipoServicio: tipoSrv,
        subtipoTurismo: tipoSrv == 'turismo' ? _tipoVehiculoTurismo : null,
        waypoints: waypoints,
        extras: {
          'paradas_count': waypoints.length,
          'segmentos': _segmentos,
          'peaje_total': _peaje,
          'esAhora': _esAhora,
          if (_promoSnapshotCotizacion != null)
            'promoSnapshot': _promoSnapshotCotizacion,
        },
        distanciaKm: _distKm,
        canalAsignacion: canal,
        publishAt: publishAtArg,
        acceptAfter: acceptAfterArg,
      );

      if (!mounted) return;

      _snack('✅ Viaje creado — #${id.substring(0, 6)}');

      if (Navigator.canPop(context)) {
        Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) {
        _snack('Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  String _mapTipoVehiculoTurismo(String tipo) {
    switch (tipo) {
      case 'carro':
        return 'Carro Turismo';
      case 'jeepeta':
        return 'Jeepeta Turismo';
      case 'minivan':
        return 'Minivan Turismo';
      case 'bus':
        return 'Bus Turismo';
      default:
        return 'Carro Turismo';
    }
  }

  Future<void> _seleccionarFechaHora() async {
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _fechaHora,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (!mounted || d == null) return;
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fechaHora),
    );
    if (!mounted || t == null) return;
    setState(() {
      _fechaHora = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _elegirMetodoPago() async {
    if (_cargando) return;
    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final t = Theme.of(ctx);
        final cs = t.colorScheme;
        final onSurface = cs.onSurface;
        final muted = onSurface.withValues(alpha: 0.65);
        final disabled = onSurface.withValues(alpha: 0.38);
        Widget item(String label, {bool enabled = true, String? subtitle}) {
          return ListTile(
            title: Text(
              label,
              style: TextStyle(
                color: enabled ? onSurface : disabled,
                fontWeight: enabled ? FontWeight.normal : FontWeight.w300,
              ),
            ),
            subtitle: subtitle != null
                ? Text(
                    subtitle,
                    style: TextStyle(color: muted, fontSize: 12),
                  )
                : null,
            trailing: label == _metodoPago && enabled
                ? Icon(Icons.check, color: cs.brightness == Brightness.dark ? Colors.greenAccent : const Color(0xFF0F9D58))
                : null,
            enabled: enabled,
            onTap: enabled ? () => Navigator.pop(ctx, label) : null,
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Método de pago',
                style: TextStyle(color: muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              item('Efectivo'),
              item('Tarjeta', enabled: false, subtitle: 'No disponible'),
              item('Transferencia'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (elegido != null && elegido.trim().isNotEmpty) {
      setState(() => _metodoPago = elegido);
    }
  }

  Future<void> _abrirCatalogoTurismo() async {
    final seleccion = await showModalBottomSheet<DestinoSeleccionado>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SelectorDestinosTuristicos(
        latOrigen: _origen?.lat,
        lonOrigen: _origen?.lon,
        tipoVehiculoInicial: _tipoVehiculoTurismo,
        onDestinoSeleccionado: (seleccion) {
          Navigator.pop(context, seleccion);
        },
      ),
    );
    
    if (seleccion != null && mounted) {
      String vehiculoValido = seleccion.tipoVehiculo;
      const vehiculosValidos = ['carro', 'jeepeta', 'minivan', 'bus'];
      if (!vehiculosValidos.contains(vehiculoValido)) {
        debugPrint('⚠️ Valor inválido en catálogo multi: "$vehiculoValido", usando "carro"');
        vehiculoValido = 'carro';
      }
      
      setState(() {
        _destino = _LugarSel(
          label: seleccion.lugar.nombre,
          lat: seleccion.lugar.lat,
          lon: seleccion.lugar.lon,
        );
        _tipoVehiculoTurismo = vehiculoValido;
      });
      _programarCalculoAutomatico();
    }
  }

  Widget _buildDestinoSection({_EstiloRutaCampo? estiloDestino}) {
    if (_tipoServicio == 'turismo') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _btnLugar(
            label: 'Destino Turístico',
            value: _destino?.label,
            estilo: estiloDestino,
            onTap: () async {
              final _LugarSel? sel = await _buscarLugar('Destino Turístico');
              if (!mounted || sel == null) return;
              setState(() => _destino = sel);
              _programarCalculoAutomatico();
            },
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _abrirCatalogoTurismo,
            icon: Icon(Icons.explore, size: 18, color: estiloDestino?.acento ?? Colors.purple),
            label: Text(
              'Ver catálogo completo de destinos turísticos',
              style: TextStyle(
                color: estiloDestino?.acento ?? Colors.purple,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: estiloDestino?.acento ?? Colors.purple,
            ),
          ),
        ],
      );
    }

    return _btnLugar(
      label: 'Destino',
      value: _destino?.label,
      estilo: estiloDestino,
      onTap: () async {
        final _LugarSel? sel = await _buscarLugar('Elige el destino');
        if (!mounted || sel == null) return;
        setState(() => _destino = sel);
        _programarCalculoAutomatico();
      },
    );
  }

  bool get _mostrarResumenMulti =>
      _vistaResumenCotizada &&
      _tipoServicio != 'turismo' &&
      _precio > 0 &&
      !_cargando;

  void _abrirFormularioCompletoMulti() {
    setState(() => _vistaResumenCotizada = false);
  }

  Widget _tarjetaResumenMulti({
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color dividerSoft,
    required Color metodoPagoChipBg,
    required Color metodoPagoChipBorder,
  }) {
    final Color c = _colorServicio;
    final String tipoLabel =
        _tipoServicio == 'motor' ? 'Motor' : 'Normal · $_tipoVehiculo';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                c.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12),
                c.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.08 : 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.check_circle_rounded, color: c, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Listo para confirmar',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Ruta',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _origen?.label ?? '',
                style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
              ),
              ..._paradas.whereType<_LugarSel>().map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.arrow_downward, size: 16, color: c),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p.label,
                              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.flag_rounded, size: 18, color: c),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _destino?.label ?? '',
                        style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(tipoLabel, style: TextStyle(color: textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              Divider(color: dividerSoft, height: 1),
              const SizedBox(height: 12),
              Text(
                FormatosMoneda.km(_distKm),
                style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600),
              ),
              if (_peaje > 0) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Peaje: ${FormatosMoneda.rd(_peaje)}',
                  style: TextStyle(color: textMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'TOTAL A PAGAR',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  FormatosMoneda.rd(_precio),
                  style: TextStyle(
                    color: c,
                    fontSize: 50,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(Icons.payments_outlined, size: 18, color: textSecondary),
                  const SizedBox(width: 8),
                  Text('Pago:', style: TextStyle(color: textMuted, fontSize: 13)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: metodoPagoChipBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: metodoPagoChipBorder),
                    ),
                    child: Text(
                      _metodoPago,
                      style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirmar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Confirmar viaje',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A1A1A)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _abrirFormularioCompletoMulti,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dividerSoft),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.edit_location_alt_rounded, color: c, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Cambiar paradas u opciones',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Vuelve al formulario completo: origen, paradas, tipo y pago',
                          style: TextStyle(color: textMuted, fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded, color: textMuted, size: 28),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = isDark ? const Color(0xFF49F18B) : const Color(0xFF0F9D58);
    final List<Color> badgeGradient = isDark
        ? const [Color(0xFF15231A), Color(0xFF102016)]
        : const [Color(0xFFE8F7EE), Color(0xFFDDF3E7)];
    final Color badgeText = isDark ? accent : const Color(0xFF0B6B3A);
    final DateFormat f = DateFormat('EEE d MMM • HH:mm', 'es');
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary = isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
    final Color payLinkColor = isDark ? Colors.green.shade300 : const Color(0xFF0F9D58);
    final Color metodoPagoChipBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEFF1F5);
    final Color metodoPagoChipBorder = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color dividerSoft = isDark ? Colors.white24 : const Color(0xFFE4E7EC);
    final Color ddBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    final _EstiloRutaCampo estiloOrigen = _EstiloRutaCampo(
      acento: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
      fondo: isDark ? const Color(0xFF0F2D2A) : const Color(0xFFECFDF5),
      borde: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF14B8A6),
      icono: Icons.trip_origin_rounded,
    );
    final _EstiloRutaCampo estiloParada = _EstiloRutaCampo(
      acento: isDark ? const Color(0xFFFBBF24) : const Color(0xFFC2410C),
      fondo: isDark ? const Color(0xFF3A280A) : const Color(0xFFFFF7ED),
      borde: isDark ? const Color(0xFFF59E0B) : const Color(0xFFFB923C),
      icono: Icons.add_location_alt_rounded,
    );
    final _EstiloRutaCampo estiloDestino = _EstiloRutaCampo(
      acento: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF6B21A8),
      fondo: isDark ? const Color(0xFF2E1065) : const Color(0xFFFAF5FF),
      borde: isDark ? const Color(0xFFA78BFA) : const Color(0xFFA855F7),
      icono: Icons.flag_rounded,
    );

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFE8EAED),
      appBar: const RaiAppBar(
        title: 'Múltiples paradas',
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (_mostrarResumenMulti)
                _tarjetaResumenMulti(
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textMuted: textMuted,
                  dividerSoft: dividerSoft,
                  metodoPagoChipBg: metodoPagoChipBg,
                  metodoPagoChipBorder: metodoPagoChipBorder,
                ),
              if (!_mostrarResumenMulti) ...<Widget>[
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Tu recorrido',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Origen → paradas (opcional) → destino final',
                      style: TextStyle(color: textMuted, fontSize: 12.5, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    _tituloSeccionRuta(
                      estilo: estiloOrigen,
                      titulo: 'ORIGEN',
                      ayuda: 'Desde dónde sale el viaje',
                      textoAyuda: textMuted,
                    ),
                    _btnLugar(
                      label: 'Punto de partida',
                      value: _origen?.label,
                      estilo: estiloOrigen,
                      onTap: () async {
                        final _LugarSel? sel = await _buscarLugar('Elige el origen');
                        if (!mounted || sel == null) return;
                        setState(() => _origen = sel);
                        _programarCalculoAutomatico();
                      },
                    ),
                    _conectorRuta(estiloOrigen),
                    _tituloSeccionRuta(
                      estilo: estiloParada,
                      titulo: 'PARADAS INTERMEDIAS',
                      ayuda: 'Paradas en el camino (hasta 3). Puedes dejar vacías.',
                      textoAyuda: textMuted,
                    ),
                    ..._paradas.asMap().entries.map((MapEntry<int, _LugarSel?> e) {
                      final int i = e.key;
                      final _LugarSel? val = e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: _btnLugar(
                                label: 'Parada ${i + 1}',
                                value: val?.label,
                                estilo: estiloParada,
                                onTap: () async {
                                  final _LugarSel? sel = await _buscarLugar('Elige la parada ${i + 1}');
                                  if (!mounted) return;
                                  setState(() => _paradas[i] = sel);
                                  _programarCalculoAutomatico();
                                },
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Quitar parada',
                              onPressed: () {
                                setState(() {
                                  if (_paradas.length > 1) {
                                    _paradas.removeAt(i);
                                  } else {
                                    _paradas[i] = null;
                                  }
                                });
                                _programarCalculoAutomatico();
                              },
                              icon: Icon(Icons.remove_circle_outline_rounded, color: estiloParada.acento),
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _paradas.length < 3
                            ? () {
                                setState(() => _paradas.add(null));
                                _programarCalculoAutomatico();
                              }
                            : null,
                        icon: Icon(Icons.add_circle_outline_rounded, color: estiloParada.acento),
                        label: Text(
                          'Agregar parada',
                          style: TextStyle(
                            color: estiloParada.acento,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: TextButton.styleFrom(foregroundColor: estiloParada.acento),
                      ),
                    ),
                    _conectorRuta(estiloParada),
                    _tituloSeccionRuta(
                      estilo: estiloDestino,
                      titulo: 'DESTINO FINAL',
                      ayuda: 'Última parada del viaje',
                      textoAyuda: textMuted,
                    ),
                    _buildDestinoSection(estiloDestino: estiloDestino),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: badgeGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: accent, width: 1.6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded, color: badgeText, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Pide ahora',
                                style: TextStyle(
                                  color: badgeText,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text('Tipo:', style: TextStyle(color: textSecondary)),
                        const SizedBox(width: 10),
                        DropdownButton<String>(
                          value: _tipoServicio,
                          dropdownColor: ddBg,
                          style: TextStyle(color: textPrimary, fontSize: 16),
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(value: 'normal', child: Text('Normal', style: TextStyle(color: textPrimary))),
                            DropdownMenuItem<String>(value: 'motor', child: Text('Motor', style: TextStyle(color: textPrimary))),
                            DropdownMenuItem<String>(value: 'turismo', child: Text('Turismo', style: TextStyle(color: textPrimary))),
                          ],
                          onChanged: (String? v) {
                            setState(() {
                              _tipoServicio = v ?? 'normal';
                              _esAhora = true; // Múltiples paradas solo en modo ahora.
                              if (_tipoServicio == 'normal') {
                                _tipoVehiculo = 'Carro';
                              } else if (_tipoServicio == 'turismo') {
                                _tipoVehiculoTurismo = 'carro';
                              }
                            });
                            _programarCalculoAutomatico();
                          },
                        ),
                      ],
                    ),
                    if (_tipoServicio != 'motor') ...[
                      const SizedBox(height: 8),
                      if (_tipoServicio == 'normal')
                        Row(
                          children: [
                            Icon(Icons.directions_car, color: textSecondary, size: 20),
                            const SizedBox(width: 10),
                            Text('Vehículo:', style: TextStyle(color: textSecondary)),
                            const Spacer(),
                            DropdownButton<String>(
                              value: _tipoVehiculo,
                              dropdownColor: ddBg,
                              underline: const SizedBox(),
                              style: TextStyle(color: textPrimary, fontSize: 16),
                              items: ['Carro', 'Jeepeta', 'Minibús', 'Minivan', 'AutobusGuagua']
                                  .map((e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e, style: TextStyle(color: textPrimary)),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                setState(() => _tipoVehiculo = v ?? 'Carro');
                                _programarCalculoAutomatico();
                              },
                            ),
                          ],
                        ),
                      if (_tipoServicio == 'turismo')
                        Row(
                          children: [
                            Icon(Icons.beach_access, color: textSecondary, size: 20),
                            const SizedBox(width: 10),
                            Text('Vehículo turismo:', style: TextStyle(color: textSecondary)),
                            const Spacer(),
                            DropdownButton<String>(
                              value: _tipoVehiculoTurismo,
                              dropdownColor: ddBg,
                              underline: const SizedBox(),
                              style: TextStyle(color: textPrimary, fontSize: 16),
                              items: [
                                DropdownMenuItem(value: 'carro', child: Text('Carro', style: TextStyle(color: textPrimary))),
                                DropdownMenuItem(value: 'jeepeta', child: Text('Jeepeta', style: TextStyle(color: textPrimary))),
                                DropdownMenuItem(value: 'minivan', child: Text('Minivan', style: TextStyle(color: textPrimary))),
                                DropdownMenuItem(value: 'bus', child: Text('Bus', style: TextStyle(color: textPrimary))),
                              ],
                              onChanged: (v) {
                                setState(() => _tipoVehiculoTurismo = v);
                                _programarCalculoAutomatico();
                              },
                            ),
                          ],
                        ),
                    ],
                    if (!_esAhora) ...<Widget>[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _seleccionarFechaHora,
                        icon: Icon(Icons.calendar_today, color: payLinkColor),
                        label: Text(f.format(_fechaHora), style: TextStyle(color: payLinkColor, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _card(
                      child: Row(
                        children: [
                          Icon(Icons.credit_card_outlined, color: textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _elegirMetodoPago,
                              icon: Icon(Icons.account_balance_wallet_outlined, color: payLinkColor),
                              label: Text(
                                'Elegir método de pago',
                                style: TextStyle(color: payLinkColor, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: metodoPagoChipBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: metodoPagoChipBorder),
                            ),
                            child: Text(
                              _metodoPago,
                              style: TextStyle(color: textSecondary, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_precio > 0 && !_cargando) ...<Widget>[
                const SizedBox(height: 16),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _colorServicio.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _colorServicio, width: 2),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'DISTANCIA TOTAL',
                        style: TextStyle(
                          color: _colorServicio,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        FormatosMoneda.km(_distKm),
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(color: dividerSoft),
                      const SizedBox(height: 12),
                      Text(
                        'TOTAL',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        FormatosMoneda.rd(_precio),
                        style: TextStyle(
                          color: _colorServicio,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (_peaje > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Incluye peaje: ${FormatosMoneda.rd(_peaje)}',
                            style: TextStyle(color: textMuted, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _confirmar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _colorServicio,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '✅ CONFIRMAR VIAJE',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_cargando)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: isDark ? Colors.greenAccent : const Color(0xFF0F9D58),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_cargando && _mensajeCarga.isNotEmpty)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  color: isDark ? Colors.grey[900] : Colors.white,
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircularProgressIndicator(
                          color: isDark ? Colors.greenAccent : const Color(0xFF0F9D58),
                        ),
                        const SizedBox(height: 16),
                        Text(_mensajeCarga, style: TextStyle(color: textPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tituloSeccionRuta({
    required _EstiloRutaCampo estilo,
    required String titulo,
    required String ayuda,
    required Color textoAyuda,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: estilo.acento.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: estilo.borde.withValues(alpha: 0.55), width: 1.2),
            ),
            child: Icon(estilo.icono, size: 22, color: estilo.acento),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  titulo,
                  style: TextStyle(
                    color: estilo.acento,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ayuda,
                  style: TextStyle(color: textoAyuda, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _conectorRuta(_EstiloRutaCampo estilo) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: estilo.acento.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white24 : const Color(0xFFD0D5DD)),
      ),
      child: child,
    );
  }

  Widget _btnLugar({
    required String label,
    String? value,
    required VoidCallback onTap,
    _EstiloRutaCampo? estilo,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color secondary = isDark ? Colors.white70 : const Color(0xFF475467);
    final Color muted = isDark ? Colors.white54 : const Color(0xFF667085);
    final Color primary = isDark ? Colors.white : const Color(0xFF101828);
    final Color fillDefault = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final Color borderDefault = isDark ? Colors.white24 : const Color(0xFFD0D5DD);

    final Color fill = estilo?.fondo ?? fillDefault;
    final Color border = estilo?.borde ?? borderDefault;
    final Color labelColor = estilo?.acento ?? secondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: estilo != null ? 1.6 : 1),
            boxShadow: estilo != null
                ? <BoxShadow>[
                    BoxShadow(
                      color: estilo.acento.withValues(alpha: isDark ? 0.12 : 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (estilo != null) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(estilo.icono, size: 22, color: estilo.acento),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        color: labelColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value?.isEmpty ?? true ? 'Toca para buscar en el mapa…' : value!,
                      style: TextStyle(
                        color: value?.isEmpty ?? true ? muted : primary,
                        fontSize: 15,
                        fontWeight: value?.isEmpty ?? true ? FontWeight.w500 : FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class DestinoSeleccionado {
  final TurismoLugar lugar;
  final String tipoVehiculo;
  final int pasajeros;
  
  DestinoSeleccionado({
    required this.lugar,
    required this.tipoVehiculo,
    required this.pasajeros,
  });
}

// ---------- BottomSheet de búsqueda ----------
class _ScoredPrediction {
  final PlacePrediction prediction;
  final int score;

  const _ScoredPrediction(this.prediction, this.score);
}

class _BuscarLugarSheet extends StatefulWidget {
  final String titulo;
  const _BuscarLugarSheet({required this.titulo});

  @override
  State<_BuscarLugarSheet> createState() => _BuscarLugarSheetState();
}

class _BuscarLugarSheetState extends State<_BuscarLugarSheet> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _deb;
  bool _loading = false;
  List<PlacePrediction> _preds = const <PlacePrediction>[];
  List<Map<String, String>> _sugerenciasDestacadas = [];

  // Evita que respuestas de búsquedas anteriores "pisen" el estado actual
  // cuando el usuario escribe rápido.
  int _autocompleteSeq = 0;

  final PlacesService _places = PlacesService(
    app_keys.kGooglePlacesApiKey,
    language: 'es',
    components: const <String>['country:do'],
  );

  @override
  void initState() {
    super.initState();
    _cargarSugerenciasDestacadas();
  }

  @override
  void dispose() {
    _deb?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _cargarSugerenciasDestacadas() {
    final sugerencias = [
      'Aeropuerto Internacional Las Américas (SDQ)',
      'Aeropuerto Internacional de Punta Cana (PUJ)',
      'Aeropuerto Internacional del Cibao (STI)',
      'Aeropuerto Internacional Gregorio Luperón (POP)',
      'Aeropuerto Internacional La Romana (LRM)',
      'Bávaro, Punta Cana',
      'Zona Colonial, Santo Domingo',
      'Playa Macao, Punta Cana',
      'Cabo Engaño, La Altagracia',
      'Samaná, Santa Bárbara de Samaná',
      'Puerto Plata, República Dominicana',
      'Jarabacoa, La Vega',
      'Constanza, La Vega',
      'Bayahíbe, La Altagracia',
      'Las Terrenas, Samaná',
      'Sosúa, Puerto Plata',
      'Cabarete, Puerto Plata',
      'Pico Duarte',
      'Parque Nacional Los Haitises',
      'Isla Saona',
      'Isla Catalina',
      'Monumento de Santiago',
      'Acuario Nacional, Santo Domingo',
      'Teleférico de Puerto Plata',
    ];
    
    _sugerenciasDestacadas = sugerencias.map((s) => {
      'id': 'sug_${s.hashCode}',
      'text': s,
    }).toList();
    
    setState(() {});
  }

  String _getPlaceDescription(PlacePrediction p) {
    try {
      final fullDesc = (p as dynamic).fullDescription;
      if (fullDesc != null && fullDesc.isNotEmpty) return fullDesc;
    } catch (_) {}
    
    try {
      final desc = (p as dynamic).description;
      if (desc != null && desc.isNotEmpty) return desc;
    } catch (_) {}
    
    try {
      final mainText = (p as dynamic).mainText;
      if (mainText != null && mainText.isNotEmpty) return mainText;
    } catch (_) {}
    
    try {
      return p.toString();
    } catch (_) {}
    
    return 'Lugar seleccionado';
  }

  String _stripAccents(String s) {
    try {
      // En esta app usamos un "strip" básico para mejorar ranking sin depender
      // de métodos no disponibles (normalize no existe en tu entorno).
      final v = s.toLowerCase().trim();
      return v
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ñ', 'n')
          .replaceAll('ü', 'u')
          .replaceAll('Á', 'a')
          .replaceAll('É', 'e')
          .replaceAll('Í', 'i')
          .replaceAll('Ó', 'o')
          .replaceAll('Ú', 'u')
          .replaceAll('Ñ', 'n')
          .replaceAll('Ü', 'u');
    } catch (_) {
      return s.toLowerCase().trim();
    }
  }

  List<PlacePrediction> _rankPredictions(List<PlacePrediction> preds, String q) {
    final nq = _stripAccents(q);
    if (nq.isEmpty) return preds;

    // Score simple basado en coincidencias con el texto del usuario.
    final scored = <_ScoredPrediction>[];
    for (final p in preds) {
      final primary = _stripAccents(p.primary);
      final secondary = _stripAccents(p.secondary ?? '');

      int score = 0;
      if (primary.startsWith(nq)) score += 120;
      if (secondary.isNotEmpty && secondary.contains(nq)) score += 40;
      if (primary.contains(nq)) score += 20;

      scored.add(_ScoredPrediction(p, score));
    }

    scored.sort((a, b) {
      // Orden descendente por score (si empatan, se mantiene orden relativo).
      final d = b.score.compareTo(a.score);
      return d != 0 ? d : 0;
    });

    return scored.map((e) => e.prediction).toList(growable: false);
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      final String q = v.trim();
      if (q.isEmpty) {
        setState(() => _preds = const <PlacePrediction>[]);
        return;
      }

      final int seq = ++_autocompleteSeq;
      setState(() => _loading = true);
      try {
        final List<PlacePrediction> r = await _places.autocomplete(q);
        if (!mounted || seq != _autocompleteSeq) return;

        // Si el usuario cambió el texto mientras llegaba la respuesta,
        // no actualizamos la lista (evita "flicker" y resultados incorrectos).
        if (_ctrl.text.trim() != q) return;

        setState(() => _preds = _rankPredictions(r, q));
      } catch (e) {
        if (!mounted || seq != _autocompleteSeq) return;
        if (_ctrl.text.trim() != q) return;
        setState(() => _preds = const <PlacePrediction>[]);
      } finally {
        if (mounted && seq == _autocompleteSeq && _ctrl.text.trim() == q) {
          setState(() => _loading = false);
        }
      }
    });
  }

  Future<void> _selectSugerencia(Map<String, String> sugerencia) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await locationFromAddress(sugerencia['text']!);
      if (results.isNotEmpty && mounted) {
        Navigator.pop(
          context,
          _LugarSel(
            label: sugerencia['text']!,
            lat: results.first.latitude,
            lon: results.first.longitude,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo ubicar este destino')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ubicando destino: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPlace(PlacePrediction p) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final PlaceDetails? det = await _places.details(p.placeId);
      if (!mounted || det == null) return;
      Navigator.pop(
        context,
        _LugarSel(
          label: det.address,
          lat: det.latLng.latitude,
          lon: det.latLng.longitude,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDestino = widget.titulo.contains('Destino');
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final sh = mq.size.height;
    final pad = mq.padding;
    // Altura del panel: se reduce cuando el teclado está abierto para que la lista siga siendo scrollable arriba del teclado.
    final panelH = math.min(
      sh * 0.62,
      sh - kb - pad.top - pad.bottom - 12,
    ).clamp(260.0, sh);

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: kb),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: panelH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.titulo,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white),
                  scrollPadding: EdgeInsets.only(bottom: math.max(200.0, sh * 0.28)),
                  keyboardType: TextInputType.streetAddress,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: isDestino
                        ? 'Busca destinos turísticos...'
                        : 'Escribe dirección o lugar…',
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54),
                            onPressed: () {
                              _ctrl.clear();
                              _onChanged('');
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() {});
                    _onChanged(v);
                  },
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount:
                        _ctrl.text.isEmpty ? _sugerenciasDestacadas.length : _preds.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (_, int i) {
                      if (_ctrl.text.isEmpty) {
                        final sugerencia = _sugerenciasDestacadas[i];
                        return ListTile(
                          leading: const Icon(Icons.star, color: Colors.amber, size: 20),
                          title: Text(
                            sugerencia['text']!,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSugerencia(sugerencia),
                        );
                      } else {
                        final PlacePrediction p = _preds[i];
                        final String displayText = _getPlaceDescription(p);
                        return ListTile(
                          leading: const Icon(Icons.location_on, color: Colors.greenAccent, size: 20),
                          title: Text(
                            displayText,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectPlace(p),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}