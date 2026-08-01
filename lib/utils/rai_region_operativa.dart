import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Partición nacional RD para `drivers_location` (escala millones sin mezclar ciudades).
abstract final class RaiRegionOperativa {
  RaiRegionOperativa._();

  /// Bounding box aproximado de República Dominicana (incl. islas adyacentes).
  static const double rdLatMin = 17.47;
  static const double rdLatMax = 19.98;
  static const double rdLonMin = -72.05;
  static const double rdLonMax = -68.32;

  /// Centro geográfico aproximado (fallback mapa sin GPS).
  static const LatLng centroNacional = LatLng(18.735, -70.162);

  /// Gran Santo Domingo + DN + Santo Domingo Este/Oeste.
  static const String metro = 'rd_metro';

  /// Santiago de los Caballeros y área inmediata.
  static const String santiago = 'rd_santiago';

  /// Costa norte (Puerto Plata, Sosúa, Cabarete, etc.).
  static const String norte = 'rd_norte';

  /// Este / turismo (Punta Cana, Bávaro, Higüey, La Romana).
  static const String este = 'rd_este';

  /// Península de Samaná, Nagua, Sánchez.
  static const String samana = 'rd_samana';

  /// San Pedro de Macorís, Hato Mayor, El Seibo.
  static const String sanPedro = 'rd_san_pedro';

  /// Noroeste (Montecristi, Dajabón, Mao, Santiago Rodríguez).
  static const String noroeste = 'rd_noroeste';

  /// Sur (Barahona, Azua, San Juan de la Maguana, Pedernales).
  static const String sur = 'rd_sur';

  /// Cibao interior (La Vega, Moca, San Francisco de Macorís, Bonao).
  static const String cibao = 'rd_cibao';

  /// Valdesia / sur metropolitano (San Cristóbal, Baní, Nizao).
  static const String valdesia = 'rd_valdesia';

  /// Resto del territorio nacional (pueblos sin región dedicada).
  static const String otros = 'rd_otros';

  static const List<String> todas = <String>[
    metro,
    santiago,
    norte,
    este,
    samana,
    sanPedro,
    noroeste,
    sur,
    cibao,
    valdesia,
    otros,
  ];

  /// ¿Coordenadas dentro del territorio RD?
  static bool enTerritorioRd(double latitude, double longitude) {
    if (!_coordsOk(latitude, longitude)) return false;
    return latitude >= rdLatMin &&
        latitude <= rdLatMax &&
        longitude >= rdLonMin &&
        longitude <= rdLonMax;
  }

  /// Etiqueta legible (UI / logs).
  static String etiqueta(String region) {
    switch (region) {
      case metro:
        return 'Gran Santo Domingo';
      case santiago:
        return 'Santiago';
      case norte:
        return 'Norte';
      case este:
        return 'Este';
      case samana:
        return 'Samaná';
      case sanPedro:
        return 'San Pedro';
      case noroeste:
        return 'Noroeste';
      case sur:
        return 'Sur';
      case cibao:
        return 'Cibao';
      case valdesia:
        return 'Valdesia';
      default:
        return 'República Dominicana';
    }
  }

  /// Resuelve región operativa desde coordenadas (zonas específicas primero).
  static String resolver(double latitude, double longitude) {
    if (!_coordsOk(latitude, longitude)) return otros;
    if (!enTerritorioRd(latitude, longitude)) return otros;

    // Este: Punta Cana → La Romana (costa este).
    if (longitude >= -68.72 &&
        latitude >= 18.12 &&
        latitude <= 19.35) {
      return este;
    }

    // Samaná y costa nordeste.
    if (latitude >= 19.05 &&
        latitude <= 19.55 &&
        longitude >= -69.95 &&
        longitude <= -69.15) {
      return samana;
    }

    // San Pedro, Hato Mayor, El Seibo.
    if (latitude >= 18.40 &&
        latitude <= 19.05 &&
        longitude >= -69.60 &&
        longitude <= -68.85) {
      return sanPedro;
    }

    // Gran Santo Domingo.
    if (latitude >= 18.35 &&
        latitude <= 18.68 &&
        longitude >= -70.12 &&
        longitude <= -69.62) {
      return metro;
    }

    // Valdesia: San Cristóbal, Baní, sur metropolitano.
    if (latitude >= 18.18 &&
        latitude <= 18.42 &&
        longitude >= -70.55 &&
        longitude <= -69.95) {
      return valdesia;
    }

    // Santiago ciudad y área inmediata.
    if (latitude >= 19.38 &&
        latitude <= 19.58 &&
        longitude >= -70.92 &&
        longitude <= -70.55) {
      return santiago;
    }

    // Noroeste fronterizo.
    if (latitude >= 19.35 &&
        latitude <= 19.95 &&
        longitude >= -72.05 &&
        longitude <= -71.15) {
      return noroeste;
    }

    // Costa norte (Puerto Plata, Cabarete…).
    if (latitude >= 19.50 &&
        latitude <= 19.95 &&
        longitude >= -71.25 &&
        longitude <= -70.35) {
      return norte;
    }

    // Sur y suroeste.
    if (latitude <= 18.28 &&
        longitude >= -72.05 &&
        longitude <= -68.90) {
      return sur;
    }

    // Cibao interior.
    if (latitude >= 18.75 &&
        latitude <= 19.45 &&
        longitude >= -71.15 &&
        longitude <= -70.15) {
      return cibao;
    }

    return otros;
  }

  static String? desdeDoc(Map<String, dynamic>? data) {
    final String raw = (data?['region'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    if (todas.contains(raw)) return raw;
    return null;
  }

  static String regionEfectiva(Map<String, dynamic>? data) {
    final String? guardada = desdeDoc(data);
    if (guardada != null) return guardada;
    final dynamic loc = data?['location'];
    if (loc is GeoPoint) {
      return resolver(loc.latitude, loc.longitude);
    }
    return otros;
  }

  static bool docEnRegion(
    Map<String, dynamic>? data,
    String regionCliente,
  ) {
    return regionEfectiva(data) == regionCliente;
  }

  static bool _coordsOk(double lat, double lon) =>
      lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180;
}
