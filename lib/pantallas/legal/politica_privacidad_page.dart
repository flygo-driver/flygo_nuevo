import 'package:flutter/material.dart';
import 'package:flygo_nuevo/legal/terms_data.dart' show kTermsContactEmail;

class PoliticaPrivacidadPage extends StatelessWidget {
  const PoliticaPrivacidadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Política de Privacidad'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text('Política de Privacidad de RAI DRIVER',
              style: text.headlineSmall
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Última actualización: 05/11/2025',
              style: text.bodySmall?.copyWith(color: Colors.white54)),
          const SizedBox(height: 18),
          _h('1. Responsable del tratamiento'),
          _p('Open ASK Service SRL, RNC 1320-11767 (“RAI DRIVER”, “nosotros”). Contacto: $kTermsContactEmail'),
          _h('2. Datos que tratamos'),
          _b([
            'Identificación y contacto: nombre, email, teléfono.',
            'Cuenta y verificación: documentos del conductor, validaciones.',
            'Ubicación: durante el uso del servicio para calcular rutas, mostrar cercanía y seguridad.',
            'Transaccionales: método de pago habilitado, historial de viajes, comisiones y liquidaciones.',
            'Técnicos: IP aproximada, dispositivo, versión de app, logs para seguridad y soporte.',
            'Comunicaciones in-app (chat/soporte) y, si se habilita, grabaciones de cámaras internas del vehículo conforme a la ley.',
          ]),
          _h('3. Finalidades'),
          _b([
            'Prestar el servicio de intermediación pasajero-conductor.',
            'Seguridad, prevención de fraude y control de calidad.',
            'Atención al usuario y soporte.',
            'Cumplimiento legal y solicitudes de autoridades.',
            'Estadísticas operativas y mejora de la plataforma.',
            'Notificaciones operativas y de seguridad (incluyendo timbres de viaje).',
          ]),
          _h('4. Base legal'),
          _b([
            'Ejecución del contrato (uso de la app).',
            'Interés legítimo (seguridad, prevención del fraude, mejora del servicio).',
            'Cumplimiento de obligaciones legales.',
            'Consentimiento para permisos específicos (por ejemplo, ubicación en segundo plano o notificaciones).',
          ]),
          _h('5. Conservación'),
          _p('Conservamos los datos el tiempo necesario para prestar el servicio, cumplir obligaciones legales y atender responsabilidades. '
              'Ciertos registros se conservan por periodos adicionales para seguridad y cooperación con autoridades.'),
          _h('6. Destinatarios y transferencias'),
          _b([
            'Proveedores tecnológicos que actúan por cuenta de RAI DRIVER (alojamiento, mensajería, pagos).',
            'Autoridades competentes cuando exista obligación legal o requerimiento válido.',
            'No vendemos datos personales.',
          ]),
          _h('7. Derechos del usuario'),
          _b([
            'Acceso, rectificación, actualización y eliminación cuando proceda.',
            'Oposición o limitación del tratamiento en casos previstos por la ley.',
            'Portabilidad en los supuestos aplicables.',
            'Canales: $kTermsContactEmail y la opción “Eliminar cuenta”.',
          ]),
          _h('8. Ubicación y permisos'),
          _p('La ubicación es necesaria para mostrar mapas, calcular rutas, ETA, asignar viajes y reforzar seguridad. '
              'Puedes gestionar permisos en los ajustes del dispositivo; deshabilitarlos puede impedir el funcionamiento de la app.'),
          _h('9. Seguridad'),
          _p('Aplicamos medidas técnicas y organizativas razonables para proteger la información (cifrado en tránsito, controles de acceso, registros de auditoría).'),
          _h('10. Menores'),
          _p('No dirigimos el servicio a menores sin autorización del representante legal. Podemos verificar y suspender cuentas que incumplan este requisito.'),
          _h('11. Cámaras a bordo (cuando se exijan)'),
          _p('Para protección de pasajeros y conductores, RAI DRIVER podrá exigir cámaras internas en el vehículo conforme a la legislación vigente. '
              'Las grabaciones se tratarán con fines de seguridad, control de calidad y cooperación con autoridades.'),
          _h('12. Cookies/SDKs'),
          _p('Podemos utilizar SDKs de analítica y mensajería para métricas de uso y diagnóstico de fallos. Puedes desactivar ciertas mediciones desde los ajustes del dispositivo.'),
          _h('13. Cambios a esta Política'),
          _p('Podremos actualizar esta Política con aviso en la app o canales oficiales. El uso continuado tras el aviso implica aceptación.'),
          const SizedBox(height: 18),
          Text(
            'Operador: Open ASK Service SRL, RNC 1320-11767\nContacto: $kTermsContactEmail',
            style: text.bodySmall?.copyWith(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  // ===== helpers de estilo =====
  static Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      );

  static Widget _p(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.35)),
      );

  static Widget _b(List<String> items) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ',
                            style:
                                TextStyle(color: Colors.white70, height: 1.35)),
                        Expanded(
                            child: Text(e,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.35))),
                      ],
                    ),
                  ))
              .toList(),
        ),
      );
}
