import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/bloqueado_por_pagos.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_pagos.dart';

/// Finanzas del taxista desde pestañas con [Navigator] anidado ([TaxistaShell]).
/// Usar siempre el [rootNavigator]; `pushNamed('/mis_pagos')` en el tab falla en silencio.
class TaxistaFinanzasNav {
  TaxistaFinanzasNav._();

  static Future<void> abrirMisPagos(
    BuildContext context, {
    bool scrollToRecargaSection = false,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MisPagos(
          scrollToRecargaSection: scrollToRecargaSection,
        ),
      ),
    );
  }

  static Future<void> abrirBloqueadoPagos(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const BloqueadoPorPagos(),
      ),
    );
  }
}
