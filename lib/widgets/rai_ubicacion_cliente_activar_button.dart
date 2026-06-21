import 'package:flutter/material.dart';

import 'package:flygo_nuevo/widgets/rai_ubicacion_activar_button.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';

/// Cliente: delega en [RaiUbicacionActivarButton].
class RaiUbicacionClienteActivarButton extends StatelessWidget {
  const RaiUbicacionClienteActivarButton({
    super.key,
    this.alerta = false,
    this.mapStyle = false,
    this.minimumSize = const Size(88, 40),
  });

  final bool alerta;
  final bool mapStyle;
  final Size minimumSize;

  @override
  Widget build(BuildContext context) {
    return RaiUbicacionActivarButton(
      rol: RaiUbicacionRol.cliente,
      alerta: alerta,
      mapStyle: mapStyle,
      minimumSize: minimumSize,
    );
  }
}
