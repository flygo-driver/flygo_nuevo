import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';

/// Ficha del conductor asignado (visible para el encargado de empresa).
class CorporativoChoferPerfilCard extends StatelessWidget {
  const CorporativoChoferPerfilCard({
    super.key,
    required this.perfil,
    this.compacto = false,
    this.mostrarTitulo = true,
  });

  final CorporativoChoferPerfil perfil;
  final bool compacto;
  final bool mostrarTitulo;

  void _copiar(BuildContext context, String texto) {
    if (texto.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: texto.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    if (!perfil.asignado) {
      return corporativoCard(
        context,
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'RAI aún no asignó el conductor de esta ruta.',
                style: TextStyle(
                  color: p.onCard,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget fila(String etiqueta, String valor, {bool copiable = false}) {
      if (valor.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: compacto ? 88 : 100,
              child: Text(
                etiqueta,
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                valor,
                style: TextStyle(
                  color: p.onCard,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (copiable)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Copiar',
                onPressed: () => _copiar(context, valor),
                icon: Icon(Icons.copy_rounded, size: 16, color: p.muted),
              ),
          ],
        ),
      );
    }

    final fmt = DateFormat('d MMM yyyy · HH:mm', 'es');

    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mostrarTitulo) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: compacto ? 20 : 24,
                  backgroundColor: p.primarySoft,
                  backgroundImage:
                      perfil.fotoUrl.isNotEmpty ? NetworkImage(perfil.fotoUrl) : null,
                  child: perfil.fotoUrl.isEmpty
                      ? Icon(Icons.person, color: p.primary)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        perfil.nombre.isNotEmpty
                            ? perfil.nombre
                            : 'Conductor RAI',
                        style: TextStyle(
                          color: p.onCard,
                          fontWeight: FontWeight.w800,
                          fontSize: compacto ? 15 : 16,
                        ),
                      ),
                      if (perfil.documentosVerificados)
                        Text(
                          'Documentos verificados por RAI',
                          style: TextStyle(color: p.success, fontSize: 11),
                        ),
                      if (perfil.calificacionPromedio > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.star_rounded,
                                color: Colors.amber.shade700, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              perfil.calificacionPromedio.toStringAsFixed(1),
                              style: TextStyle(
                                color: p.onCard,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (perfil.aniosExperiencia > 0)
                        Text(
                          '${perfil.aniosExperiencia} año${perfil.aniosExperiencia == 1 ? '' : 's'} en RAI',
                          style: TextStyle(color: p.muted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          fila('Teléfono', perfil.telefono, copiable: true),
          fila('Correo', perfil.email, copiable: true),
          fila('Cédula', perfil.cedula, copiable: true),
          fila('Placa', perfil.placa, copiable: true),
          if (perfil.vehiculoDescripcion.isNotEmpty)
            fila('Vehículo', perfil.vehiculoDescripcion),
          if (perfil.tipoVehiculo.isNotEmpty)
            fila('Tipo', perfil.tipoVehiculo),
          if (perfil.documentosVerificados)
            fila('Licencia / matrícula', 'Verificada en RAI Driver'),
          if (perfil.asignadoEn != null)
            fila('Asignado', fmt.format(perfil.asignadoEn!)),
        ],
      ),
    );
  }
}
