import 'package:flutter/material.dart';
import 'package:flygo_nuevo/legal/legal_urls.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_contrato_service.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// Firma digital del contrato de servicio corporativo (encargado / empresa).
class ContratoCorporativoFirmaPage extends StatefulWidget {
  const ContratoCorporativoFirmaPage({
    super.key,
    required this.empresaId,
    required this.nombreEmpresa,
    this.onFirmado,
  });

  final String empresaId;
  final String nombreEmpresa;
  final VoidCallback? onFirmado;

  @override
  State<ContratoCorporativoFirmaPage> createState() =>
      _ContratoCorporativoFirmaPageState();
}

class _ContratoCorporativoFirmaPageState
    extends State<ContratoCorporativoFirmaPage> {
  bool _acepta = false;
  bool _guardando = false;

  Future<void> _abrirContratoWeb() async {
    await abrirUrlLegal(context, kCorporativoContractPublicUrl);
  }

  Future<void> _firmar() async {
    if (_guardando || !_acepta) return;
    final uid = CorporativoContratoService.uidActual();
    if (uid == null) return;

    setState(() => _guardando = true);
    try {
      await CorporativoContratoService.firmarContrato(
        empresaId: widget.empresaId,
        encargadoUid: uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Contrato firmado. Ya podés entrar a configurar rutas de ${widget.nombreEmpresa}. '
            'Cuando RAI active el servicio, podrás publicar viajes.',
          ),
          backgroundColor: Colors.green.shade800,
        ),
      );
      widget.onFirmado?.call();
      if (widget.onFirmado == null) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      final permiso = raw.contains('permission-denied') ||
          raw.contains('permission_denied');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            permiso
                ? 'No se pudo firmar: tu cuenta no tiene permiso como encargado '
                    'de esta empresa. Pedí a RAI que te habilite con este correo.'
                : 'No se pudo firmar el contrato. Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: RaiAppBar(
        title: 'Contrato corporativo',
        leading: widget.onFirmado != null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.nombreEmpresa,
                style: TextStyle(
                  color: p.onCard,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Al firmar aceptás el Contrato de Servicio Corporativo RAI '
                '(modelo B2B). Entrá al centro para configurar rutas; '
                'RAI activa el servicio para publicar viajes.',
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      corporativoCard(
                        context,
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          kCorporativoContractText,
                          style: TextStyle(
                            color: p.onCard.withValues(alpha: 0.88),
                            height: 1.38,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _abrirContratoWeb,
                        icon: Icon(Icons.open_in_new, color: p.primary),
                        label: Text(
                          'Ver contrato completo en web',
                          style: TextStyle(color: p.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _acepta,
                onChanged: (v) => setState(() => _acepta = v == true),
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                activeColor: p.primary,
                title: Text(
                  'He leído y acepto el Contrato de Servicio Corporativo RAI v$kCorporativoContractVersion, '
                  'con facultad para obligar a mi empresa.',
                  style: TextStyle(
                    color: p.onCard,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: (_acepta && !_guardando) ? _firmar : null,
                  icon: const Icon(Icons.draw, size: 22),
                  label: Text(
                    _guardando ? 'Guardando firma...' : 'Firmar y continuar',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.ctaBg,
                    foregroundColor: p.ctaFg,
                    disabledBackgroundColor: p.muted.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
