import 'package:flutter/material.dart';

import 'package:flygo_nuevo/widgets/rai_ubicacion_map_alert.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';

/// Cliente: delega en [RaiUbicacionMapAlert].
class RaiUbicacionClienteMapAlert extends StatelessWidget {
  const RaiUbicacionClienteMapAlert({
    super.key,
    this.mapFloating = false,
    this.obteniendoGps = false,
    this.permisoBloqueadoEnPantalla = false,
  });

  final bool mapFloating;
  final bool obteniendoGps;
  final bool permisoBloqueadoEnPantalla;

  @override
  Widget build(BuildContext context) {
    return RaiUbicacionMapAlert(
      rol: RaiUbicacionRol.cliente,
      mapFloating: mapFloating,
      obteniendoGps: obteniendoGps,
      permisoBloqueadoEnPantalla: permisoBloqueadoEnPantalla,
    );
  }
}
