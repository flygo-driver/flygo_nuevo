import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Misma lógica de voz que [RaiAsistenteSheet] (FAB flotante), compartida en buscadores.
///
/// Una sola instancia evita conflictos entre varios [SpeechToText] en Android.
class RaiSpeechBusquedaDireccion {
  RaiSpeechBusquedaDireccion._();

  static final RaiSpeechBusquedaDireccion shared = RaiSpeechBusquedaDireccion._();

  /// Compatibilidad con `final _voz = RaiSpeechBusquedaDireccion()`.
  factory RaiSpeechBusquedaDireccion() => shared;

  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;
  bool _escuchando = false;
  void Function(bool active)? _onListeningChanged;
  String? _ultimoFallo;

  bool get isAvailable => _initialized;
  bool get isListening => _escuchando;
  String? get ultimoFallo => _ultimoFallo;

  /// Igual que `_initVoz` del asistente RAI flotante.
  Future<bool> initialize() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            _setEscuchando(false);
          }
        },
        onError: (_) {
          _setEscuchando(false);
        },
      );
      _initialized = ok;
      if (!ok) {
        _ultimoFallo =
            'Reconocimiento de voz no disponible. Revisa la app Google.';
      } else {
        _ultimoFallo = null;
      }
      return ok;
    } catch (e) {
      _initialized = false;
      _ultimoFallo = 'No se pudo iniciar el micrófono.';
      debugPrint('[RAI_VOZ] init $e');
      return false;
    }
  }

  void _setEscuchando(bool active) {
    if (_escuchando == active) return;
    _escuchando = active;
    _onListeningChanged?.call(active);
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
    _setEscuchando(false);
  }

  /// No usar en widgets: es instancia compartida. Solo [stop] si hace falta cortar dictado.
  Future<void> dispose() => stop();

  /// Igual que `_toggleVoz` del asistente: [localeId] es_DO, 30s / pausa 4s.
  Future<bool> toggleListen({
    required void Function(String words, bool isFinal) onResult,
    required void Function(bool active) onListeningChanged,
  }) async {
    _onListeningChanged = onListeningChanged;

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    if (_escuchando) {
      await stop();
      return true;
    }

    _ultimoFallo = null;
    _setEscuchando(true);

    try {
      final ok = await _speech.listen(
        onResult: (r) {
          final words = r.recognizedWords;
          if (words.isNotEmpty) {
            onResult(words, false);
          }
          if (r.finalResult && words.trim().isNotEmpty) {
            unawaited(_speech.stop());
            _setEscuchando(false);
            onResult(words.trim(), true);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: 'es_DO',
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
        ),
      );
      if (!ok) {
        _ultimoFallo = 'No se pudo abrir el micrófono. Intenta de nuevo.';
        _setEscuchando(false);
        return false;
      }
      return true;
    } catch (e) {
      _ultimoFallo = 'Error al escuchar: $e';
      debugPrint('[RAI_VOZ] listen $e');
      _setEscuchando(false);
      return false;
    }
  }
}
