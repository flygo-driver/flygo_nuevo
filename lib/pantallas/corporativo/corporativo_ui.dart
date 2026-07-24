import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/servicios/corporativo_ruta_service.dart';

/// Paleta RAI para módulo corporativo (claro / oscuro) — contraste en todos los dispositivos.
extension CorporativoUi on BuildContext {
  ({
    bool isDark,
    Color scaffold,
    Color card,
    Color cardBorder,
    Color primary,
    Color primarySoft,
    Color onPrimary,
    Color onCard,
    Color muted,
    Color accent,
    Color success,
    Color warning,
    Color danger,
    Color ctaBg,
    Color ctaFg,
    LinearGradient heroGrad,
    LinearGradient ctaGrad,
    List<BoxShadow> cardShadow,
  }) get corporativoPalette {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    final primary = isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E);
    final ctaBg = isDark ? const Color(0xFF14B8A6) : const Color(0xFF0D9488);
    return (
      isDark: isDark,
      scaffold: isDark ? const Color(0xFF0B1020) : const Color(0xFFF0F4F8),
      card: isDark ? const Color(0xFF151B2E) : Colors.white,
      cardBorder: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : const Color(0xFFD0D5DD),
      primary: primary,
      primarySoft:
          isDark ? const Color(0xFF16352F) : const Color(0xFFCCFBF1),
      onPrimary: isDark ? const Color(0xFF042F2E) : Colors.white,
      onCard: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
      muted: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475467),
      accent: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
      success: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      warning: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      danger: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
      ctaBg: ctaBg,
      ctaFg: Colors.white,
      heroGrad: LinearGradient(
        colors: isDark
            ? const [Color(0xFF12263A), Color(0xFF0B1020)]
            : const [Color(0xFFCCFBF1), Color(0xFFF0F9FF), Color(0xFFF8FAFC)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      ctaGrad: LinearGradient(
        colors: isDark
            ? const [Color(0xFF2DD4BF), Color(0xFF0D9488)]
            : const [Color(0xFF14B8A6), Color(0xFF0F766E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      cardShadow: isDark
          ? const <BoxShadow>[]
          : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
    );
  }
}

/// Limita escala de texto para evitar overflow en celulares con fuente grande.
Widget corporativoResponsive({required Widget child}) {
  return Builder(
    builder: (context) {
      final mq = MediaQuery.of(context);
      final capped = mq.textScaler.clamp(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.15,
      );
      return MediaQuery(
        data: mq.copyWith(textScaler: capped),
        child: child,
      );
    },
  );
}

Text corporativoEllipsis(
  String text, {
  required TextStyle style,
  int maxLines = 2,
  TextAlign? textAlign,
}) {
  return Text(
    text,
    style: style,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    softWrap: true,
    textAlign: textAlign,
  );
}

Widget corporativoSectionTitle(BuildContext context, String text) {
  final p = context.corporativoPalette;
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: corporativoEllipsis(
      text,
      maxLines: 2,
      style: TextStyle(
        color: p.onCard,
        fontWeight: FontWeight.w800,
        fontSize: 15,
        letterSpacing: 0.2,
      ),
    ),
  );
}

Widget corporativoCard(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  Color? borderColor,
  Gradient? gradient,
}) {
  final p = context.corporativoPalette;
  return Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: gradient == null ? p.card : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: borderColor ?? p.cardBorder),
      boxShadow: p.cardShadow,
    ),
    child: child,
  );
}

