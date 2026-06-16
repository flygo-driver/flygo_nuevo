import 'package:flygo_nuevo/servicios/rai_perfil_cliente_estado.dart';
import 'package:flygo_nuevo/utils/rai_destino_desde_voz.dart';

/// Respuesta del asistente RAI (nube Gemini o conocimiento local gratuito).
class RaiAsistenteRespuesta {  const RaiAsistenteRespuesta({
    required this.reply,
    this.addressQuery,
    this.addressQueries = const [],
    this.suggestedAction = RaiAsistenteAction.none,
    this.source = RaiAsistenteSource.local,
  });

  final String reply;
  final String? addressQuery;
  final List<String> addressQueries;
  final RaiAsistenteAction suggestedAction;
  final RaiAsistenteSource source;
}

enum RaiAsistenteSource { gemini, local, cloudFallback }

enum RaiAsistenteAction {
  none,
  openMotor,
  openTaxi,
  openTurismo,
  openSoporte,
  openMisViajes,
  openPerfil,
}

class RaiAsistenteMensaje {
  const RaiAsistenteMensaje({
    required this.role,
    required this.text,
    this.respuesta,
  });

  final String role; // user | assistant
  final String text;
  final RaiAsistenteRespuesta? respuesta;
}

/// Conocimiento local gratuito: responde sin API cuando no hay red o Gemini.
class RaiAsistenteKb {
  RaiAsistenteKb._();

