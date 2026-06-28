import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/widgets/pool_gira_qr_scanner.dart';

/// Validar ticket de gira por código o escaneo QR (admin u operador).
class PoolGiraValidarEntradaPage extends StatefulWidget {
  const PoolGiraValidarEntradaPage({super.key, this.poolId});

  /// Si se pasa, solo acepta tickets de esa gira (operador en su salida).
  final String? poolId;

  @override
  State<PoolGiraValidarEntradaPage> createState() =>
      _PoolGiraValidarEntradaPageState();
}

class _PoolGiraValidarEntradaPageState extends State<PoolGiraValidarEntradaPage> {
  final _ctrl = TextEditingController();
  bool _validando = false;
  Map<String, dynamic>? _ultimoOk;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _validar([String? tokenOverride]) async {
    final token =
        (tokenOverride ?? _ctrl.text).trim().toUpperCase();
    final parsed = extraerTokenGiraDesdeTexto(token) ?? token;
    if (parsed.isEmpty || !parsed.startsWith('RAI-')) {
      _snack('Escribe o escanea un código válido (ej. RAI-ABC12345)');
      return;
    }
    setState(() {
      _validando = true;
      _ultimoOk = null;
    });
    try {
      final r = await PoolRepo.validarTokenEntradaGira(
        token: parsed,
        poolId: widget.poolId,
      );
      if (!mounted) return;
      setState(() => _ultimoOk = r);
      _snack('✅ Entrada válida — ${r['pasajero']} · ${r['asientos']} asiento(s)');
      _ctrl.clear();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _validando = false);
    }
  }

  Future<void> _escanear() async {
    final token = await escanearTokenGiraConCamara(context);
    if (token != null && token.isNotEmpty) {
      _ctrl.text = token;
      await _validar(token);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.poolId == null
              ? 'Validar ticket gira'
              : 'Validar entrada — esta gira',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            kIsWeb
                ? 'Pega el código del ticket o el texto del QR.'
                : 'Escanea el QR del pasajero o pega el código manualmente.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _validando ? null : _escanear,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear con cámara'),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Código ticket',
              hintText: 'RAI-XXXXXXXX',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _validar(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _validando ? null : () => _validar(),
            icon: _validando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_outlined),
            label: const Text('Validar entrada'),
          ),
          if (_ultimoOk != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Última validación',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text('Pasajero: ${_ultimoOk!['pasajero']}'),
                    Text('Gira: ${_ultimoOk!['gira']}'),
                    Text('Asientos: ${_ultimoOk!['asientos']}'),
                    if ((_ultimoOk!['agencia'] ?? '').toString().isNotEmpty)
                      Text('Empresa: ${_ultimoOk!['agencia']}'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