/// CTA principal corporativo — alto contraste en claro y oscuro.
Widget corporativoCtaButton({
  required BuildContext context,
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
  bool expanded = true,
}) {
  final p = context.corporativoPalette;
  final btn = DecoratedBox(
    decoration: BoxDecoration(
      gradient: onPressed == null ? null : p.ctaGrad,
      color: onPressed == null ? p.muted.withValues(alpha: 0.35) : null,
      borderRadius: BorderRadius.circular(14),
      boxShadow: onPressed == null
          ? null
          : [
              BoxShadow(
                color: p.ctaBg.withValues(alpha: p.isDark ? 0.35 : 0.4),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, color: p.ctaFg, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.ctaFg,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
}

Widget corporativoSecondaryButton({
  required BuildContext context,
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  final p = context.corporativoPalette;
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: p.onCard,
        side: BorderSide(color: p.cardBorder, width: 1.4),
        backgroundColor: p.isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

/// Confirma quitar un viaje del historial del encargado (oculto, no borra en RAI).
Future<bool> confirmarQuitarViajeHistorialCorporativo(
  BuildContext context, {
  required String nombreRuta,
  required String estado,
}) async {
  final p = context.corporativoPalette;
  final estadoLc = estado.trim().toLowerCase();
  final esCompletado = estadoLc == 'completado';
  final esActivo = estadoLc == 'lanzado' ||
      estadoLc == 'publicado_auto' ||
      estadoLc == 'aceptado' ||
      estadoLc == 'fallo_publicacion' ||
      estadoLc == 'fallo_asignacion';

  final detalle = esCompletado
      ? 'Se oculta de tu lista. El monto sigue en tu liquidación hasta que RAI '
          'apruebe una incidencia.\n\n'
          'Para quitar el cobro usá «Reportar incidencia».'
      : esActivo
          ? 'Si el chofer aún no empezó, se cancela el envío de hoy y se quita '
              'de tu historial. RAI conserva el registro para auditoría.'
          : 'Se quita de tu lista. RAI conserva el registro para auditoría y facturación.';

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.cardBorder),
      ),
      title: Text(
        'Quitar del historial',
        style: TextStyle(color: p.onCard, fontWeight: FontWeight.w900),
      ),
      content: Text(
        '¿Quitar «$nombreRuta» de tu historial?\n\n$detalle',
        style: TextStyle(color: p.muted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: p.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Quitar'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Confirma baja voluntaria de la empresa del servicio corporativo RAI.
/// Devuelve el motivo si confirmó; `null` si canceló.
Future<String?> confirmarDarDeBajaEmpresaCorporativo(
  BuildContext context, {
  required String nombreEmpresa,
  required double deudaPendienteRd,
  required NumberFormat fmtMonto,
}) async {
  final p = context.corporativoPalette;
  final motivoCtrl = TextEditingController();
  var confirmado = false;

  final motivo = await showDialog<String?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.cardBorder),
        ),
        title: Text(
          'Salir del servicio RAI',
          style: TextStyle(color: p.onCard, fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '¿Querés dar de baja «$nombreEmpresa» del servicio corporativo RAI?\n\n'
                'Se cancelan los envíos de hoy que aún no empezó el chofer, '
                'se eliminan las rutas guardadas y tu empresa deja de operar en RAI. '
                'El historial y las liquidaciones pendientes se conservan.',
                style: TextStyle(color: p.muted, height: 1.4),
              ),
              if (deudaPendienteRd > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Tenés ${fmtMonto.format(deudaPendienteRd)} pendiente de liquidar. '
                    'Podés salir igual, pero debés pagar a RAI según tu contrato.',
                    style: TextStyle(
                      color: p.onCard,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: motivoCtrl,
                maxLines: 2,
                style: TextStyle(color: p.onCard),
                decoration: InputDecoration(
                  labelText: 'Motivo (opcional)',
                  labelStyle: TextStyle(color: p.muted),
                  hintText: 'Ej.: ya no necesitamos el servicio',
                  hintStyle: TextStyle(color: p.muted.withValues(alpha: 0.7)),
                  filled: true,
                  fillColor: p.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.primary, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: confirmado,
                onChanged: (v) => setDlg(() => confirmado = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: p.danger,
                title: Text(
                  'Entiendo que mi empresa dejará de estar en RAI corporativo',
                  style: TextStyle(
                    color: p.onCard,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.danger),
            onPressed: confirmado
                ? () => Navigator.pop(ctx, motivoCtrl.text.trim())
                : null,
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    ),
  );

  motivoCtrl.dispose();
  return motivo;
}

Future<bool> confirmarEliminarRutaCorporativo(
  BuildContext context, {
  required String nombreRuta,
}) async {
  final p = context.corporativoPalette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.card,
      title: Text(
        'Eliminar ruta',
        style: TextStyle(color: p.onCard, fontWeight: FontWeight.w800),
      ),
      content: Text(
        '¿Eliminar «$nombreRuta» por completo?\n\n'
        'Se borran pasajeros y configuración. Si hoy ya se envió al chofer '
        'y el viaje no ha empezado, se cancela automáticamente.',
        style: TextStyle(color: p.muted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: p.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Elimina plantilla corporativa tras confirmación. Devuelve `true` si se borró.
Future<bool> ejecutarEliminarRutaCorporativo(
  BuildContext context, {
  required String empresaId,
  required CorporativoPlantilla plantilla,
}) async {
  final p = context.corporativoPalette;
  final ok = await confirmarEliminarRutaCorporativo(
    context,
    nombreRuta: plantilla.nombre,
  );
  if (!ok || !context.mounted) return false;

  try {
    final cancelados = await CorporativoRutaService.eliminarPlantilla(
      empresaId: empresaId,
      plantillaId: plantilla.id,
    );
    if (!context.mounted) return false;
    final extra = cancelados > 0
        ? ' Se canceló el envío de hoy al chofer.'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ruta eliminada.$extra'),
        backgroundColor: p.success,
      ),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$e'),
        backgroundColor: Colors.red.shade800,
      ),
    );
    return false;
  }
}
