import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';

import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';

/// Código del período de facturación: una clave para todas las rutas
/// hasta el pago / renovación del ciclo (semanal · quincenal · mensual).
class CorporativoCodigoVerificacionCard extends StatelessWidget {
  const CorporativoCodigoVerificacionCard({
    super.key,
    required this.codigo,
    this.compacto = false,
    this.etiquetaCiclo = '',
    this.validoHasta,
    this.activo = true,
    this.estadoEtiqueta = '',
  });

  final String codigo;
  final bool compacto;
  /// Ej. "Quincenal (15 días)" — opcional, solo texto informativo.
  final String etiquetaCiclo;
  final DateTime? validoHasta;
  final bool activo;
  final String estadoEtiqueta;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final limpio = codigo.replaceAll(RegExp(r'\D'), '');
    if (limpio.length != 6) return const SizedBox.shrink();
    final cicloTxt = etiquetaCiclo.trim();
    final estadoTxt = estadoEtiqueta.trim().isNotEmpty
        ? estadoEtiqueta.trim()
        : (activo ? 'Activo' : 'Expirado');
    final estadoColor = activo ? Colors.green.shade700 : Colors.red.shade700;
    final hastaTxt = validoHasta != null
        ? DateFormat('d MMM y', 'es').format(validoHasta!)
        : null;

    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: p.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Código del período de facturación',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: compacto ? 14 : 16,
                  ),
                ),
              ),
            ],
          ),
          if (!compacto) ...[
            const SizedBox(height: 6),
            Text(
              cicloTxt.isEmpty
                  ? 'Un solo código para todas tus rutas. Válido hasta el fin del período '
                      'de facturación. Al pagar, RAI genera un código nuevo.'
                  : 'Ciclo $cicloTxt. Un solo código para todas tus rutas. '
                      'Válido hasta el fin del período; al pagar se renueva.',
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
            ),
            if (hastaTxt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Válido hasta: $hastaTxt',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Estado: ', style: TextStyle(color: p.muted, fontSize: 12)),
                Text(
                  estadoTxt,
                  style: TextStyle(
                    color: estadoColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    limpio,
                    style: TextStyle(
                      color: p.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: compacto ? 26 : 32,
                      letterSpacing: 6,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copiar código',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: limpio));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código copiado'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(Icons.copy_rounded, color: p.primary),
              ),
            ],
          ),
          if (!compacto)
            Text(
              'Dictáselo a los empleados en el punto (no al chofer por chat). '
              'Sin código vigente → el taxista no inicia → no se cobra.\n'
              'Feriado / nadie viaja → no den el código.',
              style: TextStyle(color: p.muted, fontSize: 11, height: 1.35),
            ),
        ],
      ),
    );
  }
}
