// UI de negociación Bola Ahorro (ofertas, contraofertas). Solo presentación.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pantallas/comun/bola_pueblo_visual.dart';

/// Componentes visuales para ofertas y contraofertas (estilo inDriver, preciso).
abstract final class BolaNegociacionUi {
  static Widget offersSheetHeader(
    BuildContext context, {
    required String title,
    double? minRd,
    double? maxRd,
  }) {
    final c = BolaPuebloColors.of(context);
    return Column(
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: c.dragHandle,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            color: c.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Aceptá, contraofertá o descartá. El precio se cierra cuando ambos aceptan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.onMuted, fontSize: 12, height: 1.3),
        ),
        if (minRd != null &&
            maxRd != null &&
            maxRd >= minRd &&
            minRd > 0) ...[
          const SizedBox(height: 8),
          BolaPuebloUi.statusChip(
            context,
            label:
                'Rango RD\$${minRd.toStringAsFixed(0)} – RD\$${maxRd.toStringAsFixed(0)}',
            color: BolaPuebloTheme.accentSecondary,
          ),
        ],
      ],
    );
  }

  /// Formulario contraoferta (diálogo).
  static Widget contraofertaForm(
    BuildContext context, {
    required String counterpartyName,
    required double theirAmountRd,
    required TextEditingController montoCtrl,
    required TextEditingController msgCtrl,
    double? minRd,
    double? maxRd,
  }) {
    final c = BolaPuebloColors.of(context);
    final name =
        counterpartyName.trim().isEmpty ? 'Usuario' : counterpartyName.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        priceCompareBar(
          context,
          leftLabel: 'Su oferta',
          leftRd: theirAmountRd,
          rightLabel: 'Tu contraoferta',
          rightRd: double.tryParse(
                montoCtrl.text.trim().replaceAll(',', '.'),
              ) ??
              theirAmountRd,
        ),
        const SizedBox(height: 14),
        Text(
          '$name propuso RD\$${theirAmountRd.toStringAsFixed(0)}. '
          'Escribí el monto exacto que aceptás.',
          style: TextStyle(color: c.onMuted, fontSize: 12, height: 1.35),
        ),
        if (minRd != null && maxRd != null && maxRd >= minRd) ...[
          const SizedBox(height: 6),
          Text(
            'Permitido: RD\$${minRd.toStringAsFixed(0)} – RD\$${maxRd.toStringAsFixed(0)}',
            style: TextStyle(
              color: BolaPuebloTheme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: montoCtrl,
          style: TextStyle(
            color: c.onSurface,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            prefixText: 'RD\$ ',
            prefixStyle: TextStyle(
              color: c.onMuted,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            filled: true,
            fillColor: c.surfaceRaised,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) {},
        ),
        const SizedBox(height: 10),
        TextField(
          controller: msgCtrl,
          style: TextStyle(color: c.onSurface, fontSize: 14),
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Nota (opcional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  /// Barra comparativa dos montos.
  static Widget priceCompareBar(
    BuildContext context, {
    required String leftLabel,
    required double leftRd,
    required String rightLabel,
    required double rightRd,
  }) {
    final c = BolaPuebloColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.outlineSoft.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _priceCol(
              context,
              label: leftLabel,
              amount: leftRd,
              muted: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded,
                color: c.onMuted, size: 20),
          ),
          Expanded(
            child: _priceCol(
              context,
              label: rightLabel,
              amount: rightRd,
              muted: false,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _priceCol(
    BuildContext context, {
    required String label,
    required double amount,
    required bool muted,
  }) {
    final c = BolaPuebloColors.of(context);
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.onMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'RD\$${amount.toStringAsFixed(0)}',
          style: TextStyle(
            color: muted ? c.onMuted : BolaPuebloTheme.accent,
            fontSize: muted ? 16 : 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  /// Precio grande en tarjeta.
  static Widget priceHero(
    BuildContext context, {
    required double amountRd,
    String? meta,
    String label = 'Precio',
  }) {
    final c = BolaPuebloColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.onMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'RD\$${amountRd.toStringAsFixed(0)}',
                style: TextStyle(
                  color: BolaPuebloTheme.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  height: 1.05,
                ),
              ),
              if (meta != null && meta.isNotEmpty)
                Text(
                  meta,
                  style: TextStyle(
                    color: c.onMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cabecera fila en hoja de ofertas.
  static Widget offerRowHeader(
    BuildContext context, {
    required String title,
    required double montoRd,
    String? badge,
    String? message,
  }) {
    final c = BolaPuebloColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badge != null && badge.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: BolaPuebloUi.statusChip(
                        context,
                        label: badge,
                        color: BolaPuebloTheme.accentSecondary,
                      ),
                    ),
                  Text(
                    title,
                    style: TextStyle(
                      color: c.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'RD\$${montoRd.toStringAsFixed(0)}',
              style: const TextStyle(
                color: BolaPuebloTheme.accent,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        if (message != null && message.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              color: c.onMuted,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  /// Tarjeta contraoferta entrante (aceptar / rechazar).
  static Widget inboundContraofertaShell(
    BuildContext context, {
    required String fromName,
    required double montoRd,
    String? message,
    required List<Widget> actions,
    Widget? footer,
  }) {
    final c = BolaPuebloColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BolaPuebloTheme.accent.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BolaPuebloUi.statusChip(
                  context,
                  label: 'Contraoferta',
                  color: BolaPuebloTheme.accent,
                ),
              ],
            ),
            const SizedBox(height: 10),
            offerRowHeader(
              context,
              title: fromName,
              montoRd: montoRd,
              message: message?.trim().isEmpty == true ? null : message,
            ),
            const SizedBox(height: 12),
            ...actions,
            if (footer != null) ...[
              const SizedBox(height: 8),
              footer,
            ],
          ],
        ),
      ),
    );
  }

  static Widget actionRow({
    required Widget reject,
    required Widget accept,
  }) {
    return Row(
      children: [
        Expanded(child: reject),
        const SizedBox(width: 8),
        Expanded(child: accept),
      ],
    );
  }

  static ButtonStyle rejectBtn(BuildContext context) {
    final c = BolaPuebloColors.of(context);
    return OutlinedButton.styleFrom(
      foregroundColor: c.onSurface,
      side: BorderSide(color: c.onSurface.withValues(alpha: 0.35)),
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  static ButtonStyle acceptBtn() {
    return FilledButton.styleFrom(
      backgroundColor: BolaPuebloTheme.accent,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  /// Ruta compacta origen → destino.
  static Widget compactRoute(
    BuildContext context, {
    required String origen,
    required String destino,
  }) {
    final c = BolaPuebloColors.of(context);
    return Row(
      children: [
        Icon(Icons.trip_origin,
            size: 14, color: BolaPuebloTheme.accent),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            origen,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward_rounded,
              size: 14, color: c.onMuted),
        ),
        Icon(Icons.flag_rounded,
            size: 14, color: BolaPuebloTheme.accentSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            destino,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
