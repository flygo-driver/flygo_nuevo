import 'package:flutter/material.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

/// Mensaje naranja contextual para orientar taxista/cliente en viaje en curso.
/// Se oculta solo cuando el paso correspondiente ya se cumplió (botón tocado o estado avanzado).
class ViajeFlujoOrientacionBanner extends StatelessWidget {
  const ViajeFlujoOrientacionBanner({
    super.key,
    required this.mensaje,
  });

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.deepOrange.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.85)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.touch_app_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? viajeFlujoOrientacionMensajeTaxista({
  required String estadoBase,
  required bool navegacionPickupIniciada,
  required bool navegacionDestinoIniciada,
  required bool codigoVerificado,
  required bool esMultiparada,
  required bool multiparadaRutaCompleta,
  bool esCorporativo = false,
}) {
  if (EstadosViaje.esAceptado(estadoBase) ||
      EstadosViaje.esEnCaminoPickup(estadoBase)) {
    if (!navegacionPickupIniciada) {
      return esCorporativo
          ? 'Desliza la hoja y toca Waze/Maps para ir a la empresa (recogida del grupo).'
          : 'Desliza la hoja hacia arriba y toca «Navegar hacia el cliente».';
    }
    return esCorporativo
        ? 'En la empresa: toca «Cliente a bordo» y pide el código al encargado.'
        : 'Toca «Cliente a bordo» cuando el pasajero suba al vehículo.';
  }

  if (EstadosViaje.esAbordo(estadoBase)) {
    if (!codigoVerificado) {
      return esCorporativo
          ? 'Toca «Verificar e iniciar ruta» e ingresa el código del período (dicta el encargado).'
          : 'Toca «Verificar e iniciar ruta» e ingresa el PIN del cliente.';
    }
    if (!EstadosViaje.esEnCurso(estadoBase)) {
      return esCorporativo
          ? 'Toca «Iniciar ruta al destino» para empezar a dejar pasajeros.'
          : 'Toca «Iniciar ruta al destino» para comenzar el trayecto.';
    }
  }

  if (EstadosViaje.esEnCurso(estadoBase)) {
    if (esMultiparada && !multiparadaRutaCompleta) {
      if (!navegacionDestinoIniciada) {
        return esCorporativo
            ? 'Toca «Navegar a la parada» para cada pasajero en el orden de la ruta.'
            : 'Desliza la hoja y toca «Navegar a la parada» o «Navegar al destino final».';
      }
      return esCorporativo
          ? 'En cada parada: toca «Llegué — siguiente destino» al dejar al pasajero.'
          : 'Confirma cada parada con «Llegué — siguiente destino» antes de finalizar.';
    }
    if (!navegacionDestinoIniciada) {
      return esCorporativo
          ? 'Toca «Navegar al destino» para la dejada del pasajero.'
          : 'Desliza la hoja hacia arriba y toca «Navegar al destino».';
    }
    return 'Al llegar al destino, toca «Finalizar viaje».';
  }

  return null;
}

/// Paso 1: solo «Navegar hacia el cliente».
bool taxistaMostrarNavegarPickup(bool navegacionPickupIniciada) =>
    !navegacionPickupIniciada;

/// Paso 2: «Cliente a bordo» solo después de abrir navegación al pickup.
bool taxistaMostrarClienteAbordo(bool navegacionPickupIniciada) =>
    navegacionPickupIniciada;

/// En `en_curso`: «Finalizar» solo tras «Navegar al destino» (o multiparada completa).
bool taxistaMostrarFinalizarViaje({
  required bool navegacionDestinoIniciada,
  required bool esMultiparada,
  required bool multiparadaRutaCompleta,
}) {
  if (esMultiparada) return multiparadaRutaCompleta;
  return navegacionDestinoIniciada;
}

String? viajeFlujoOrientacionMensajeCliente({
  required String estadoBase,
  required bool codigoVerificado,
  required bool mostrarCodigoCliente,
  required bool mostrarNavDestino,
  required bool clienteNavDestinoUsado,
  required bool multiparadaActiva,
  required bool multiparadaCompleta,
  required int multiparadaLegHechos,
  required int clienteNavOrientacionLegDismissed,
  required bool tieneTaxista,
}) {
  if (!tieneTaxista) return null;

  if (EstadosViaje.esAceptado(estadoBase) ||
      EstadosViaje.esEnCaminoPickup(estadoBase)) {
    return 'Tu conductor va hacia ti. Al subir, él tocará «Cliente a bordo».';
  }

  if (EstadosViaje.esAbordo(estadoBase) &&
      !codigoVerificado &&
      mostrarCodigoCliente) {
    return 'Dicta el código de 6 dígitos a tu conductor para iniciar el viaje.';
  }

  if (multiparadaActiva &&
      !multiparadaCompleta &&
      multiparadaLegHechos > clienteNavOrientacionLegDismissed) {
    return 'Desliza la hoja y toca «Navegar a la parada» o «Navegar al destino final».';
  }

  if (mostrarNavDestino && !clienteNavDestinoUsado) {
    return 'Desliza la hoja y toca «Navegar al destino» si quieres abrir Maps o Waze.';
  }

  return null;
}
