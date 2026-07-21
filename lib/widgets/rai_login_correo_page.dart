import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/servicios/phone_auth_error_es.dart';
import 'package:flygo_nuevo/servicios/post_auth_navigation.dart';
import 'package:flygo_nuevo/widgets/rai_entrada_hero.dart';

/// Login con correo + contraseña (cuentas legacy Play).
class RaiLoginCorreoPage extends StatefulWidget {
  const RaiLoginCorreoPage({
    super.key,
    this.entradaRol = 'cliente',
    this.postLoginRoute,
  });

  final String entradaRol;
  final String? postLoginRoute;

  static Future<void> abrir(
    BuildContext context, {
    String entradaRol = 'cliente',
    String? postLoginRoute,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RaiLoginCorreoPage(
          entradaRol: entradaRol,
          postLoginRoute: postLoginRoute,
        ),
      ),
    );
  }

  @override
  State<RaiLoginCorreoPage> createState() => _RaiLoginCorreoPageState();
}

class _RaiLoginCorreoPageState extends State<RaiLoginCorreoPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _cargando = false;
  bool _ocultarPass = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      final rol =
          widget.entradaRol.trim().toLowerCase() == 'taxista' ? 'taxista' : 'cliente';
      await AuthService().loginUser(
        _email.text.trim(),
        _pass.text,
        rolSiFalta: rol,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if ((widget.postLoginRoute ?? '').trim().isNotEmpty) {
        await PostAuthNavigation.saveRoute(widget.postLoginRoute!.trim());
      }
      await PostAuthNavigation.goAfterStoredRoute(context);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'role-mismatch') {
        _snack(phoneAuthErrorEs(e, entradaRol: widget.entradaRol));
      } else {
        _snack(errorAuthEs(e));
      }
    } catch (e) {
      _snack(errorAuthEs(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  bool get _esConductor =>
      widget.entradaRol.trim().toLowerCase() == 'taxista';

  @override
  Widget build(BuildContext context) {
    final c = RaiEntradaColores.de(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return RaiEntradaScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RaiEntradaHero(compacto: true, mostrarEslogan: true),
              const SizedBox(height: 16),
              Center(
                child: RaiEntradaRolEtiqueta(
                  entradaRol: widget.entradaRol,
                ),
              ),
              const SizedBox(height: 20),
              Text('Entrá con correo', style: c.estiloTitulo),
              const SizedBox(height: 8),
              Text(
                _esConductor
                    ? 'Solo para cuentas que ya creaste con correo.'
                    : '¿Ya tenés cuenta con correo? Entrá acá. '
                        '¿Primera vez? Volvé y usá celular o Google.',
                style: c.estiloSubtitulo,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                style: c.estiloCampo,
                cursorColor: RaiEntradaColores.raiVerde,
                decoration: raiCampoEntradaDecoration(
                  context,
                  label: 'Correo electrónico',
                  hint: 'tu@correo.com',
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty || !t.contains('@')) {
                    return 'Correo inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pass,
                obscureText: _ocultarPass,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _entrar(),
                style: c.estiloCampo,
                cursorColor: RaiEntradaColores.raiVerde,
                decoration: raiCampoEntradaDecoration(
                  context,
                  label: 'Contraseña',
                  hint: 'Mínimo 6 caracteres',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _ocultarPass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(
                      () => _ocultarPass = !_ocultarPass,
                    ),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? 'Mínimo 6 caracteres'
                    : null,
              ),
              const SizedBox(height: 28),
              raiBotonContinuar(
                onPressed: _cargando ? null : _entrar,
                label: 'Continuar',
                cargando: _cargando,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