  static RaiAsistenteRespuesta responder(
    String raw, {
    RaiPerfilClienteEstado? perfil,
  }) {
    final q = raw.toLowerCase().trim();
    if (q.isEmpty) {
      return const RaiAsistenteRespuesta(
        reply:
            'Hola, soy RAI 👋 Pregúntame cómo pedir un viaje, buscar una dirección difícil o cómo funciona la app.',
      );
    }

    final destinoVoz = RaiDestinoDesdeVoz.analizar(raw);
    if (destinoVoz.tieneDestinoParaBuscar) {
      final query = destinoVoz.consultaPlaces;
      return RaiAsistenteRespuesta(
        reply:
            'Entiendo que quieres ir a: «$query». '
            'Busco la dirección exacta en Google para cotizar bien.',
        addressQuery: query,
        addressQueries: [query, raw.trim()],
        suggestedAction: destinoVoz.preferMotor
            ? RaiAsistenteAction.openMotor
            : destinoVoz.preferTurismo
                ? RaiAsistenteAction.openTurismo
                : RaiAsistenteAction.openTaxi,
      );
    }

    if (destinoVoz.esDireccionDirecta) {
      final query = destinoVoz.consultaPlaces;
      return RaiAsistenteRespuesta(
        reply:
            'Voy a buscar «$query» en Google Places para fijar el destino con coordenadas.',
        addressQuery: query,
        addressQueries: [query],
        suggestedAction: RaiAsistenteAction.openTaxi,
      );
    }

    if (_match(q, [
      'como funciona',
      'cómo funciona',
      'que es rai',
      'qué es rai',
      'para que sirve',
      'para qué sirve',
    ])) {
      return const RaiAsistenteRespuesta(
        reply:
            'RAI Driver te conecta con conductores en RD 🚗\n\n'
            '1. Elige servicio (Taxi, Motor, Turismo o BOLA).\n'
            '2. Indica destino (origen = tu GPS en viajes «ahora»).\n'
            '3. Ves el precio y confirmas.\n'
            '4. Un conductor acepta y sigues el viaje en el mapa.\n\n'
            'Pagos: efectivo o transferencia al conductor.',
      );
    }

    if (_match(q, ['motor', 'moto', 'motocicleta'])) {
      return const RaiAsistenteRespuesta(
        reply:
            'Motor 🏍️: ideal para tráfico urbano. Solo eliges destino; '
            'tu ubicación GPS es el punto de salida. Te muestro el precio antes de confirmar.',
        suggestedAction: RaiAsistenteAction.openMotor,
      );
    }

    if (_match(q, ['turismo', 'excursion', 'excursión', 'playa', 'punta cana tour'])) {
      return const RaiAsistenteRespuesta(
        reply:
            'Turismo 🏝️: elige un destino del catálogo o escribe uno. '
            'Hay asignación automática con choferes aprobados; si no hay disponibles, soporte te ayuda.',
        suggestedAction: RaiAsistenteAction.openTurismo,
      );
    }

    if (_match(q, [
      'programar',
      'programado',
      'reservar',
      'agendar',
      'mañana',
      'manana',
    ])) {
      return const RaiAsistenteRespuesta(
        reply:
            'Viaje programado 📅: puedes elegir fecha, hora, origen y destino '
            'con anticipación. Entra en Taxi → Programar viaje.',
        suggestedAction: RaiAsistenteAction.openTaxi,
      );
    }

    if (_match(q, ['precio', 'tarifa', 'cuanto cuesta', 'cuánto cuesta', 'cobran'])) {
      return const RaiAsistenteRespuesta(
        reply:
            'El precio se calcula por distancia y tipo de vehículo antes de confirmar. '
            'Sin internet verás un estimado de referencia; para confirmar necesitas conexión.',
      );
    }

    if (_match(q, [
      'sin internet',
      'no tengo internet',
      'offline',
      'no hay wifi',
      'no hay datos',
    ])) {
      return const RaiAsistenteRespuesta(
        reply:
            'Sin internet puedes ver un precio estimado, pero no confirmar el viaje '
            'hasta que vuelva la conexión. Marca el destino en el mapa si el buscador no responde.',
      );
    }

    if (_match(q, [
      'pago',
      'efectivo',
      'transferencia',
      'tarjeta',
      'nequi',
    ])) {
      return const RaiAsistenteRespuesta(
        reply:
            'Pagos en RAI: efectivo o transferencia al conductor al finalizar. '
            'La app muestra el total acordado en la cotización.',
      );
    }

    if (_match(q, [
      'soporte',
      'ayuda humana',
      'reclamo',
      'problema',
      'queja',
      'no llego',
      'no llegó',
      'estafa',
      'emergencia',
    ])) {
      return const RaiAsistenteRespuesta(
        reply:
            'Para un caso urgente o reclamo, te conecto con soporte humano '
            '(correo, teléfono o WhatsApp). Cuéntame también aquí y te oriento.',
        suggestedAction: RaiAsistenteAction.openSoporte,
      );
    }

    if (_match(q, [
      'viaje en curso',
      'donde esta',
      'dónde está',
      'conductor',
      'historial',
      'mis viajes',
    ])) {
      return const RaiAsistenteRespuesta(
        reply:
            'Revisa «Mis viajes» para historial o el mapa en vivo si tienes un viaje activo.',
        suggestedAction: RaiAsistenteAction.openMisViajes,
      );
    }

    if (_match(q, ['bola', 'pueblo', 'interurbano'])) {
      return const RaiAsistenteRespuesta(
        reply:
            'BOLA pueblo a pueblo conecta rutas interurbanas compartidas. '
            'Desde Inicio elige BOLA y sigue los pasos del mapa.',
      );
    }

    // Palabras clave de dirección (sin patrón claro de frase)
    if (_match(q, [
      'direccion',
      'dirección',
      'donde queda',
      'dónde queda',
      'como llego',
      'cómo llego',
      'ir a ',
      'llevarme',
      'sector',
      'calle',
      'colmado',
      'aeropuerto',
      'sdq',
      'puj',
      'hotel',
      'quiero ir',
      'llevame',
      'llévame',
      'voy para',
      'voy a ',
    ])) {
      final query = RaiDestinoDesdeVoz.normalizarParaPlaces(raw) ?? raw.trim();
      return RaiAsistenteRespuesta(
        reply: query.isNotEmpty
            ? 'Entiendo que quieres ir a: «$query». '
                'Busco la dirección exacta en Google para cotizar bien.'
            : 'Descríbeme el lugar con sector, ciudad o referencia '
                '(ej. «Los Minas, cerca del malecón») y te ayudo a buscarlo.',
        addressQuery: query.isNotEmpty ? query : raw.trim(),
        addressQueries: query.isNotEmpty ? [query, raw.trim()] : [raw.trim()],
        suggestedAction: RaiAsistenteAction.openTaxi,
      );
    }

    if (_match(q, [
      'registro',
      'perfil',
      'completar',
      'documento',
      'documentos',
      'falta',
      'llenar',
      'datos',
      'nombre',
      'telefono',
      'teléfono',
      'foto',
    ])) {
      if (perfil != null && perfil.faltantes.isNotEmpty) {
        return RaiAsistenteRespuesta(
          reply: perfil.mensajeAmigable,
          suggestedAction: RaiAsistenteAction.openPerfil,
        );
      }
      if (perfil != null && perfil.recomendados.isNotEmpty) {
        return RaiAsistenteRespuesta(
          reply: perfil.mensajeAmigable,
          suggestedAction: RaiAsistenteAction.openPerfil,
        );
      }
      return const RaiAsistenteRespuesta(
        reply:
            'Tu perfil básico (nombre y teléfono) está completo. '
            'La foto es opcional pero ayuda al conductor a identificarte. '
            'Edita todo en Cuenta → Configuración de perfil.',
        suggestedAction: RaiAsistenteAction.openPerfil,
      );
    }

    return const RaiAsistenteRespuesta(
      reply:
          'Puedo ayudarte con:\n'
          '• Cómo funciona RAI\n'
          '• Buscar direcciones difíciles\n'
          '• Taxi, motor, turismo o viaje programado\n'
          '• Pagos y qué hacer sin internet\n\n'
          '¿Qué necesitas?',
    );
  }

  static bool _match(String q, List<String> keys) {
    for (final k in keys) {
      if (q.contains(k)) return true;
    }
    return false;
  }

  static String? normalizarBusquedaDireccionPublica(String raw) =>
      RaiDestinoDesdeVoz.normalizarParaPlaces(raw);

  static RaiAsistenteAction parseAction(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'open_motor':
        return RaiAsistenteAction.openMotor;
      case 'open_taxi':
        return RaiAsistenteAction.openTaxi;
      case 'open_turismo':
        return RaiAsistenteAction.openTurismo;
      case 'open_soporte':
        return RaiAsistenteAction.openSoporte;
      case 'open_mis_viajes':
        return RaiAsistenteAction.openMisViajes;
      case 'open_perfil':
        return RaiAsistenteAction.openPerfil;
      default:
        return RaiAsistenteAction.none;
    }
  }
}
