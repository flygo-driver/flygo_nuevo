import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Estado del perfil/registro del cliente para el asistente RAI (solo lectura).
class RaiPerfilClienteEstado {
  const RaiPerfilClienteEstado({
    required this.registroMarcadoCompleto,
    required this.tieneNombre,
    required this.tieneTelefono,
    required this.tieneFoto,
    required this.faltantes,
    required this.recomendados,
  });

  final bool registroMarcadoCompleto;
  final bool tieneNombre;
  final bool tieneTelefono;
  final bool tieneFoto;
  final List<String> faltantes;
  final List<String> recomendados;

  bool get perfilListo =>
      faltantes.isEmpty && registroMarcadoCompleto;

  bool get hayAlgoPendiente => faltantes.isNotEmpty || recomendados.isNotEmpty;

  String get resumenParaAsistente {
    if (perfilListo && !recomendados.contains('foto de perfil')) {
      return 'Perfil de cliente completo (nombre y teléfono).';
    }
    final buf = StringBuffer();
    if (faltantes.isNotEmpty) {
      buf.write('Falta completar: ${faltantes.join(', ')}.');
    } else if (!registroMarcadoCompleto) {
      buf.write('El registro aún no está marcado como completo.');
    } else {
      buf.write('Perfil básico OK.');
    }
    if (recomendados.isNotEmpty) {
      buf.write(' Recomendado (opcional): ${recomendados.join(', ')}.');
    }
    buf.write(
      ' Nota: puedes pedir viajes sin foto; nombre y teléfono ayudan al conductor.',
    );
    return buf.toString().trim();
  }

  String get mensajeAmigable {
    if (perfilListo && recomendados.isEmpty) {
      return 'Tu perfil está completo. Nombre y teléfono listos.';
    }
    if (faltantes.isEmpty && recomendados.isNotEmpty) {
      return 'Tu registro básico está bien. Opcional: ${recomendados.join(' y ')}.';
    }
    final lista = faltantes.map(_etiquetaHumana).join('\n• ');
    return 'Te falta completar:\n• $lista\n\n'
        'Ve a Cuenta → Configuración de perfil. '
        'Puedes seguir pidiendo viajes mientras tanto.';
  }

  static String _etiquetaHumana(String id) {
    switch (id) {
      case 'nombre':
        return 'Nombre (mínimo 2 letras)';
      case 'telefono':
        return 'Teléfono (mínimo 7 dígitos)';
      default:
        return id;
    }
  }

  /// Lee Firestore `usuarios/{uid}` — no escribe nada.
  static Future<RaiPerfilClienteEstado?> cargarActual() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final data = snap.data();
      if (data == null) {
        return const RaiPerfilClienteEstado(
          registroMarcadoCompleto: false,
          tieneNombre: false,
          tieneTelefono: false,
          tieneFoto: false,
          faltantes: ['nombre', 'telefono'],
          recomendados: ['foto de perfil'],
        );
      }

      final nombre = (data['nombre'] as String?)?.trim() ?? '';
      final telefono =
          ((data['telefono'] as String?) ?? '').replaceAll(RegExp(r'\s'), '');
      final foto = (data['fotoUrl'] as String?)?.trim() ?? '';
      final registroCompleto = data['registroClienteCompleto'] == true;

      final faltantes = <String>[];
      if (nombre.length < 2) faltantes.add('nombre');
      if (telefono.length < 7) faltantes.add('telefono');

      final recomendados = <String>[];
      if (foto.isEmpty) recomendados.add('foto de perfil');

      return RaiPerfilClienteEstado(
        registroMarcadoCompleto: registroCompleto,
        tieneNombre: nombre.length >= 2,
        tieneTelefono: telefono.length >= 7,
        tieneFoto: foto.isNotEmpty,
        faltantes: faltantes,
        recomendados: recomendados,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toPayload() => {
        'registroCompleto': registroMarcadoCompleto,
        'tieneNombre': tieneNombre,
        'tieneTelefono': tieneTelefono,
        'tieneFoto': tieneFoto,
        'faltantes': faltantes,
        'recomendados': recomendados,
        'resumen': resumenParaAsistente,
      };
}
