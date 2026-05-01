// Acciones y diálogos de Bola Ahorro (reutilizable en pantalla completa y pestaña taxista).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_crear_publicacion_flow.dart';
import 'package:flygo_nuevo/widgets/bola_pueblo_contraparte_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_visual.dart';
export 'package:flygo_nuevo/pantallas/comun/bola_pueblo_visual.dart';

class BolaPuebloNav {
  BolaPuebloNav._();

  static bool _coordPairOk(double? a, double? b) =>
      a != null && b != null && a.isFinite && b.isFinite;

  static Future<void> abrirSelectorNavegacion(
    BuildContext context, {
    required String origen,
    required String destino,
    double? origenLat,
    double? origenLon,
    double? destinoLat,
    double? destinoLon,
  }) async {
    final c = BolaPuebloColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cc = BolaPuebloColors.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cc.dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  '¿Cómo quieres navegar?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cc.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$origen → $destino',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cc.onMuted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 20),
                _NavTile(
                  icon: Icons.map_outlined,
                  iconBg: const Color(0xFF1E88E5).withValues(alpha: 0.25),
                  iconColor: cc.isDark
                      ? const Color(0xFF7CB9FF)
                      : const Color(0xFF1565C0),
                  title: 'Google Maps',
                  subtitle: 'Ruta paso a paso',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await abrirGoogleMapsDir(
                      origen: origen,
                      destino: destino,
                      origenLat: origenLat,
                      origenLon: origenLon,
                      destinoLat: destinoLat,
                      destinoLon: destinoLon,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _NavTile(
                  icon: Icons.navigation_rounded,
                  iconBg: const Color(0xFF039BE5).withValues(alpha: 0.25),
                  iconColor: cc.isDark
                      ? const Color(0xFF33CCFF)
                      : const Color(0xFF0277BD),
                  title: 'Waze',
                  subtitle: 'Navegación en vivo',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await abrirWazeHaciaDestino(
                      origen: origen,
                      destino: destino,
                      origenLat: origenLat,
                      origenLon: origenLon,
                      destinoLat: destinoLat,
                      destinoLon: destinoLon,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> abrirGoogleMapsDir({
    required String origen,
    required String destino,
    double? origenLat,
    double? origenLon,
    double? destinoLat,
    double? destinoLon,
  }) async {
    final Uri maps;
    if (_coordPairOk(origenLat, origenLon) &&
        _coordPairOk(destinoLat, destinoLon)) {
      maps = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&origin=${origenLat!.toStringAsFixed(6)},${origenLon!.toStringAsFixed(6)}'
        '&destination=${destinoLat!.toStringAsFixed(6)},${destinoLon!.toStringAsFixed(6)}'
        '&travelmode=driving',
      );
    } else {
      final String o = Uri.encodeComponent(origen.trim());
      final String d = Uri.encodeComponent(destino.trim());
      maps = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$o&destination=$d&travelmode=driving',
      );
    }
    await launchUrl(maps, mode: LaunchMode.externalApplication);
  }

  /// Waze: con coordenadas usa destino como punto final; si no, búsqueda por texto.
  static Future<void> abrirWazeHaciaDestino({
    required String origen,
    required String destino,
    double? origenLat,
    double? origenLon,
    double? destinoLat,
    double? destinoLon,
  }) async {
    final Uri waze;
    if (_coordPairOk(destinoLat, destinoLon)) {
      waze = Uri.parse(
        'https://waze.com/ul?ll=${destinoLat!.toStringAsFixed(6)},${destinoLon!.toStringAsFixed(6)}&navigate=yes',
      );
    } else {
      final String q = Uri.encodeComponent(
        '${origen.trim()} → ${destino.trim()}',
      );
      waze = Uri.parse(
        'https://waze.com/ul?q=$q&navigate=yes',
      );
    }
    if (await canLaunchUrl(waze)) {
      await launchUrl(waze, mode: LaunchMode.externalApplication);
      return;
    }
    final Uri alt = Uri.parse(
      waze.toString().replaceFirst('waze.com', 'www.waze.com'),
    );
    await launchUrl(alt, mode: LaunchMode.externalApplication);
  }

  /// Tramo en curso: solo hasta el destino final (taxista o cliente).
  static Future<void> abrirSelectorSoloDestino(
    BuildContext context, {
    required String destinoLabel,
    double? destinoLat,
    double? destinoLon,
    String sheetTitle = 'Ir al destino del viaje',
    String hint =
        'Desde donde estés ahora hasta el destino acordado en la bola.',
  }) async {
    final c = BolaPuebloColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cc = BolaPuebloColors.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cc.dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  sheetTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cc.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  destinoLabel,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cc.onMuted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cc.onMuted.withValues(alpha: 0.9),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 20),
                _NavTile(
                  icon: Icons.map_outlined,
                  iconBg: const Color(0xFF1E88E5).withValues(alpha: 0.25),
                  iconColor: cc.isDark
                      ? const Color(0xFF7CB9FF)
                      : const Color(0xFF1565C0),
                  title: 'Google Maps',
                  subtitle: 'Hasta el destino',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await abrirGoogleMapsSoloDestino(
                      direccion: destinoLabel,
                      lat: destinoLat,
                      lon: destinoLon,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _NavTile(
                  icon: Icons.navigation_rounded,
                  iconBg: const Color(0xFF039BE5).withValues(alpha: 0.25),
                  iconColor: cc.isDark
                      ? const Color(0xFF33CCFF)
                      : const Color(0xFF0277BD),
                  title: 'Waze',
                  subtitle: 'Hasta el destino',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await abrirWazeSoloPunto(
                      direccion: destinoLabel,
                      lat: destinoLat,
                      lon: destinoLon,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Solo hacia un punto (desde la ubicación actual del usuario), p. ej. recogida del pasajero
  /// o punto donde espera el conductor en publicaciones «Voy para».
  /// Devuelve `true` si eligió Maps o Waze (p. ej. para avanzar pasos en la UI del taxista).
  static Future<bool> abrirSelectorNavegacionSoloRecogida(
    BuildContext context, {
    required String recogida,
    double? recogidaLat,
    double? recogidaLon,
    String sheetTitle = 'Ir al punto de recogida',
    String mapsSubtitle = 'Hasta el cliente',
    String wazeSubtitle = 'Hasta el cliente',
    String hint =
        'Se abre navegación desde tu ubicación actual hacia esta dirección.',
  }) async {
    final c = BolaPuebloColors.of(context);
    final launched = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cc = BolaPuebloColors.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cc.dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  sheetTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cc.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  recogida,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cc.onMuted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cc.onMuted.withValues(alpha: 0.9),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 20),
                _NavTile(
                  icon: Icons.map_outlined,
                  iconBg: const Color(0xFF1E88E5).withValues(alpha: 0.25),
                  iconColor: cc.isDark
                      ? const Color(0xFF7CB9FF)
                      : const Color(0xFF1565C0),
                  title: 'Google Maps',
                  subtitle: mapsSubtitle,
                  onTap: () async {
                    Navigator.pop(ctx, true);
                    await abrirGoogleMapsSoloDestino(
                      direccion: recogida,
                      lat: recogidaLat,
                      lon: recogidaLon,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _NavTile(
                  icon: Icons.navigation_rounded,
                  iconBg: const Color(0xFF039BE5).withValues(alpha: 0.25),
                  iconColor: cc.isDark
                      ? const Color(0xFF33CCFF)
                      : const Color(0xFF0277BD),
                  title: 'Waze',
                  subtitle: wazeSubtitle,
                  onTap: () async {
                    Navigator.pop(ctx, true);
                    await abrirWazeSoloPunto(
                      direccion: recogida,
                      lat: recogidaLat,
                      lon: recogidaLon,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    return launched == true;
  }

  static Future<void> abrirGoogleMapsSoloDestino({
    String direccion = '',
    double? lat,
    double? lon,
  }) async {
    final Uri maps;
    if (_coordPairOk(lat, lon)) {
      maps = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${lat!.toStringAsFixed(6)},${lon!.toStringAsFixed(6)}&travelmode=driving',
      );
    } else {
      final String d = Uri.encodeComponent(direccion.trim());
      maps = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$d&travelmode=driving',
      );
    }
    await launchUrl(maps, mode: LaunchMode.externalApplication);
  }

  static Future<void> abrirWazeSoloPunto({
    String direccion = '',
    double? lat,
    double? lon,
  }) async {
    final Uri waze;
    if (_coordPairOk(lat, lon)) {
      waze = Uri.parse(
        'https://waze.com/ul?ll=${lat!.toStringAsFixed(6)},${lon!.toStringAsFixed(6)}&navigate=yes',
      );
    } else {
      final String q = Uri.encodeComponent(direccion.trim());
      waze = Uri.parse('https://waze.com/ul?q=$q&navigate=yes');
    }
    if (await canLaunchUrl(waze)) {
      await launchUrl(waze, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(
      Uri.parse(waze.toString().replaceFirst('waze.com', 'www.waze.com')),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return Material(
      color: c.surfaceRaised,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: c.onMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.outlineOnCard),
            ],
          ),
        ),
      ),
    );
  }
}

class BolaPuebloFormat {
  BolaPuebloFormat._();

  static String textoVigenciaCodigo(dynamic ts) {
    if (ts is! Timestamp) return 'Vigencia del código: 20 min';
    final DateTime vence = ts.toDate().add(BolaPuebloRepo.vigenciaCodigoInicio);
    final Duration left = vence.difference(DateTime.now());
    if (left.inSeconds <= 0) return 'Código vencido. Deben reacordar la bola.';
    return 'Código vence en ${left.inMinutes} min';
  }

  static String fmtTs(dynamic v) {
    if (v is! Timestamp) return 'Fecha por definir';
    final d = v.toDate();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${d.year} $hh:$mi';
  }
}

class BolaPuebloDialogs {
  BolaPuebloDialogs._();

  static Future<String?> pedirCodigoInicio(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final col = BolaPuebloColors.of(ctx);
        return Theme(
          data: BolaPuebloTheme.dialogTheme(context),
          child: AlertDialog(
            backgroundColor: col.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Código de verificación',
                style: TextStyle(color: col.onSurface)),
            content: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(
                  color: col.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Código del cliente',
                hintText: 'Cuatro dígitos',
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Verificar')),
            ],
          ),
        );
      },
    );
    if (ok != true) return null;
    return c.text.trim();
  }

  static Future<void> crearPublicacion({
    required BuildContext context,
    required String uid,
    required String rol,
    required String nombre,
    required String tipo,
    required void Function(bool busy) onBusy,
  }) async {
    final result =
        await Navigator.of(context).push<BolaPuebloCrearPublicacionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => BolaPuebloCrearPublicacionFlow(tipo: tipo),
      ),
    );

    if (result == null) return;
    try {
      onBusy(true);
      await BolaPuebloRepo.crearPublicacion(
        uid: uid,
        rol: rol,
        nombre: nombre,
        tipo: tipo,
        origen: result.origen,
        destino: result.destino,
        distanciaKm: result.distanciaKm,
        fechaSalida: result.fechaSalida,
        nota: result.nota,
        origenLat: result.origenLat,
        origenLon: result.origenLon,
        destinoLat: result.destinoLat,
        destinoLon: result.destinoLon,
        pasajeros: result.pasajeros,
        montoPropuestoRd: result.montoPropuestoRd,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        BolaPuebloTheme.snack(context, 'Publicación creada'),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(BolaPuebloTheme.snack(context, '$e', error: true));
    } finally {
      onBusy(false);
    }
  }

  static Future<void> enviarOferta({
    required BuildContext context,
    required String bolaId,
    required String uid,
    required String nombre,
    required String rol,
    double? montoInicial,
  }) async {
    final mi = montoInicial;
    final double semillaCampo = (mi != null && mi > 0) ? mi : 1500;
    final montoCtrl =
        TextEditingController(text: semillaCampo.toStringAsFixed(0));
    final msgCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final col = BolaPuebloColors.of(context);
        var cerrando = false;
        return Theme(
          data: BolaPuebloTheme.dialogTheme(context),
          child: StatefulBuilder(
            builder: (ctxDialog, setDialog) {
              return AlertDialog(
                backgroundColor: col.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                title:
                    Text('Tu oferta', style: TextStyle(color: col.onSurface)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: montoCtrl,
                      style: TextStyle(
                          color: col.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Monto en RD\$',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: msgCtrl,
                      style: TextStyle(color: col.onSurface),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje (opcional)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        cerrando ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: cerrando
                        ? null
                        : () {
                            cerrando = true;
                            setDialog(() {});
                            Navigator.pop(ctx, true);
                          },
                    child: const Text('Enviar oferta'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (ok != true) return;
    final monto =
        double.tryParse(montoCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    try {
      await BolaPuebloRepo.enviarOferta(
        bolaId: bolaId,
        fromUid: uid,
        fromNombre: nombre,
        fromRol: rol,
        montoRd: monto,
        mensaje: msgCtrl.text,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(BolaPuebloTheme.snack(context, 'Oferta enviada'));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(BolaPuebloTheme.snack(context, '$e', error: true));
    }
  }

  /// Pedido: el pasajero responde al monto del conductor con otra cifra dentro del rango.
  static Future<void> proponerContraofertaCliente({
    required BuildContext context,
    required String bolaId,
    required String uid,
    required String nombre,
    required String taxistaUid,
    required String taxistaNombre,
    required double montoTaxista,
    required String ofertaTaxistaId,
    double? ofertaMinRd,
    double? ofertaMaxRd,
  }) async {
    final semilla = montoTaxista > 0 ? montoTaxista : (ofertaMinRd ?? 1500);
    final montoCtrl = TextEditingController(text: semilla.toStringAsFixed(0));
    final msgCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final col = BolaPuebloColors.of(context);
        var cerrando = false;
        return Theme(
          data: BolaPuebloTheme.dialogTheme(context),
          child: StatefulBuilder(
            builder: (ctxDialog, setDialog) {
              return AlertDialog(
                backgroundColor: col.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                title: Text('Tu contraoferta',
                    style: TextStyle(color: col.onSurface)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${taxistaNombre.trim().isEmpty ? "Conductor" : taxistaNombre.trim()} '
                      'propuso RD\$${montoTaxista.toStringAsFixed(0)}. '
                      'Indicá el monto con el que te quedarías; el conductor puede aceptar o rechazar.',
                      style: TextStyle(
                          color: col.onMuted, fontSize: 13, height: 1.4),
                    ),
                    if (ofertaMinRd != null &&
                        ofertaMaxRd != null &&
                        ofertaMaxRd >= ofertaMinRd) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Rango permitido: RD\$${ofertaMinRd.toStringAsFixed(0)} – RD\$${ofertaMaxRd.toStringAsFixed(0)}',
                        style: TextStyle(color: col.onMuted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: montoCtrl,
                      style: TextStyle(
                          color: col.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tu monto (RD\$)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: msgCtrl,
                      style: TextStyle(color: col.onSurface),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje (opcional)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        cerrando ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: cerrando
                        ? null
                        : () {
                            cerrando = true;
                            setDialog(() {});
                            Navigator.pop(ctx, true);
                          },
                    child: const Text('Enviar contraoferta'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (ok != true) return;
    final monto =
        double.tryParse(montoCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    try {
      await BolaPuebloRepo.enviarContraofertaCliente(
        bolaId: bolaId,
        clienteUid: uid,
        clienteNombre: nombre,
        taxistaUid: taxistaUid,
        respondiendoOfertaId: ofertaTaxistaId,
        montoRd: monto,
        mensaje: msgCtrl.text,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        BolaPuebloTheme.snack(context,
            'Contraoferta enviada. El conductor puede aceptarla desde su tarjeta.'),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(BolaPuebloTheme.snack(context, '$e', error: true));
    }
  }

  static Future<void> mostrarPostAceptarOfertaDialog(
      BuildContext context) async {
    final c = BolaPuebloColors.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: c.surfaceRaised,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Acuerdo confirmado',
            style: TextStyle(color: c.onSurface, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Precio cerrado: el traslado sigue en esta misma bola. El conductor ve los pasos para ir a buscarte, '
            'registrar abordo e iniciar con tu código; vos tenés el código en la tarjeta.\n\n'
            'Después, en curso, ambos confirman llegada al destino y el viaje queda finalizado '
            '(se registra la comisión RAI al conductor según lo acordado).\n\n'
            'Si necesitás cancelar antes de subir, usá «Cancelar acuerdo».',
            style: TextStyle(color: c.onMuted, height: 1.45, fontSize: 14),
          ),
          actions: [
            FilledButton(
              style: BolaPuebloUi.filledPrimary,
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> confirmarCancelarAcuerdoBola({
    required BuildContext context,
    required String bolaId,
    required String uid,
  }) async {
    final c = BolaPuebloColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '¿Cancelar el acuerdo?',
          style: TextStyle(color: c.onSurface, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Podés volver a publicar u ofertar en otra bola. No se puede cancelar si el conductor ya registró el abordo.',
          style: TextStyle(color: c.onMuted, height: 1.45, fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Volver')),
          FilledButton(
            style: BolaPuebloUi.filledPrimary,
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await BolaPuebloRepo.cancelarAcuerdoAntesDeAbordo(
          bolaId: bolaId, uidActor: uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(BolaPuebloTheme.snack(context, 'Acuerdo cancelado'));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(BolaPuebloTheme.snack(context, '$e', error: true));
      }
    }
  }

  static String _etiquetaEstadoOferta(String estado) {
    switch (estado) {
      case 'pendiente':
        return 'Pendiente';
      case 'aceptada':
        return 'Aceptada';
      case 'rechazada':
        return 'Descartada';
      case 'retirada':
        return 'Retirada';
      default:
        return estado;
    }
  }

  static Future<String?> pedirMotivoRechazoContraoferta(
      BuildContext context) async {
    final ctrl = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) {
          final cc = Theme.of(ctx).extension<BolaPuebloColors>()!;
          return AlertDialog(
            backgroundColor: cc.surface,
            title: Text('Motivo del rechazo',
                style: TextStyle(color: cc.onSurface)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _motivoRapidoChip(
                      context: ctx,
                      label: 'Monto insuficiente',
                      onTap: () => ctrl.text = 'El monto es insuficiente.',
                    ),
                    _motivoRapidoChip(
                      context: ctx,
                      label: 'Ruta no conveniente',
                      onTap: () => ctrl.text = 'La ruta no es conveniente ahora.',
                    ),
                    _motivoRapidoChip(
                      context: ctx,
                      label: 'Horario no me funciona',
                      onTap: () =>
                          ctrl.text = 'Ese horario no me funciona.',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  style: TextStyle(color: cc.onSurface),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Ej: el monto no cubre combustible y peajes',
                    hintStyle: TextStyle(color: cc.onMuted),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancelar', style: TextStyle(color: cc.onMuted)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Rechazar'),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  static Widget _motivoRapidoChip({
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
  }) {
    final cc = Theme.of(context).extension<BolaPuebloColors>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cc.onSurface.withValues(alpha: cc.isDark ? 0.08 : 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cc.onSurface.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: cc.onMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static void verOfertasSheet(
    BuildContext context,
    String bolaId, {
    required String tipoPublicacion,
    double? ofertaMinRd,
    double? ofertaMaxRd,
  }) {
    final c = BolaPuebloColors.of(context);
    String? aceptandoOfertaId;
    String? rechazandoOfertaId;
    String? retirandoOfertaId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final cc = BolaPuebloColors.of(sheetCtx);
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetCtx).size.height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cc.dragHandle,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            tipoPublicacion == 'pedido'
                                ? 'Ofertas de conductores'
                                : 'Propuestas de pago',
                            style: TextStyle(
                              color: cc.onSurface,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tipoPublicacion == 'pedido'
                                ? 'Compará montos de los conductores. Podés aceptar, descartar o enviar una contraoferta '
                                    'con otro monto (el conductor la verá en su tarjeta y puede aceptarla o rechazarla). '
                                    'La publicación sigue abierta hasta que cierres un acuerdo.'
                                : 'Compará montos y mensajes (horario, condiciones, etc.). '
                                    'Podés aceptar una propuesta para cerrar el precio, o descartar la que no te sirve: '
                                    'la publicación sigue abierta en el tablero y en el pool hasta que aceptes una. '
                                    'Si alguien reenvía cifra, ves su última pendiente.',
                            style: TextStyle(
                                color: cc.onMuted, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: BolaPuebloRepo.streamOfertas(bolaId),
                        builder: (_, snap) {
                          final raw = snap.data?.docs ?? const [];
                          // Conductores: una pendiente por uid. Contraofertas del pasajero: todas las pendientes.
                          final seenTaxistaPending = <String>{};
                          final docs =
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          for (final d in raw) {
                            final m = d.data();
                            final estado = (m['estado'] ?? '').toString();
                            final from = (m['fromUid'] ?? '').toString();
                            final esContraCliente =
                                m['esContraofertaCliente'] == true;
                            if (estado == 'pendiente' && !esContraCliente) {
                              if (from.isEmpty ||
                                  seenTaxistaPending.contains(from)) {
                                continue;
                              }
                              seenTaxistaPending.add(from);
                            }
                            docs.add(d);
                          }
                          final miUid =
                              FirebaseAuth.instance.currentUser?.uid ?? '';
                          if (docs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Aún no hay ofertas',
                                  style: TextStyle(
                                      color: cc.onMuted, fontSize: 15),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: docs.length,
                            itemBuilder: (_, i) {
                              final d = docs[i];
                              final m = d.data();
                              final estado = (m['estado'] ?? '').toString();
                              final fromNombre =
                                  (m['fromNombre'] ?? 'Usuario').toString();
                              final fromUid = (m['fromUid'] ?? '').toString();
                              final fromRol =
                                  (m['fromRol'] ?? '').toString().toLowerCase();
                              final esTaxistaOffer =
                                  fromRol == 'taxista' || fromRol == 'driver';
                              final esContraCliente =
                                  m['esContraofertaCliente'] == true;
                              final esMiContraPendientePedido =
                                  estado == 'pendiente' &&
                                      esContraCliente &&
                                      fromUid == miUid;
                              final esMiContraPendienteOferta =
                                  estado == 'pendiente' &&
                                      tipoPublicacion == 'oferta' &&
                                      !esContraCliente &&
                                      fromUid == miUid &&
                                      esTaxistaOffer;
                              final esMiContraPendiente =
                                  esMiContraPendientePedido ||
                                      esMiContraPendienteOferta;
                              final filaConductorPedido =
                                  estado == 'pendiente' &&
                                      tipoPublicacion == 'pedido' &&
                                      esTaxistaOffer;
                              final filaClienteOferta = estado == 'pendiente' &&
                                  tipoPublicacion == 'oferta' &&
                                  fromRol == 'cliente';
                              final tituloFila = esMiContraPendiente
                                  ? 'Tu contraoferta'
                                  : fromNombre;
                              final monto =
                                  ((m['montoRd'] ?? 0) as num).toDouble();
                              final msg = (m['mensaje'] ?? '').toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: cc.surfaceRaised,
                                  borderRadius: BorderRadius.circular(18),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                tituloFila,
                                                style: TextStyle(
                                                  color: cc.onSurface,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              'RD\$${monto.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                color: BolaPuebloTheme.accent,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          msg.isEmpty ? 'Sin mensaje' : msg,
                                          style: TextStyle(
                                            color: cc.onSurface.withValues(
                                                alpha: cc.isDark ? 0.75 : 0.72),
                                            fontSize: 14,
                                            height: 1.35,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (esMiContraPendiente)
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                'Esperando al conductor. Si cambiás de idea, podés retirar tu contraoferta.',
                                                style: TextStyle(
                                                  color: cc.onMuted,
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: cc.onSurface,
                                                  side: BorderSide(
                                                    color: cc.onSurface
                                                        .withValues(
                                                            alpha: 0.35),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 14),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                  ),
                                                ),
                                                onPressed: (aceptandoOfertaId !=
                                                            null ||
                                                        rechazandoOfertaId !=
                                                            null ||
                                                        retirandoOfertaId !=
                                                            null)
                                                    ? null
                                                    : () async {
                                                        final ok =
                                                            await showDialog<
                                                                bool>(
                                                          context: sheetCtx,
                                                          builder: (dCtx) {
                                                            final dc =
                                                                BolaPuebloColors
                                                                    .of(dCtx);
                                                            return AlertDialog(
                                                              backgroundColor: dc
                                                                  .surfaceRaised,
                                                              title: Text(
                                                                '¿Retirar tu contraoferta?',
                                                                style:
                                                                    TextStyle(
                                                                  color: dc
                                                                      .onSurface,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                              ),
                                                              content: Text(
                                                                'Podés enviar otra más adelante si querés.',
                                                                style:
                                                                    TextStyle(
                                                                  color: dc
                                                                      .onMuted,
                                                                  height: 1.45,
                                                                  fontSize: 14,
                                                                ),
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          dCtx,
                                                                          false),
                                                                  child: const Text(
                                                                      'Volver'),
                                                                ),
                                                                FilledButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          dCtx,
                                                                          true),
                                                                  child: const Text(
                                                                      'Retirar'),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        );
                                                        if (ok != true) return;
                                                        retirandoOfertaId =
                                                            d.id;
                                                        setModalState(() {});
                                                        try {
                                                          await BolaPuebloRepo
                                                              .retirarMiOfertaPendiente(
                                                            bolaId: bolaId,
                                                            ofertaId: d.id,
                                                            uid: miUid,
                                                          );
                                                          if (context.mounted) {
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              BolaPuebloTheme
                                                                  .snack(
                                                                context,
                                                                'Contraoferta retirada',
                                                              ),
                                                            );
                                                          }
                                                        } catch (e) {
                                                          if (context.mounted) {
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              BolaPuebloTheme
                                                                  .snack(
                                                                context,
                                                                '$e',
                                                                error: true,
                                                              ),
                                                            );
                                                          }
                                                        } finally {
                                                          retirandoOfertaId =
                                                              null;
                                                          if (sheetCtx
                                                              .mounted) {
                                                            setModalState(
                                                                () {});
                                                          }
                                                        }
                                                      },
                                                child: retirandoOfertaId == d.id
                                                    ? SizedBox(
                                                        height: 22,
                                                        width: 22,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2.5,
                                                          color: cc.onSurface
                                                              .withValues(
                                                                  alpha: 0.8),
                                                        ),
                                                      )
                                                    : const Text(
                                                        'Retirar contraoferta'),
                                              ),
                                            ],
                                          )
                                        else if (estado == 'pendiente')
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: OutlinedButton(
                                                      style: OutlinedButton
                                                          .styleFrom(
                                                        foregroundColor:
                                                            cc.onSurface,
                                                        side: BorderSide(
                                                          color: cc.onSurface
                                                              .withValues(
                                                                  alpha: 0.35),
                                                        ),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 14),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(14),
                                                        ),
                                                      ),
                                                      onPressed:
                                                          (aceptandoOfertaId !=
                                                                      null ||
                                                                  rechazandoOfertaId !=
                                                                      null ||
                                                                  retirandoOfertaId !=
                                                                      null)
                                                              ? null
                                                              : () async {
                                                                  final ok =
                                                                      await showDialog<
                                                                          bool>(
                                                                    context:
                                                                        sheetCtx,
                                                                    builder:
                                                                        (dCtx) {
                                                                      final dc =
                                                                          BolaPuebloColors.of(
                                                                              dCtx);
                                                                      return AlertDialog(
                                                                        backgroundColor:
                                                                            dc.surfaceRaised,
                                                                        title:
                                                                            Text(
                                                                          '¿Descartar esta propuesta?',
                                                                          style:
                                                                              TextStyle(
                                                                            color:
                                                                                dc.onSurface,
                                                                            fontWeight:
                                                                                FontWeight.w800,
                                                                          ),
                                                                        ),
                                                                        content:
                                                                            Text(
                                                                          'No se cierra el precio ni se asigna conductor. '
                                                                          'Tu publicación sigue visible en el tablero y en el pool; '
                                                                          'quien ofertó puede enviarte otra cifra si quiere.',
                                                                          style:
                                                                              TextStyle(
                                                                            color:
                                                                                dc.onMuted,
                                                                            height:
                                                                                1.45,
                                                                            fontSize:
                                                                                14,
                                                                          ),
                                                                        ),
                                                                        actions: [
                                                                          TextButton(
                                                                            onPressed: () =>
                                                                                Navigator.pop(dCtx, false),
                                                                            child:
                                                                                const Text('Volver'),
                                                                          ),
                                                                          FilledButton(
                                                                            style:
                                                                                FilledButton.styleFrom(
                                                                              backgroundColor: Colors.redAccent,
                                                                              foregroundColor: Colors.white,
                                                                            ),
                                                                            onPressed: () =>
                                                                                Navigator.pop(dCtx, true),
                                                                            child:
                                                                                const Text('Descartar'),
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  );
                                                                  if (ok !=
                                                                      true) {
                                                                    return;
                                                                  }
                                                                  rechazandoOfertaId =
                                                                      d.id;
                                                                  setModalState(
                                                                      () {});
                                                                  try {
                                                                    await BolaPuebloRepo
                                                                        .rechazarOfertaPublicador(
                                                                      bolaId:
                                                                          bolaId,
                                                                      ofertaId:
                                                                          d.id,
                                                                    );
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger.of(
                                                                              context)
                                                                          .showSnackBar(
                                                                        BolaPuebloTheme
                                                                            .snack(
                                                                          context,
                                                                          'Propuesta descartada',
                                                                        ),
                                                                      );
                                                                    }
                                                                  } catch (e) {
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger.of(
                                                                              context)
                                                                          .showSnackBar(
                                                                        BolaPuebloTheme
                                                                            .snack(
                                                                          context,
                                                                          '$e',
                                                                          error:
                                                                              true,
                                                                        ),
                                                                      );
                                                                    }
                                                                  } finally {
                                                                    rechazandoOfertaId =
                                                                        null;
                                                                    if (sheetCtx
                                                                        .mounted) {
                                                                      setModalState(
                                                                          () {});
                                                                    }
                                                                  }
                                                                },
                                                      child:
                                                          rechazandoOfertaId ==
                                                                  d.id
                                                              ? SizedBox(
                                                                  height: 22,
                                                                  width: 22,
                                                                  child:
                                                                      CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2.5,
                                                                    color: cc
                                                                        .onSurface
                                                                        .withValues(
                                                                            alpha:
                                                                                0.8),
                                                                  ),
                                                                )
                                                              : const Text(
                                                                  'Descartar'),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: FilledButton(
                                                      style: FilledButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            BolaPuebloTheme
                                                                .accent,
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 14),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(14),
                                                        ),
                                                      ),
                                                      onPressed:
                                                          (aceptandoOfertaId !=
                                                                      null ||
                                                                  rechazandoOfertaId !=
                                                                      null ||
                                                                  retirandoOfertaId !=
                                                                      null)
                                                              ? null
                                                              : () async {
                                                                  aceptandoOfertaId =
                                                                      d.id;
                                                                  setModalState(
                                                                      () {});
                                                                  try {
                                                                    await BolaPuebloRepo
                                                                        .aceptarOferta(
                                                                      bolaId:
                                                                          bolaId,
                                                                      ofertaId:
                                                                          d.id,
                                                                    );
                                                                    if (sheetCtx
                                                                        .mounted) {
                                                                      Navigator.pop(
                                                                          sheetCtx);
                                                                    }
                                                                    if (context
                                                                        .mounted) {
                                                                      await BolaPuebloDialogs
                                                                          .mostrarPostAceptarOfertaDialog(
                                                                        context,
                                                                      );
                                                                    }
                                                                  } catch (e) {
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger.of(
                                                                              context)
                                                                          .showSnackBar(
                                                                        BolaPuebloTheme
                                                                            .snack(
                                                                          context,
                                                                          '$e',
                                                                          error:
                                                                              true,
                                                                        ),
                                                                      );
                                                                    }
                                                                  } finally {
                                                                    aceptandoOfertaId =
                                                                        null;
                                                                    if (sheetCtx
                                                                        .mounted) {
                                                                      setModalState(
                                                                          () {});
                                                                    }
                                                                  }
                                                                },
                                                      child:
                                                          aceptandoOfertaId ==
                                                                  d.id
                                                              ? const SizedBox(
                                                                  height: 22,
                                                                  width: 22,
                                                                  child:
                                                                      CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2.5,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                )
                                                              : const Text(
                                                                  'Aceptar'),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (filaConductorPedido) ...[
                                                const SizedBox(height: 10),
                                                OutlinedButton.icon(
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        BolaPuebloTheme.accent,
                                                    side: BorderSide(
                                                      color: BolaPuebloTheme
                                                          .accent
                                                          .withValues(
                                                              alpha: 0.55),
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 14),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                    ),
                                                  ),
                                                  onPressed: (aceptandoOfertaId !=
                                                              null ||
                                                          rechazandoOfertaId !=
                                                              null ||
                                                          retirandoOfertaId !=
                                                              null)
                                                      ? null
                                                      : () async {
                                                          final u = FirebaseAuth
                                                              .instance
                                                              .currentUser;
                                                          if (u == null) return;
                                                          await BolaPuebloDialogs
                                                              .proponerContraofertaCliente(
                                                            context: sheetCtx,
                                                            bolaId: bolaId,
                                                            uid: u.uid,
                                                            nombre:
                                                                u.displayName ??
                                                                    'Pasajero',
                                                            taxistaUid: fromUid,
                                                            taxistaNombre:
                                                                fromNombre,
                                                            montoTaxista: monto,
                                                            ofertaTaxistaId:
                                                                d.id,
                                                            ofertaMinRd:
                                                                ofertaMinRd,
                                                            ofertaMaxRd:
                                                                ofertaMaxRd,
                                                          );
                                                          if (sheetCtx
                                                              .mounted) {
                                                            setModalState(
                                                                () {});
                                                          }
                                                        },
                                                  icon: const Icon(
                                                      Icons.swap_horiz_rounded,
                                                      size: 20),
                                                  label: const Text(
                                                      'Proponer otro monto'),
                                                ),
                                              ],
                                              if (filaClienteOferta) ...[
                                                const SizedBox(height: 10),
                                                OutlinedButton.icon(
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        BolaPuebloTheme.accent,
                                                    side: BorderSide(
                                                      color: BolaPuebloTheme
                                                          .accent
                                                          .withValues(
                                                              alpha: 0.55),
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 14),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                    ),
                                                  ),
                                                  onPressed: (aceptandoOfertaId !=
                                                              null ||
                                                          rechazandoOfertaId !=
                                                              null ||
                                                          retirandoOfertaId !=
                                                              null)
                                                      ? null
                                                      : () async {
                                                          final u = FirebaseAuth
                                                              .instance
                                                              .currentUser;
                                                          if (u == null) return;
                                                          await BolaPuebloDialogs
                                                              .enviarOferta(
                                                            context: sheetCtx,
                                                            bolaId: bolaId,
                                                            uid: u.uid,
                                                            nombre:
                                                                u.displayName ??
                                                                    'Conductor',
                                                            rol: 'taxista',
                                                            montoInicial: monto,
                                                          );
                                                          if (sheetCtx
                                                              .mounted) {
                                                            setModalState(
                                                                () {});
                                                          }
                                                        },
                                                  icon: const Icon(
                                                      Icons.swap_horiz_rounded,
                                                      size: 20),
                                                  label: const Text(
                                                      'Proponer otro monto'),
                                                ),
                                              ],
                                            ],
                                          )
                                        else
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        cc.onSurface.withValues(
                                                            alpha: cc.isDark
                                                                ? 0.08
                                                                : 0.06),
                                                    borderRadius:
                                                        BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    _etiquetaEstadoOferta(estado),
                                                    style: TextStyle(
                                                      color: cc.onMuted,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                if (estado == 'rechazada' &&
                                                    (m['motivoRechazo'] ?? '')
                                                        .toString()
                                                        .trim()
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Motivo: ${(m['motivoRechazo'] ?? '').toString().trim()}',
                                                    style: TextStyle(
                                                      color: cc.onMuted,
                                                      fontSize: 12,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> marcarEnCursoDialog(
      BuildContext context, String bolaId, String uidActor) async {
    try {
      final codigo = await BolaPuebloDialogs.pedirCodigoInicio(context);
      if (codigo == null || codigo.isEmpty) return;
      await BolaPuebloRepo.marcarEnCurso(
        bolaId: bolaId,
        uidActor: uidActor,
        codigoIngresado: codigo,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          BolaPuebloTheme.snack(context, 'Bola iniciada (en curso)'));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(BolaPuebloTheme.snack(context, '$e', error: true));
    }
  }

  static Future<void> confirmarFinalizacionDialog(
      BuildContext context, String bolaId, String uidActor) async {
    try {
      await BolaPuebloRepo.confirmarFinalizacion(
        bolaId: bolaId,
        uidActor: uidActor,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        BolaPuebloTheme.snack(
          context,
          'Confirmación registrada. Cuando cliente y taxista confirmen llegada, el viaje queda finalizado y se aplica la comisión RAI al conductor.',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(BolaPuebloTheme.snack(context, '$e', error: true));
    }
  }
}

/// Taxista en acordada: un solo listado (encuentro → abordo → código).
class BolaTaxistaAcordadaFlow extends StatefulWidget {
  const BolaTaxistaAcordadaFlow({
    super.key,
    required this.docId,
    required this.user,
    required this.origen,
    required this.destino,
    required this.pickupConfirmadoServidor,
    required this.uidPasajero,
    required this.tipoPublicacion,
    this.origenLat,
    this.origenLon,
    this.destinoLat,
    this.destinoLon,
  });

  final String docId;
  final User user;
  final String origen;
  final String destino;
  final bool pickupConfirmadoServidor;
  final String uidPasajero;

  /// `oferta` = el taxista publicó «Voy para»; el pasajero viene al [origen].
  final String tipoPublicacion;
  final double? origenLat;
  final double? origenLon;
  final double? destinoLat;
  final double? destinoLon;

  @override
  State<BolaTaxistaAcordadaFlow> createState() =>
      BolaTaxistaAcordadaFlowState();
}

class BolaTaxistaAcordadaFlowState extends State<BolaTaxistaAcordadaFlow>
    with WidgetsBindingObserver {
  late bool _pasoNavegacionListo;
  late bool _pasoAbordoListo;
  bool _busyAbordo = false;
  DateTime? _lastResumeSnackAt;

  static String _prefNavPickupBola(String docId) => 'bp_nav_pickup_$docId';

  Future<void> _persistNavPickupBola(bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (value) {
        await p.setBool(_prefNavPickupBola(widget.docId), true);
      } else {
        await p.remove(_prefNavPickupBola(widget.docId));
      }
    } catch (_) {}
  }

  Future<void> _restoreNavPickupBola({bool forceSnack = false}) async {
    if (!mounted || widget.pickupConfirmadoServidor) return;
    if (_pasoNavegacionListo) return;
    bool saved = false;
    try {
      final p = await SharedPreferences.getInstance();
      saved = p.getBool(_prefNavPickupBola(widget.docId)) ?? false;
    } catch (_) {
      return;
    }
    if (!mounted || !saved) return;
    setState(() => _pasoNavegacionListo = true);
    final now = DateTime.now();
    if (!forceSnack &&
        _lastResumeSnackAt != null &&
        now.difference(_lastResumeSnackAt!) < const Duration(seconds: 6)) {
      return;
    }
    _lastResumeSnackAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      BolaPuebloTheme.snack(
        context,
        'Volviste a RAI Driver. Continúa con "Subió el cliente" y luego el código.',
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.pickupConfirmadoServidor) {
      _pasoNavegacionListo = true;
      _pasoAbordoListo = true;
    } else {
      _pasoNavegacionListo = false;
      _pasoAbordoListo = false;
      unawaited(_restoreNavPickupBola());
    }
  }

  @override
  void didUpdateWidget(covariant BolaTaxistaAcordadaFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pickupConfirmadoServidor && !_pasoAbordoListo) {
      unawaited(_persistNavPickupBola(false));
      setState(() {
        _pasoNavegacionListo = true;
        _pasoAbordoListo = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_restoreNavPickupBola(forceSnack: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _resumenPasoProfesional(BolaPuebloColors c) {
    final String titulo;
    final String detalle;
    final IconData icono;
    final Color color;
    if (!_pasoNavegacionListo) {
      titulo = 'Paso actual: encuentro con el pasajero';
      detalle = 'Abre Waze/Maps y al llegar marca "Llegué al punto".';
      icono = Icons.navigation_rounded;
      color = BolaPuebloTheme.accent;
    } else if (!_pasoAbordoListo) {
      titulo = 'Paso actual: confirmar abordo';
      detalle = 'Cuando suba el pasajero, toca "Subió el cliente".';
      icono = Icons.person_add_alt_1_rounded;
      color = Colors.tealAccent.shade400;
    } else {
      titulo = 'Paso actual: validar código de salida';
      detalle = 'Pide el PIN al pasajero y comienza la ruta al destino.';
      icono = Icons.pin_rounded;
      color = Colors.amberAccent;
    }
    return Container(
      key: ValueKey<String>('bp_step_$titulo'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: c.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(color: c.onMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(BolaPuebloUi.radiusCard),
        border: Border.all(color: c.outlineSoft.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Con tu pasajero',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Encuentro → sube el pasajero → código para salir.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.onMuted, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: _resumenPasoProfesional(c),
              ),
              const SizedBox(height: 18),
              if (!_pasoNavegacionListo) ...[
                // — 1 Encuentro —
                _bolaPasoTitulo(
                  c,
                  '1',
                  'Vas a buscar al pasajero',
                ),
                const SizedBox(height: 10),
                Text(
                  'Abrí Maps o Waze hasta el punto de encuentro del pasajero.',
                  style:
                      TextStyle(color: c.onMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: BolaPuebloUi.filledPrimary,
                  onPressed: () async {
                    final ok =
                        await BolaPuebloNav.abrirSelectorNavegacionSoloRecogida(
                      context,
                      recogida: widget.origen,
                      recogidaLat: widget.origenLat,
                      recogidaLon: widget.origenLon,
                    );
                    if (!mounted) return;
                    if (ok) {
                      unawaited(_persistNavPickupBola(true));
                      setState(() => _pasoNavegacionListo = true);
                    }
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 22),
                  label: const Text('Ir a recoger al cliente'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: BolaPuebloUi.outlineAccent(context),
                  onPressed: () {
                    unawaited(_persistNavPickupBola(true));
                    setState(() => _pasoNavegacionListo = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      BolaPuebloTheme.snack(
                        context,
                        'Punto marcado. Cuando el cliente suba, toca "Subió el cliente".',
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 21),
                  label: const Text('Llegué al punto'),
                ),
                const SizedBox(height: 12),
                Theme(
                  data:
                      Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Contactar al pasajero',
                      style: TextStyle(
                        color: c.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      'Llamada, WhatsApp o chat',
                      style: TextStyle(color: c.onMuted, fontSize: 11.5),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: BolaPuebloContrapartePanel(
                          bolaId: widget.docId,
                          counterpartyUid: widget.uidPasajero,
                          sectionTitle: 'Tu pasajero',
                          vistaChofer: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!_pasoAbordoListo) ...[
                // — 2 Abordo —
                _bolaPasoTitulo(c, '2', 'Pasajero a bordo'),
                const SizedBox(height: 10),
                Text(
                  'Cuando suba, confirmá abordo para habilitar el código.',
                  style:
                      TextStyle(color: c.onMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: BolaPuebloUi.filledSecondary,
                  onPressed: _busyAbordo
                      ? null
                      : () async {
                          setState(() => _busyAbordo = true);
                          try {
                            await BolaPuebloRepo.marcarPickupClienteAbordo(
                              bolaId: widget.docId,
                              uidTaxista: widget.user.uid,
                            );
                            if (!mounted || !context.mounted) return;
                            unawaited(_persistNavPickupBola(false));
                            setState(() {
                              _pasoAbordoListo = true;
                              _busyAbordo = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              BolaPuebloTheme.snack(
                                context,
                                'Pedí el código al pasajero.',
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setState(() => _busyAbordo = false);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              BolaPuebloTheme.snack(
                                context,
                                _mensajeErrorAbordo(e),
                                error: true,
                              ),
                            );
                          }
                        },
                  icon: _busyAbordo
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(
                    _busyAbordo ? 'Guardando…' : 'Subió el cliente',
                    textAlign: TextAlign.center,
                  ),
                ),
              ] else ...[
                // — 3 Código —
                _bolaPasoTitulo(c, '3', 'Iniciar viaje'),
                const SizedBox(height: 10),
                Text(
                  'El pasajero te dicta el código que ve en su pantalla.',
                  style:
                      TextStyle(color: c.onMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: BolaPuebloUi.filledPrimary,
                  onPressed: () => BolaPuebloDialogs.marcarEnCursoDialog(
                    context,
                    widget.docId,
                    widget.user.uid,
                  ),
                  icon: const Icon(Icons.pin_rounded, size: 22),
                  label: const Text(
                    'Iniciar viaje con código',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: BolaPuebloUi.outlineLink(context),
                  onPressed: () => BolaPuebloNav.abrirSelectorNavegacion(
                    context,
                    origen: widget.origen,
                    destino: widget.destino,
                    origenLat: widget.origenLat,
                    origenLon: widget.origenLon,
                    destinoLat: widget.destinoLat,
                    destinoLon: widget.destinoLon,
                  ),
                  icon: Icon(Icons.alt_route_rounded,
                      size: 20, color: c.linkBlue),
                  label: const Text('Ver ruta origen → destino'),
                ),
              ],
              if (!widget.pickupConfirmadoServidor) ...[
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        BolaPuebloDialogs.confirmarCancelarAcuerdoBola(
                      context: context,
                      bolaId: widget.docId,
                      uid: widget.user.uid,
                    ),
                    child: Text(
                      'Cancelar acuerdo',
                      style: TextStyle(
                        color: c.onMuted,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: c.onMuted.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bolaPasoTitulo(BolaPuebloColors c, String n, String titulo) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: BolaPuebloTheme.accent.withValues(alpha: 0.2),
          child: Text(
            n,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: BolaPuebloTheme.accent,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            titulo,
            style: TextStyle(
              color: c.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
            ),
          ),
        ),
      ],
    );
  }

  String _mensajeErrorAbordo(Object e) {
    final raw = e.toString();
    final msg = raw.replaceFirst('Exception:', '').trim().toLowerCase();
    if (msg.contains('solo el taxista asignado')) {
      return 'Solo el taxista asignado puede confirmar abordo.';
    }
    if (msg.contains('acuerdo está pendiente') ||
        msg.contains('solo aplica mientras')) {
      return 'Este paso solo aplica cuando la bola está acordada.';
    }
    if (msg.contains('publicación no encontrada')) {
      return 'No se encontró la bola. Reabre el viaje e intenta otra vez.';
    }
    if (msg.contains('permission-denied') || msg.contains('insufficient')) {
      return 'No se pudo guardar abordo por permisos. Intenta nuevamente.';
    }
    return 'No se pudo confirmar abordo. Revisa conexión e intenta otra vez.';
  }
}

/// Botones Maps/Waze para el cliente en acordada (misma lógica en tablero y modo viaje).
class BolaPuebloClienteMapsAcordada extends StatelessWidget {
  const BolaPuebloClienteMapsAcordada({
    super.key,
    required this.origen,
    required this.tipo,
    this.origenLat,
    this.origenLon,
  });

  final String origen;
  final String tipo;
  final double? origenLat;
  final double? origenLon;

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    final fgMuted = c.onMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BolaPuebloUi.sectionLabel(context, 'Maps / Waze'),
        const SizedBox(height: 8),
        BolaPuebloUi.actionPanel(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'El taxista va hacia tu punto de encuentro.',
                style: TextStyle(color: fgMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Esperá en el lugar acordado y usa contacto si necesitás coordinar.',
                style: TextStyle(color: fgMuted, fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cliente en acordada: código y conductor en una sola vista.
class BolaClienteAcordadaCapas extends StatelessWidget {
  const BolaClienteAcordadaCapas({
    super.key,
    required this.bolaId,
    required this.uidConductor,
    required this.codigoBola,
    required this.codigoGeneradoEn,
    required this.pickupConfirmadoTaxista,
    required this.user,
    required this.fg,
    required this.fgMuted,
    required this.esClienteVaHaciaConductor,
  });

  final String bolaId;
  final String uidConductor;
  final String codigoBola;
  final dynamic codigoGeneradoEn;
  final bool pickupConfirmadoTaxista;
  final User user;
  final Color fg;
  final Color fgMuted;

  /// Publicación tipo [oferta]: vos vas al punto donde el conductor dijo que está.
  final bool esClienteVaHaciaConductor;

  @override
  Widget build(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(BolaPuebloUi.radiusCard),
        border: Border.all(color: c.outlineSoft.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!pickupConfirmadoTaxista) ...[
              Text(
                'Esperando abordo',
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cuando subas, el conductor te pedirá el código.',
                style: TextStyle(color: fgMuted, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 18),
            ] else ...[
              Text(
                'Tu código',
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Dictalo ahora para iniciar el viaje.',
                style: TextStyle(color: fgMuted, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: BolaPuebloTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: BolaPuebloTheme.accent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      codigoBola.isEmpty ? '—' : codigoBola,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: fg,
                        fontSize: 32,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BolaPuebloFormat.textoVigenciaCodigo(codigoGeneradoEn),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: fgMuted, fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'El conductor marcó que ya estás a bordo.',
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
            ],
            BolaPuebloUi.sectionLabel(context, 'Tu conductor'),
            const SizedBox(height: 8),
            BolaPuebloContrapartePanel(
              bolaId: bolaId,
              counterpartyUid: uidConductor,
              sectionTitle: 'Contacto',
              vistaChofer: false,
            ),
            const SizedBox(height: 12),
            Text(
              'Paso actual: esperar recogida y subir.',
              style: TextStyle(
                color: fgMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (!pickupConfirmadoTaxista) ...[
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () =>
                      BolaPuebloDialogs.confirmarCancelarAcuerdoBola(
                    context: context,
                    bolaId: bolaId,
                    uid: user.uid,
                  ),
                  child: Text(
                    'Cancelar acuerdo',
                    style: TextStyle(
                      color: fgMuted,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: fgMuted.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Contraofertas del pasajero dirigidas a este conductor (pedido en tablero).
class BolaPuebloContraofertasInbound extends StatefulWidget {
  const BolaPuebloContraofertasInbound({
    super.key,
    required this.bolaId,
    required this.uidTaxista,
  });

  final String bolaId;
  final String uidTaxista;

  @override
  State<BolaPuebloContraofertasInbound> createState() =>
      _BolaPuebloContraofertasInboundState();
}

class _BolaPuebloContraofertasInboundState
    extends State<BolaPuebloContraofertasInbound> {
  /// `rej:docId` | `acc:docId`
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final cs = BolaPuebloColors.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: BolaPuebloRepo.streamOfertas(widget.bolaId),
      builder: (context, snap) {
        final raw = snap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final items = raw.where((d) {
          final m = d.data();
          if (m['esContraofertaCliente'] != true) return false;
          if ((m['contraOfertaParaUid'] ?? '').toString() != widget.uidTaxista) {
            return false;
          }
          if ((m['estado'] ?? '').toString() != 'pendiente') return false;
          return true;
        }).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BolaPuebloUi.sectionLabel(context, 'Te propusieron otro monto'),
            const SizedBox(height: 6),
            Text(
              'El pasajero envió una contraoferta. Podés aceptarla para cerrar al precio que indica, o rechazarla y seguir negociando.',
              style: TextStyle(color: cs.onMuted, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 10),
            ...items.map((d) {
              final m = d.data();
              final nombre = (m['fromNombre'] ?? 'Pasajero').toString();
              final monto = ((m['montoRd'] ?? 0) as num).toDouble();
              final msg = (m['mensaje'] ?? '').toString();
              final rejBusy = _busy == 'rej:${d.id}';
              final accBusy = _busy == 'acc:${d.id}';
              final anyBusy = _busy != null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: cs.surfaceRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color: cs.outlineSoft.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          nombre,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'RD\$${monto.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: BolaPuebloTheme.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        if (msg.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            msg,
                            style: TextStyle(
                                color: cs.onMuted, fontSize: 13, height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cs.onSurface,
                                  side: BorderSide(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.35)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: anyBusy && !rejBusy
                                    ? null
                                    : () async {
                                        setState(() => _busy = 'rej:${d.id}');
                                        try {
                                          final motivo = await BolaPuebloDialogs
                                              .pedirMotivoRechazoContraoferta(
                                                  context);
                                          if (motivo == null) return;
                                          await BolaPuebloRepo
                                              .rechazarContraofertaClienteBola(
                                            bolaId: widget.bolaId,
                                            ofertaId: d.id,
                                            motivo: motivo,
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            BolaPuebloTheme.snack(context,
                                                'Contraoferta rechazada'),
                                          );
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              BolaPuebloTheme.snack(
                                                  context, '$e',
                                                  error: true),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _busy = null);
                                          }
                                        }
                                      },
                                child: rejBusy
                                    ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.onSurface
                                              .withValues(alpha: 0.8),
                                        ),
                                      )
                                    : const Text('Rechazar'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: BolaPuebloTheme.accent,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: anyBusy && !accBusy
                                    ? null
                                    : () async {
                                        setState(() => _busy = 'acc:${d.id}');
                                        try {
                                          await BolaPuebloRepo
                                              .aceptarContraofertaClienteBola(
                                            bolaId: widget.bolaId,
                                            ofertaId: d.id,
                                          );
                                          if (!context.mounted) return;
                                          await BolaPuebloDialogs
                                              .mostrarPostAceptarOfertaDialog(
                                                  context);
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              BolaPuebloTheme.snack(
                                                  context, '$e',
                                                  error: true),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _busy = null);
                                          }
                                        }
                                      },
                                child: accBusy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Aceptar monto'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

/// Notifica al ofertante en vivo cuando el publicador descarta su propuesta (pendiente → rechazada).
class BolaPuebloOfertaDescartadaListener extends StatefulWidget {
  const BolaPuebloOfertaDescartadaListener({
    super.key,
    required this.bolaId,
    required this.miUid,
    required this.activo,
  });

  final String bolaId;
  final String miUid;
  final bool activo;

  @override
  State<BolaPuebloOfertaDescartadaListener> createState() =>
      _BolaPuebloOfertaDescartadaListenerState();
}

class _BolaPuebloOfertaDescartadaListenerState
    extends State<BolaPuebloOfertaDescartadaListener> {
  final Map<String, String> _ultimoEstadoPorOferta = <String, String>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.activo) _suscribir();
  }

  @override
  void didUpdateWidget(covariant BolaPuebloOfertaDescartadaListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bolaId != widget.bolaId || oldWidget.miUid != widget.miUid) {
      _sub?.cancel();
      _sub = null;
      _ultimoEstadoPorOferta.clear();
      if (widget.activo) _suscribir();
      return;
    }
    if (oldWidget.activo != widget.activo) {
      if (widget.activo) {
        _ultimoEstadoPorOferta.clear();
        _suscribir();
      } else {
        _sub?.cancel();
        _sub = null;
      }
    }
  }

  void _suscribir() {
    _sub?.cancel();
    _sub = BolaPuebloRepo.streamOfertas(widget.bolaId).listen((snap) {
      if (!mounted) return;
      for (final d in snap.docs) {
        final m = d.data();
        if ((m['fromUid'] ?? '').toString() != widget.miUid) continue;
        final e = (m['estado'] ?? '').toString();
        final prev = _ultimoEstadoPorOferta[d.id];
        _ultimoEstadoPorOferta[d.id] = e;
        if (prev == 'pendiente' && e == 'rechazada') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              BolaPuebloTheme.snack(
                context,
                'Descartaron tu propuesta. Podés enviar otra desde esta tarjeta.',
              ),
            );
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Tarjeta de una publicación (misma lógica en pantalla Bola y pestaña taxista).
class BolaPuebloPublicacionCard extends StatelessWidget {
  const BolaPuebloPublicacionCard({
    super.key,
    required this.docId,
    required this.data,
    required this.user,
    required this.nombre,
    required this.rol,
    this.onVerRutaEnMapa,

    /// Taxista en pestaña «Viajes disponibles»: alineado con pool (AHORA/PROGRAMADOS).
    this.puedeOperarEnPool = true,

    /// Abre pantalla completa mapa + pasos (padre hace [Navigator.push]).
    this.onAbrirModoViaje,
  });

  final String docId;
  final Map<String, dynamic> data;
  final User user;
  final String nombre;
  final String rol;

  /// Si la publicación guardó coordenadas (Places), el padre puede centrar mapa + polyline.
  final VoidCallback? onVerRutaEnMapa;
  final bool puedeOperarEnPool;
  final void Function(String bolaId)? onAbrirModoViaje;

  @override
  Widget build(BuildContext context) {
    final ownerUid = (data['createdByUid'] ?? '').toString();
    final owner = (data['createdByNombre'] ?? 'Usuario').toString();
    final tipo = (data['tipo'] ?? '').toString();
    final origen = (data['origen'] ?? '').toString();
    final destino = (data['destino'] ?? '').toString();
    final fecha = BolaPuebloFormat.fmtTs(data['fechaSalida']);
    final monto = ((data['montoSugeridoRd'] ?? 0) as num).toDouble();
    final nota = (data['nota'] ?? '').toString();
    final esMio = ownerUid == user.uid;
    final estado = (data['estado'] ?? '').toString();
    final uidTaxista = (data['uidTaxista'] ?? '').toString();
    final uidCliente = (data['uidCliente'] ?? '').toString();
    final bool soyTaxistaAsignado = uidTaxista == user.uid;
    final bool soyClienteAsignado = uidCliente == user.uid;
    final double comisionRd = ((data['comisionRd'] ?? 0) as num).toDouble();
    final double netoChofer =
        ((data['gananciaNetaChoferRd'] ?? 0) as num).toDouble();
    final double montoAcordadoRd =
        ((data['montoAcordadoRd'] ?? 0) as num).toDouble();
    final bool confTax = data['confirmacionTaxistaFinal'] == true;
    final bool confCli = data['confirmacionClienteFinal'] == true;
    final bool codigoVerificado = data['codigoVerificado'] == true;
    final bool pickupConfirmadoTaxista =
        data['pickupConfirmadoTaxista'] == true;
    final String codigoBola = (data['codigoVerificacionBola'] ?? '').toString();
    final dynamic codigoGeneradoEn = data['codigoGeneradoEn'];
    final double tarifaNormalRd =
        ((data['tarifaNormalRd'] ?? 0) as num).toDouble();
    final double tarifaBaseBolaRd =
        ((data['tarifaBaseBolaRd'] ?? monto) as num).toDouble();
    final double ofertaMinRd = ((data['ofertaMinRd'] ?? 0) as num).toDouble();
    final double ofertaMaxRd = ((data['ofertaMaxRd'] ?? 0) as num).toDouble();

    /// Si el doc no trae monto sugerido, el diálogo debe abrir con cifra válida (evita 0 o default 1500 fuera de rango).
    final double montoSemillaOferta = monto > 0
        ? monto
        : (ofertaMinRd > 0 && ofertaMaxRd >= ofertaMinRd
            ? ((ofertaMinRd + ofertaMaxRd) / 2).clamp(ofertaMinRd, ofertaMaxRd)
            : (tarifaBaseBolaRd > 0
                ? tarifaBaseBolaRd
                : (tarifaNormalRd > 0 ? tarifaNormalRd : monto)));
    final double distanciaKm = ((data['distanciaKm'] ?? 0) as num).toDouble();
    final int pasajeros = ((data['pasajeros'] ?? 1) as num).toInt().clamp(1, 8);
    final double? origenLatBola =
        (data['origenLat'] is num) ? (data['origenLat'] as num).toDouble() : null;
    final double? origenLonBola =
        (data['origenLon'] is num) ? (data['origenLon'] as num).toDouble() : null;
    final double? destinoLatBola =
        (data['destinoLat'] is num) ? (data['destinoLat'] as num).toDouble() : null;
    final double? destinoLonBola =
        (data['destinoLon'] is num) ? (data['destinoLon'] as num).toDouble() : null;

    final c = BolaPuebloColors.of(context);
    final Color cardBg = c.surface;
    final Color fg = c.onSurface;
    final Color fgMuted = c.onMuted;
    final bool esPedido = tipo == 'pedido';

    final Color badgePedidoBg = c.isDark
        ? const Color(0xFFFF8F00).withValues(alpha: 0.24)
        : const Color(0xFFFFA000).withValues(alpha: 0.18);
    final Color badgePedidoFg =
        c.isDark ? const Color(0xFFFFE082) : const Color(0xFFBF360C);
    final Color badgeOfertaBg = c.isDark
        ? const Color(0xFF00C853).withValues(alpha: 0.24)
        : const Color(0xFF2E7D32).withValues(alpha: 0.16);
    final Color badgeOfertaFg =
        c.isDark ? const Color(0xFF69F0AE) : const Color(0xFF1B5E20);
    final Color tipoStrong = esPedido
        ? (c.isDark ? const Color(0xFFFFB300) : const Color(0xFFF57C00))
        : (c.isDark ? const Color(0xFF00E676) : const Color(0xFF2E7D32));
    final Color bordeTipoColor = esPedido
        ? (c.isDark ? const Color(0xFFFFC107) : const Color(0xFFEF6C00))
        : (c.isDark ? const Color(0xFF00E676) : const Color(0xFF2E7D32));
    final Color tipoChipBg = esPedido
        ? (c.isDark
            ? const Color(0xFF5D3A00).withValues(alpha: 0.52)
            : const Color(0xFFFFF3E0))
        : (c.isDark
            ? const Color(0xFF00391E).withValues(alpha: 0.56)
            : const Color(0xFFE8F5E9));
    final Color tipoChipFg = esPedido
        ? (c.isDark ? const Color(0xFFFFE082) : const Color(0xFFBF360C))
        : (c.isDark ? const Color(0xFFB9F6CA) : const Color(0xFF1B5E20));
    final String tipoEtiqueta = esPedido ? 'PIDE BOLA' : 'VOY PARA';
    final IconData tipoIcon = esPedido
        ? Icons.person_pin_circle_rounded
        : Icons.directions_car_filled_rounded;
    final bool ocultarNavRutaClienteEnAcordada =
        estado == 'acordada' && soyClienteAsignado;
    final bool partActivo = soyTaxistaAsignado || soyClienteAsignado;
    final bool esTaxistaRol = rol == 'taxista' || rol == 'driver';
    final bool bloqueadoOperacionBola = esTaxistaRol && !puedeOperarEnPool;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(BolaPuebloUi.radiusCard),
        border: Border.all(
          color: bordeTipoColor.withValues(alpha: c.isDark ? 0.9 : 0.78),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: c.cardShadow,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: tipoStrong,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            if (estado == 'abierta' && !esMio)
              BolaPuebloOfertaDescartadaListener(
                bolaId: docId,
                miUid: user.uid,
                activo: true,
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: esPedido ? badgePedidoBg : badgeOfertaBg,
                    borderRadius:
                        BorderRadius.circular(BolaPuebloUi.radiusSmall),
                  ),
                  child: Text(
                    esPedido ? 'Pedido' : 'Oferta',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.45,
                      color: esPedido ? badgePedidoFg : badgeOfertaFg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: tipoChipBg,
                    borderRadius:
                        BorderRadius.circular(BolaPuebloUi.radiusSmall),
                    border:
                        Border.all(color: tipoStrong.withValues(alpha: 0.55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tipoIcon, size: 14, color: tipoChipFg),
                      const SizedBox(width: 5),
                      Text(
                        tipoEtiqueta,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.55,
                          color: tipoChipFg,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: fgMuted.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    estado.toUpperCase(),
                    style: TextStyle(
                      color: fgMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.65,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            BolaPuebloUi.routeBlock(
              context,
              origen: origen,
              destino: destino,
              origenLabel: 'ESTOY EN',
              destinoLabel: esPedido ? 'NECESITO IR A' : 'VOY PARA',
              origenIconColor: tipoStrong,
              destinoIconColor: tipoStrong,
            ),
            if (onVerRutaEnMapa != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: BolaPuebloUi.outlineLink(context),
                  onPressed: onVerRutaEnMapa,
                  icon: Icon(Icons.map_rounded, size: 20, color: c.linkBlue),
                  label: const Text('Ver en mapa (vista previa)'),
                ),
              ),
            ],
            if (estado == 'abierta') ...[
              const SizedBox(height: 8),
              BolaPuebloUi.sectionLabel(context, 'Precio y negociación'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BolaPuebloTheme.accent
                      .withValues(alpha: c.isDark ? 0.1 : 0.08),
                  borderRadius: BorderRadius.circular(BolaPuebloUi.radiusSmall),
                  border: Border.all(
                      color: BolaPuebloTheme.accent.withValues(alpha: 0.32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tipo == 'pedido'
                          ? 'Oferta inicial (pasajero)'
                          : 'Precio de referencia (conductor)',
                      style: TextStyle(
                        color: fgMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.85,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RD\$${monto.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: fg,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if ((monto - tarifaBaseBolaRd).abs() > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Sugerida sistema: RD\$${tarifaBaseBolaRd.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: fgMuted, fontSize: 12, height: 1.3),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Rango para ofertar: RD\$${ofertaMinRd.toStringAsFixed(0)} – RD\$${ofertaMaxRd.toStringAsFixed(0)} · '
                      'Tarifa mercado ref.: RD\$${tarifaNormalRd.toStringAsFixed(0)}',
                      style: TextStyle(
                          color: fgMuted,
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      esMio
                          ? (tipo == 'pedido'
                              ? 'Recibís propuestas dentro del rango. Abrí «Ver ofertas y aceptar» las veces que quieras; '
                                  'cuando toques Aceptar en una fila, queda el precio cerrado y el viaje sigue en esta tarjeta.'
                              : 'Recibís propuestas de pago dentro del rango. Revisalas en «Ver ofertas y aceptar»; '
                                  'al aceptar una, cerrás el precio y el traslado continúa aquí (código, navegación, finalizar).')
                          : (tipo == 'pedido'
                              ? 'Proponé montos dentro del rango; si cambiás de idea, enviá otra oferta (solo cuenta la última pendiente tuya). '
                                  'Quien publicó el pedido elige una y acepta para cerrar.'
                              : 'Proponé cuánto pagarías dentro del rango; podés reenviar otra cifra si ajustás (solo se muestra tu última pendiente). '
                                  'El conductor publicador acepta una propuesta para cerrar.'),
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.9),
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: fgMuted.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 18, color: fgMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Chat, llamada y WhatsApp con la otra parte están disponibles recién cuando el precio queda acordado (después de Aceptar una oferta), no mientras negociás montos. '
                              'El pago del trayecto lo coordinan ustedes; al finalizar el traslado en la app se registra la comisión RAI sobre el monto acordado.',
                              style: TextStyle(
                                  color: fgMuted, fontSize: 11.5, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: esMio,
                  title: Text(
                    'Detalles del viaje',
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '$pasajeros ${pasajeros == 1 ? 'pasajero' : 'pasajeros'} · $fecha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fgMuted, fontSize: 12),
                  ),
                  children: [
                    BolaPuebloUi.metaRow(
                      context,
                      icon: Icons.people_outline_rounded,
                      text: pasajeros == 1
                          ? '1 pasajero'
                          : '$pasajeros pasajeros',
                    ),
                    BolaPuebloUi.metaRow(context,
                        icon: Icons.schedule_rounded, text: 'Salida: $fecha'),
                    if (distanciaKm > 0)
                      BolaPuebloUi.metaRow(
                        context,
                        icon: Icons.straighten_rounded,
                        text:
                            'Distancia estimada: ${distanciaKm.toStringAsFixed(1)} km',
                      ),
                    BolaPuebloUi.metaRow(
                      context,
                      icon: Icons.person_outline_rounded,
                      text: 'Publica: $owner',
                      emphasize: true,
                    ),
                    if (nota.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      BolaPuebloUi.sectionLabel(context, 'Nota'),
                      Text(nota,
                          style: TextStyle(
                              color: fgMuted, fontSize: 13, height: 1.4)),
                    ],
                  ],
                ),
              ),
              if (esMio) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: BolaPuebloUi.filledPrimary,
                    onPressed: bloqueadoOperacionBola
                        ? null
                        : () => BolaPuebloDialogs.verOfertasSheet(
                              context,
                              docId,
                              tipoPublicacion: tipo,
                              ofertaMinRd: ofertaMinRd,
                              ofertaMaxRd: ofertaMaxRd,
                            ),
                    icon: const Icon(Icons.forum_rounded, size: 22),
                    label: Text(
                      bloqueadoOperacionBola
                          ? 'Activa disponibilidad'
                          : 'Ver ofertas y aceptar',
                    ),
                  ),
                ),
              ],
            ],
            if ((estado == 'acordada' || estado == 'en_curso') &&
                partActivo) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: fgMuted.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(BolaPuebloUi.radiusSmall),
                  border:
                      Border.all(color: c.outlineSoft.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Acuerdo',
                      style: TextStyle(
                        color: fgMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.85,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (soyTaxistaAsignado)
                      Text(
                        'Total RD\$${(montoAcordadoRd > 0 ? montoAcordadoRd : monto).toStringAsFixed(2)} · '
                        'Tu neto RD\$${netoChofer.toStringAsFixed(2)} · RAI RD\$${comisionRd.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: fg,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      )
                    else
                      Text(
                        'Monto acordado RD\$${(montoAcordadoRd > 0 ? montoAcordadoRd : monto).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (onAbrirModoViaje != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: BolaPuebloUi.filledPrimary,
                    onPressed: () => onAbrirModoViaje!(docId),
                    icon: const Icon(Icons.explore_rounded, size: 22),
                    label: Text(
                      estado == 'en_curso'
                          ? 'Modo viaje: mapa y confirmaciones'
                          : 'Modo viaje: mapa y pasos',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (soyTaxistaAsignado && estado == 'acordada') ...[
              BolaTaxistaAcordadaFlow(
                docId: docId,
                user: user,
                origen: origen,
                destino: destino,
                pickupConfirmadoServidor: pickupConfirmadoTaxista,
                uidPasajero: uidCliente,
                tipoPublicacion: tipo,
                origenLat: origenLatBola,
                origenLon: origenLonBola,
                destinoLat: destinoLatBola,
                destinoLon: destinoLonBola,
              ),
              const SizedBox(height: 14),
            ],
            if (soyClienteAsignado && estado == 'acordada') ...[
              BolaPuebloClienteMapsAcordada(
                origen: origen,
                tipo: tipo,
                origenLat: origenLatBola,
                origenLon: origenLonBola,
              ),
              const SizedBox(height: 14),
              BolaClienteAcordadaCapas(
                bolaId: docId,
                uidConductor: uidTaxista,
                codigoBola: codigoBola,
                codigoGeneradoEn: codigoGeneradoEn,
                pickupConfirmadoTaxista: pickupConfirmadoTaxista,
                user: user,
                fg: fg,
                fgMuted: fgMuted,
                esClienteVaHaciaConductor: tipo == 'oferta',
              ),
              const SizedBox(height: 14),
            ],
            if (estado == 'en_curso' && partActivo) ...[
              BolaPuebloContrapartePanel(
                bolaId: docId,
                counterpartyUid: soyClienteAsignado ? uidTaxista : uidCliente,
                sectionTitle:
                    soyClienteAsignado ? 'Tu conductor' : 'Tu pasajero',
                vistaChofer: soyTaxistaAsignado,
              ),
              const SizedBox(height: 14),
              BolaPuebloUi.sectionLabel(context, 'Navegar al destino'),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: BolaPuebloUi.filledSecondary,
                  onPressed: destino.trim().isEmpty
                      ? null
                      : () => BolaPuebloNav.abrirSelectorSoloDestino(
                            context,
                            destinoLabel: destino,
                            destinoLat: destinoLatBola,
                            destinoLon: destinoLonBola,
                          ),
                  icon: const Icon(Icons.flag_outlined, size: 22),
                  label: const Text('Ir al destino del viaje (Maps / Waze)'),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (estado == 'en_curso' && partActivo) ...[
              BolaPuebloUi.sectionLabel(context, 'Estado del traslado'),
              BolaPuebloUi.metaRow(
                context,
                icon: Icons.verified_outlined,
                text:
                    'Código: ${codigoVerificado ? 'verificado' : 'pendiente'}',
              ),
              BolaPuebloUi.metaRow(
                context,
                icon: Icons.local_taxi_outlined,
                text:
                    'Conductor: ${confTax ? 'confirmó llegada' : 'pendiente'}',
              ),
              BolaPuebloUi.metaRow(
                context,
                icon: Icons.person_pin_outlined,
                text: 'Cliente: ${confCli ? 'confirmó llegada' : 'pendiente'}',
              ),
              const SizedBox(height: 12),
            ],
            if ((estado == 'acordada' || estado == 'en_curso') &&
                !(soyTaxistaAsignado && estado == 'acordada') &&
                !ocultarNavRutaClienteEnAcordada) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: BolaPuebloUi.outlineAccent(context),
                  onPressed: () => BolaPuebloNav.abrirSelectorNavegacion(
                    context,
                    origen: origen,
                    destino: destino,
                    origenLat: origenLatBola,
                    origenLon: origenLonBola,
                    destinoLat: destinoLatBola,
                    destinoLon: destinoLonBola,
                  ),
                  icon: const Icon(Icons.navigation_rounded, size: 21),
                  label: const Text('Navegar ruta completa'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (partActivo && estado == 'en_curso') ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: BolaPuebloUi.filledPrimary,
                  onPressed: () =>
                      BolaPuebloDialogs.confirmarFinalizacionDialog(
                          context, docId, user.uid),
                  icon: const Icon(Icons.flag_rounded, size: 22),
                  label: Text(
                    soyTaxistaAsignado
                        ? 'Confirmar llegada al destino'
                        : 'Confirmar que llegamos',
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if ((estado == 'acordada' || estado == 'en_curso') &&
                partActivo) ...[
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: false,
                  title: Text(
                    'Más detalles del viaje',
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '$owner · $fecha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fgMuted, fontSize: 12),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BolaPuebloUi.routeBlock(context,
                              origen: origen, destino: destino),
                          const SizedBox(height: 10),
                          BolaPuebloUi.metaRow(
                            context,
                            icon: Icons.people_outline_rounded,
                            text: pasajeros == 1
                                ? '1 pasajero'
                                : '$pasajeros pasajeros',
                          ),
                          BolaPuebloUi.metaRow(context,
                              icon: Icons.schedule_rounded,
                              text: 'Salida: $fecha'),
                          if (distanciaKm > 0)
                            BolaPuebloUi.metaRow(
                              context,
                              icon: Icons.straighten_rounded,
                              text:
                                  'Distancia estimada: ${distanciaKm.toStringAsFixed(1)} km',
                            ),
                          BolaPuebloUi.metaRow(
                            context,
                            icon: Icons.person_outline_rounded,
                            text: 'Publica: $owner',
                            emphasize: true,
                          ),
                          if (soyTaxistaAsignado) ...[
                            const SizedBox(height: 8),
                            BolaPuebloUi.metaRow(
                              context,
                              icon: Icons.percent_rounded,
                              text:
                                  'Comisión RAI (10%): RD\$${comisionRd.toStringAsFixed(2)}',
                            ),
                            BolaPuebloUi.metaRow(
                              context,
                              icon: Icons.account_balance_wallet_outlined,
                              text:
                                  'Neto conductor: RD\$${netoChofer.toStringAsFixed(2)}',
                              emphasize: true,
                            ),
                          ],
                          if (nota.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            BolaPuebloUi.sectionLabel(context, 'Nota'),
                            Text(nota,
                                style: TextStyle(
                                    color: fgMuted, fontSize: 13, height: 1.4)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (estado == 'abierta' && !esMio) ...[
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (bloqueadoOperacionBola) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 152, 0, 0.12),
                        borderRadius:
                            BorderRadius.circular(BolaPuebloUi.radiusSmall),
                        border: Border.all(
                          color: const Color.fromRGBO(255, 152, 0, 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 20, color: fgMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No disponible para operar en Bola: activá tu disponibilidad como en el pool de viajes.',
                              style: TextStyle(
                                color: fgMuted,
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (tipo == 'pedido' && (rol == 'taxista' || rol == 'driver'))
                    IgnorePointer(
                      ignoring: bloqueadoOperacionBola,
                      child: Opacity(
                        opacity: bloqueadoOperacionBola ? 0.45 : 1,
                        child: BolaPuebloContraofertasInbound(
                          bolaId: docId,
                          uidTaxista: user.uid,
                        ),
                      ),
                    ),
                  if (tipo == 'pedido' && (rol == 'taxista' || rol == 'driver'))
                    const SizedBox(height: 12),
                  Text(
                    'Referencia RD\$${monto.toStringAsFixed(0)}. Podés enviar esa cifra u otra dentro del rango; '
                    'si ajustás, mandá otra oferta (solo cuenta tu última pendiente). '
                    '${tipo == 'pedido' ? 'El pasajero' : 'El conductor'} cierra el precio en «Ver ofertas y aceptar» y el viaje sigue en esta bola.',
                    style: TextStyle(
                        color: fgMuted,
                        fontSize: 12.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  BolaPuebloUi.sectionLabel(context, 'Tu propuesta'),
                  FilledButton(
                    style: BolaPuebloUi.filledPrimary,
                    onPressed: bloqueadoOperacionBola
                        ? null
                        : () => BolaPuebloDialogs.enviarOferta(
                              context: context,
                              bolaId: docId,
                              uid: user.uid,
                              nombre: nombre,
                              rol: rol,
                              montoInicial: montoSemillaOferta,
                            ),
                    child: Text(
                      bloqueadoOperacionBola
                          ? 'No disponible'
                          : (monto > 0
                              ? 'Misma cifra publicada · RD\$${monto.toStringAsFixed(0)}'
                              : (montoSemillaOferta > 0
                                  ? 'Propuesta inicial · RD\$${montoSemillaOferta.toStringAsFixed(0)}'
                                  : 'Elegí el monto en el siguiente paso')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: BolaPuebloUi.filledSecondary,
                    onPressed: bloqueadoOperacionBola
                        ? null
                        : () => BolaPuebloDialogs.enviarOferta(
                              context: context,
                              bolaId: docId,
                              uid: user.uid,
                              nombre: nombre,
                              rol: rol,
                              montoInicial: ofertaMaxRd,
                            ),
                    child: Text(
                      bloqueadoOperacionBola
                          ? 'No disponible'
                          : 'Tope permitido · RD\$${ofertaMaxRd.toStringAsFixed(0)}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.onSurface,
                      side: BorderSide(color: c.outlineOnCard),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(BolaPuebloUi.radiusButton),
                      ),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    onPressed: bloqueadoOperacionBola
                        ? null
                        : () => BolaPuebloDialogs.enviarOferta(
                              context: context,
                              bolaId: docId,
                              uid: user.uid,
                              nombre: nombre,
                              rol: rol,
                              montoInicial: montoSemillaOferta,
                            ),
                    child: Text(
                      bloqueadoOperacionBola
                          ? 'No disponible'
                          : 'Proponer otro monto',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
