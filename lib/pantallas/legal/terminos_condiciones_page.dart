import 'package:flutter/material.dart';

class TerminosCondicionesPage extends StatelessWidget {
  const TerminosCondicionesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Términos y Condiciones'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text('Términos y Condiciones de FlyGo',
              style: text.headlineSmall
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Última actualización: 05/11/2025',
              style: text.bodySmall?.copyWith(color: Colors.white54)),
          const SizedBox(height: 18),
          _h('1. Quiénes somos'),
          _p('FlyGo es una plataforma tecnológica operada por Open Ask Service, RNC 132011767 (en adelante, “FlyGo”, “nosotros”). '
              'FlyGo **no es** una empresa de transporte: prestamos un **servicio de intermediación** digital que conecta pasajeros con conductores independientes autorizados.'),
          _h('2. Aceptación'),
          _p('Al crear una cuenta, acceder o utilizar la aplicación, aceptas íntegramente estos Términos y nuestra Política de Privacidad. '
              'Si no estás de acuerdo, no debes usar la plataforma.'),
          _h('3. Elegibilidad y cuentas'),
          _b([
            'Ser mayor de edad conforme a la ley aplicable. Menores solo con autorización y acompañamiento de su representante legal.',
            'Proporcionar datos veraces y mantenerlos actualizados.',
            'No compartir credenciales ni permitir el uso de tu cuenta por terceros.',
          ]),
          _h('4. Alcance del servicio'),
          _p('FlyGo permite solicitar viajes **AHORA** o **PROGRAMADOS** (especialmente en aeropuertos, hoteles, zonas turísticas y traslados interurbanos). '
              'Los viajes los ejecutan **conductores independientes** habilitados tras verificación de documentos. FlyGo cobra al conductor una comisión (por defecto 20%) y ofrece herramientas de billetera y liquidación.'),
          _h('5. Conductores: requisitos y obligaciones'),
          _b([
            'Documentación vigente (licencia, matrícula/seguro, etc.).',
            'Vehículo en condiciones óptimas, limpio y seguro.',
            'Cumplir normas de tránsito y protocolos de servicio.',
            'Cooperar con verificaciones y controles de calidad.',
            'Instalar cámaras de seguridad internas cuando FlyGo lo exija conforme a la ley vigente.',
          ]),
          _h('6. Pasajeros: obligaciones'),
          _b([
            'Indicar origen/destino reales y respetar al conductor.',
            'No transportar objetos ilícitos o peligrosos.',
            'Cuidar el vehículo y la marca FlyGo.',
            'Reportar incidentes por los canales de soporte de la app.',
          ]),
          _h('7. Prohibiciones'),
          _b([
            'Usar la app para fines ilícitos, violentos o para causar daño.',
            'Acoso, agresiones o discriminación de cualquier tipo.',
            'Manipular tarifas, fraudes o suplantación de identidad.',
          ]),
          _h('8. Riesgos e imprevistos'),
          _p('La movilidad implica riesgos inherentes (tránsito, clima, terceros). FlyGo aplica medidas de seguridad, pero no puede eliminar totalmente los riesgos.'),
          _h('9. Responsabilidad y limitación'),
          _p('En la máxima medida permitida por la ley, FlyGo no es responsable por: '
              '(i) daños indirectos o lucro cesante; '
              '(ii) conductas de usuarios o conductores; '
              '(iii) fuerza mayor o hechos fuera de nuestro control. '
              'En todo caso, la responsabilidad total de FlyGo se limita al monto efectivamente pagado por el servicio objeto del reclamo.'),
          _h('10. Pagos, comisiones y billetera'),
          _b([
            'El pasajero paga el viaje conforme a las opciones habilitadas en la app.',
            'El conductor autoriza la retención de la comisión de FlyGo (por defecto 20%).',
            'FlyGo podrá requerir saldo mínimo operativo en la billetera del conductor.',
          ]),
          _h('11. Viajes programados y liberación'),
          _p('Los viajes programados se publican y liberan para aceptación en las ventanas indicadas por la app. '
              'Si el conductor no cumple las condiciones (disponibilidad, verificación, fondos, etc.), no podrá aceptar.'),
          _h('12. Menores de edad'),
          _p('Menores deben viajar acompañados o con autorización del representante legal. FlyGo podrá exigir documentación y cancelar solicitudes que impliquen riesgo.'),
          _h('13. Seguridad y cooperación con autoridades'),
          _p('FlyGo podrá conservar y, cuando la ley lo requiera, facilitar a las autoridades información pertinente (registros, ubicaciones, comunicaciones y, si aplica, grabaciones). '
              'Hechos delictivos serán denunciados.'),
          _h('14. Contenido, marca y licencia'),
          _p('FlyGo y sus logotipos son marcas protegidas. No adquieres derecho alguno sobre nuestra propiedad intelectual. '
              'Concedes a FlyGo una licencia no exclusiva para tratar los contenidos que subas estrictamente para operar el servicio.'),
          _h('15. Suspensión y terminación'),
          _p('Podemos suspender o cerrar cuentas por incumplimientos, riesgos de seguridad, fraude, daño a la marca o por requerimiento legal.'),
          _h('16. Modificaciones'),
          _p('Podemos actualizar estos Términos con aviso en la app o por canales oficiales. El uso continuado implica aceptación de las modificaciones.'),
          _h('17. Ley aplicable y jurisdicción'),
          _p('Estos términos se rigen por las leyes de la República Dominicana. Las controversias se someterán a los tribunales competentes de Santo Domingo, salvo norma imperativa en contrario.'),
          const SizedBox(height: 18),
          Text(
            'Operador: Open Ask Service, RNC 132011767\nContacto: soporte@flygo.do',
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
