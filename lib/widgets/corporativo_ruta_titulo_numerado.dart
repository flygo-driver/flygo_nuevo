import 'package:flutter/material.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';
import 'package:flygo_nuevo/utils/corporativo_ruta_enumeracion.dart';

/// Título «Ruta N» coherente en toda la app corporativa del encargado.
class CorporativoRutaTituloNumerado extends StatelessWidget {
  const CorporativoRutaTituloNumerado({
    super.key,
    required this.empresaId,
    required this.plantilla,
    this.numeroConocido,
    this.tituloStyle,
    this.subtituloStyle,
    this.maxLines = 2,
  });

  final String empresaId;
  final CorporativoPlantilla plantilla;
  final int? numeroConocido;
  final TextStyle? tituloStyle;
  final TextStyle? subtituloStyle;
  final int maxLines;

  Widget _build(int numero) {
    final titulo = CorporativoRutaEnumeracion.titulo(plantilla, numero);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: tituloStyle,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (numeroConocido != null && numeroConocido! > 0) {
      return _build(numeroConocido!);
    }
    return StreamBuilder<List<CorporativoPlantilla>>(
      stream: CorporativoRutaService.streamPlantillas(empresaId),
      builder: (context, snap) {
        final items = snap.data ?? [plantilla];
        final numero = CorporativoRutaEnumeracion.numeroDe(items, plantilla.id);
        return _build(numero);
      },
    );
  }
}

/// Badge compacto «Ruta 1» para chips y filas.
class CorporativoRutaNumeroBadge extends StatelessWidget {
  const CorporativoRutaNumeroBadge({
    super.key,
    required this.numero,
    this.compacto = false,
  });

  final int numero;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    if (numero <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 7 : 9,
        vertical: compacto ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.28)),
      ),
      child: Text(
        CorporativoRutaEnumeracion.etiquetaNumero(numero),
        style: TextStyle(
          color: Colors.indigo.shade800,
          fontSize: compacto ? 10 : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
