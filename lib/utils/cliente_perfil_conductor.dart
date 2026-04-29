import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Perfil del pasajero para el taxista (estilo apps tipo inDrive): primera vez, frecuente, fijo, premium.
class ClientePerfilConductorVista {
  const ClientePerfilConductorVista({
    required this.viajesCompletados,
    required this.codigoNivel,
    required this.tituloPerfil,
    required this.lineaViajes,
    required this.detalleConductor,
  });

  final int viajesCompletados;

  /// `nuevo` | `primeros_viajes` | `frecuente` | `habitual` | `vip`
  final String codigoNivel;

  /// Titular grande (ej. «Primera vez en RAI», «Cliente fijo»).
  final String tituloPerfil;

  /// Línea con conteo (ej. «12 viajes completados en RAI»).
  final String lineaViajes;

  /// Texto largo para tooltip o segunda línea.
  final String detalleConductor;

  bool get esPrimeraVez => codigoNivel == 'nuevo';
  bool get esPremium => codigoNivel == 'vip';
  bool get esClienteFijo => codigoNivel == 'habitual' || codigoNivel == 'vip';

  static ClientePerfilConductorVista fromUsuarioDoc(
    DocumentSnapshot<Map<String, dynamic>>? snap,
  ) {
    final Map<String, dynamic>? m = snap?.data();
    final int n = m == null ? 0 : _intSeguro(m['clienteViajesCompletados']);
    final String codigoServidor =
        (m?['clienteNivelConductor'] ?? '').toString().trim().toLowerCase();
    final String codigo = _normalizarCodigo(codigoServidor, n);

    final String serverTitulo =
        (m?['clienteNivelConductorCorta'] ?? '').toString().trim();
    final String serverDetalle =
        (m?['clienteNivelConductorEtiqueta'] ?? '').toString().trim();

    final String titulo =
        serverTitulo.isNotEmpty ? serverTitulo : _tituloLocal(codigo);
    final String linea = _lineaViajesLocal(n);
    final String detalle =
        serverDetalle.isNotEmpty ? serverDetalle : _detalleLocal(n, codigo);

    return ClientePerfilConductorVista(
      viajesCompletados: n,
      codigoNivel: codigo,
      tituloPerfil: titulo,
      lineaViajes: linea,
      detalleConductor: detalle,
    );
  }

  static String _normalizarCodigo(String servidor, int n) {
    const validos = {
      'nuevo',
      'primeros_viajes',
      'frecuente',
      'habitual',
      'vip',
    };
    if (servidor.isNotEmpty && validos.contains(servidor)) return servidor;
    if (n <= 0) return 'nuevo';
    if (n <= 2) return 'primeros_viajes';
    if (n <= 14) return 'frecuente';
    if (n <= 39) return 'habitual';
    return 'vip';
  }

  static int _intSeguro(dynamic v) {
    if (v is int) return v < 0 ? 0 : v;
    if (v is num) return v.toInt().clamp(0, 999999);
    return 0;
  }

  static String _tituloLocal(String codigo) {
    switch (codigo) {
      case 'nuevo':
        return 'Primera vez en RAI';
      case 'primeros_viajes':
        return 'Pocos viajes en la app';
      case 'frecuente':
        return 'Cliente frecuente';
      case 'habitual':
        return 'Cliente fijo';
      case 'vip':
        return 'Cliente premium';
      default:
        return 'Pasajero RAI';
    }
  }

  static String _lineaViajesLocal(int n) {
    if (n <= 0) {
      return 'Sin viajes completados registrados — puede ser su primer servicio';
    }
    if (n == 1) return '1 viaje completado en RAI';
    return '$n viajes completados en RAI';
  }

  static String _detalleLocal(int n, String codigo) {
    switch (codigo) {
      case 'nuevo':
        return 'Sin historial cerrado en la app. Conducí como si fuera su primera experiencia con RAI.';
      case 'primeros_viajes':
        return 'Todavía conoce el servicio; un buen trato ayuda a que vuelva.';
      case 'frecuente':
        return 'Ya usa RAI con regularidad; valorá la puntualidad y el trato.';
      case 'habitual':
        return 'Cliente fijo de la plataforma — suele saber cómo funciona el flujo.';
      default:
        return 'Usuario muy activo en RAI — trato premium recomendado.';
    }
  }

  /// Acento visual tipo inDrive (sobre fondos oscuros).
  Color get colorAcento {
    switch (codigoNivel) {
      case 'nuevo':
        return const Color(0xFFFFB74D);
      case 'primeros_viajes':
        return const Color(0xFF4FC3F7);
      case 'frecuente':
        return const Color(0xFF69F0AE);
      case 'habitual':
        return const Color(0xFFFFD54F);
      case 'vip':
        return const Color(0xFFE040FB);
      default:
        return const Color(0xFFB0BEC5);
    }
  }

  IconData get iconoNivel {
    switch (codigoNivel) {
      case 'nuevo':
        return Icons.waving_hand_rounded;
      case 'primeros_viajes':
        return Icons.rocket_launch_outlined;
      case 'frecuente':
        return Icons.trending_up_rounded;
      case 'habitual':
        return Icons.loyalty_rounded;
      case 'vip':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.person_rounded;
    }
  }
}
