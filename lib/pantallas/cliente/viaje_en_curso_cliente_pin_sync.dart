part of 'viaje_en_curso_cliente.dart';

/// PIN, abordo y sincronizacion en vivo del viaje cliente (extraido del monolito).
mixin _ViajeEnCursoClientePinSync on State<ViajeEnCursoCliente> {
  static const Duration _kClienteViajeSyncPulseInterval = Duration(seconds: 2);
  static const Duration _kClienteViajeSyncPulseRapido =
      Duration(milliseconds: 900);

  Timer? _clienteViajeSyncPulseTimer;
  String? _syncPulseViajeId;
  Map<String, dynamic>? _syncPulseViajeData;
  bool _syncPulseRapidoActivo = false;
  DateTime? _ultimoPulseForzadoPorStream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _viajeDocSub;
  String _lastNotifiedState = '';
  String _lastWatchDocUiSig = '';
  String _lastLiveAbordoPinSig = '';

  String? _pinAbordoLiveViajeId;
  String? _snackPinAbordoLiveMostrado;
  String _ultimoPinUiMostrado = '';
  String _ultimoTaxistaAsignadoEnWatch = '';
  String _viajeIdAsignacionWatch = '';

  String? _pinEnsureViajeId;
  int _pinEnsureSeq = 0;
  bool _pinEnsureEnCurso = false;
  DateTime? _pinEnsureUltimoIntento;
  bool _refrescandoViajeManual = false;

  _ViajeEnCursoClienteState get _pinHost => this as _ViajeEnCursoClienteState;

  /// Tras retomar / abrir overlay: caché local → callable → pulso (evita carga infinita
  /// si el listener de Firestore devuelve permission-denied).
  Future<void> _bootstrapViajeClienteAlAbrir() async {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null || !mounted) return;

    String vid = _pinHost._lastNonEmptyViajeActivoId.trim();
    if (vid.isEmpty) {
      vid = ActiveTripService.resolverViajeIdClienteParaPausa();
    }
    if (vid.isEmpty) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> us =
            await FirebaseFirestore.instance
                .collection('usuarios')
                .doc(u.uid)
                .get();
        vid = (us.data()?['viajeActivoId'] ?? '').toString().trim();
      } catch (_) {}
    }
    if (vid.isEmpty) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_pinHost._bootstrapViajeIntentadoId == vid &&
        nowMs - _pinHost._bootstrapViajeUltimoIntentoMs < 2500) {
      return;
    }
    _pinHost._bootstrapViajeIntentadoId = vid;
    _pinHost._bootstrapViajeUltimoIntentoMs = nowMs;

    print('[VIAJE_ACTIVO] bootstrap viaje al abrir vid=$vid');
    Map<String, dynamic>? d =
        ActiveTripService.tomarBootstrapViajeCliente(vid);

    try {
      if (d == null) {
        final DocumentSnapshot<Map<String, dynamic>> cacheSnap =
            await FirebaseFirestore.instance
                .collection('viajes')
                .doc(vid)
                .get(const GetOptions(source: Source.cache));
        if (cacheSnap.exists) {
          final Map<String, dynamic>? cacheData = cacheSnap.data();
          if (cacheData != null && cacheData.isNotEmpty) {
            d = Map<String, dynamic>.from(cacheData);
            _pinHost._lastViajeUiCache = cacheSnap;
          }
        }
      }
    } catch (_) {}

    d = await ViajesRepo.fetchViajeDocClienteAutoritativo(vid, base: d);
    if (!mounted) return;
    if (d == null || d.isEmpty) {
      print('[VIAJE_ACTIVO] bootstrap viaje sin datos vid=$vid');
      _pinHost._bootstrapViajeIntentadoId = '';
      return;
    }

    _pinHost._lastNonEmptyViajeActivoId = vid;
    _pinHost._viajeDatosOfflineId = vid;
    _pinHost._viajeDatosOffline = Map<String, dynamic>.from(d);
    _ingestarPulsoServidorViaje(vid, d);
    _aplicarAbordoPinEnVivo(viajeId: vid, d: d);
    _startClienteViajeSyncPulse(vid, forceRestart: true);
    if (mounted) setState(() {});
    print('[VIAJE_ACTIVO] bootstrap viaje OK vid=$vid');
  }

  Future<void> _refrescarViajeActivoClienteResume() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || !mounted) return;
    print('[VIAJE_ACTIVO] cliente resumed: refresh viaje (cache→server)');
    _lastLiveAbordoPinSig = '';
    _lastWatchDocUiSig = '';
    try {
      String resolvedViajeId = '';
      Map<String, dynamic>? d;

      final us = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get(const GetOptions(source: Source.server));
      resolvedViajeId = (us.data()?['viajeActivoId'] ?? '').toString().trim();

      if (resolvedViajeId.isNotEmpty) {
        // 1) Caché local: al volver de la app taxista, Firestore a veces ya tiene el abordo.
        try {
          final DocumentSnapshot<Map<String, dynamic>> cacheSnap =
              await FirebaseFirestore.instance
                  .collection('viajes')
                  .doc(resolvedViajeId)
                  .get(const GetOptions(source: Source.cache));
          if (cacheSnap.exists) {
            final Map<String, dynamic>? cacheData = cacheSnap.data();
            if (cacheData != null && cacheData.isNotEmpty) {
              _ingestarPulsoServidorViaje(resolvedViajeId, cacheData);
              _aplicarAbordoPinEnVivo(viajeId: resolvedViajeId, d: cacheData);
              if (mounted) setState(() {});
            }
          }
        } catch (_) {}

        // 2) Servidor: fuente autoritativa (abordo + PIN).
        d = await ViajesRepo.fetchViajeDocClienteAutoritativo(
          resolvedViajeId,
        );
        if (d == null) {
          final DocumentSnapshot<Map<String, dynamic>> vs =
              await FirebaseFirestore.instance
                  .collection('viajes')
                  .doc(resolvedViajeId)
                  .get();
          if (vs.exists) d = vs.data();
        }
      }
      if (d == null) {
        final snap = await ViajesRepo.getViajeActivoParaUsuario(u.uid);
        if (snap != null && snap.exists) {
          resolvedViajeId = snap.id;
          d = await ViajesRepo.fetchViajeDocClienteAutoritativo(resolvedViajeId);
        }
      }

      if (d == null || resolvedViajeId.isEmpty) {
        if (mounted) setState(() {});
        return;
      }

      final bool abordoNuevo = _clienteAbordoEnMapData(d) ||
          EstadosViaje.esAbordo(
            EstadosViaje.normalizar((d['estado'] ?? '').toString()),
          );

      _ingestarPulsoServidorViaje(resolvedViajeId, d);
      _aplicarAbordoPinEnVivo(viajeId: resolvedViajeId, d: d);
      _disposeDocWatch();
      _startClienteViajeSyncPulse(
        resolvedViajeId,
        forceRestart: true,
        rapido: abordoNuevo || (d['codigoVerificado'] != true),
      );
      _pinHost._manejarViajeCerradoSiCorresponde(
        viajeId: resolvedViajeId,
        uid: u.uid,
        data: d,
        origen: 'resume',
      );

      if (mounted) {
        setState(() {});
        if (abordoNuevo && d['codigoVerificado'] != true) {
          _mostrarSnackPinAbordoListo(d);
        } else {
          final now = DateTime.now();
          if (_pinHost._lastClienteNavResumeSnackAt == null ||
              now.difference(_pinHost._lastClienteNavResumeSnackAt!) >=
                  const Duration(seconds: 6)) {
            _pinHost._lastClienteNavResumeSnackAt = now;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Seguís en tu viaje RAI: el mapa, el conductor y el estado se actualizan aquí.',
                  ),
                  duration: Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            });
          }
        }
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] cliente resume refresh error: $e');
    }
  }

  void _mostrarSnackPinAbordoListo(Map<String, dynamic> viajeData) {
    final String pin = ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
      viajeData: viajeData,
    );
    final String cuerpo = pin.length == 6
        ? 'Tu conductor te marcó a bordo. PIN: $pin'
        : 'Tu conductor te marcó a bordo. Tu PIN aparece arriba.';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cuerpo),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1B5E20),
        ),
      );
    });
  }

  /// El cliente toca para forzar sync servidor (útil si cambió de app o el PIN no entró).
  Future<void> _refrescarEstadoViajeManual(String viajeId) async {
    if (_refrescandoViajeManual) return;
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    setState(() => _refrescandoViajeManual = true);
    try {
      _lastLiveAbordoPinSig = '';
      _lastWatchDocUiSig = '';

      try {
        final DocumentSnapshot<Map<String, dynamic>> cacheSnap =
            await FirebaseFirestore.instance
                .collection('viajes')
                .doc(id)
                .get(const GetOptions(source: Source.cache));
        if (cacheSnap.exists) {
          final Map<String, dynamic>? cacheData = cacheSnap.data();
          if (cacheData != null && cacheData.isNotEmpty) {
            _ingestarPulsoServidorViaje(id, cacheData);
            try {
              _aplicarAbordoPinEnVivo(viajeId: id, d: cacheData);
            } catch (_) {}
          }
        }
      } catch (_) {}

      Map<String, dynamic>? d = await ViajesRepo.fetchViajeDocClienteAutoritativo(
        id,
        base: _syncPulseViajeData,
      );
      if (!mounted) return;
      if (d == null || d.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo actualizar. Verifica tu conexión e intenta de nuevo.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      _ingestarPulsoServidorViaje(id, d);
      try {
        _aplicarAbordoPinEnVivo(viajeId: id, d: d);
      } catch (_) {}
      _disposeDocWatch();
      _startClienteViajeSyncPulse(id, forceRestart: true, rapido: true);

      final String pin = ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
        viajeData: d,
      );
      final bool abordo = _clienteAbordoEnMapData(d) ||
          EstadosViaje.esAbordo(
            EstadosViaje.normalizar((d['estado'] ?? '').toString()),
          );

      if (!mounted) return;
      setState(() {});
      if (abordo && d['codigoVerificado'] != true) {
        final Viaje v = Viaje.fromMap(id, Map<String, dynamic>.from(d));
        _maybeExpandirSheetAbordoCliente(
          v: v,
          viajeData: d,
          estadoEfectivo: ClienteViajeEstadoEfectivo.resolver(d),
          mostrarCodigoCliente: true,
          codigoVerificado: false,
        );
      }
      final String msg = pin.length == 6
          ? 'Actualizado. Tu PIN es $pin — díctaselo al conductor.'
          : abordo
              ? 'Actualizado. El conductor ya te marcó a bordo; el PIN aparece arriba.'
              : 'Aún no estás marcado a bordo. Cuando el conductor lo haga, toca de nuevo.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          backgroundColor: pin.length == 6
              ? const Color(0xFF1B5E20)
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final Map<String, dynamic>? local = _syncPulseViajeData;
      final String pinLocal = local != null
          ? ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(viajeData: local)
          : '';
      if (pinLocal.length == 6) {
        _ingestarPulsoServidorViaje(id, local!);
        _aplicarAbordoPinEnVivo(viajeId: id, d: local);
        if (mounted) setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tu PIN es $pinLocal — díctaselo al conductor.',
            ),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1B5E20),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo sincronizar con el servidor. Si ya ves tu PIN arriba, '
            'díctaselo al conductor.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _refrescandoViajeManual = false);
    }
  }
  void _stopClienteViajeSyncPulse() {
    _clienteViajeSyncPulseTimer?.cancel();
    _clienteViajeSyncPulseTimer = null;
    _syncPulseRapidoActivo = false;
  }

  void _startClienteViajeSyncPulse(
    String viajeId, {
    bool forceRestart = false,
    bool rapido = false,
  }) {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    final bool mismoViajeActivo =
        _clienteViajeSyncPulseTimer != null && _syncPulseViajeId == id;
    if (!forceRestart && mismoViajeActivo) {
      if (rapido && !_syncPulseRapidoActivo) {
        forceRestart = true;
      } else {
        return;
      }
    }
    _stopClienteViajeSyncPulse();
    _syncPulseViajeId = id;
    _syncPulseRapidoActivo = rapido;
    final Duration interval = rapido
        ? _kClienteViajeSyncPulseRapido
        : _kClienteViajeSyncPulseInterval;
    unawaited(_clienteViajeSyncPulseTick(id));
    _clienteViajeSyncPulseTimer = Timer.periodic(
      interval,
      (_) => unawaited(_clienteViajeSyncPulseTick(id)),
    );
  }

  void _ajustarSyncPulseParaFaseAbordoPin({
    required String viajeId,
    required bool esperandoPinAbordo,
    required bool codigoVerificado,
  }) {
    if (codigoVerificado) {
      if (_syncPulseRapidoActivo && _syncPulseViajeId == viajeId) {
        _startClienteViajeSyncPulse(viajeId, forceRestart: true);
      }
      return;
    }
    if (esperandoPinAbordo) {
      _startClienteViajeSyncPulse(viajeId, rapido: true);
    }
  }

  void _notificarPinAbordoEnVivoSiCorresponde({
    required String viajeId,
    required Map<String, dynamic> d,
    required bool abordoUi,
    required bool codigoVerificado,
  }) {
    if (!abordoUi || codigoVerificado) return;
    final String pin = ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
      viajeData: d,
    );
    if (pin.length != 6) return;
    if (_snackPinAbordoLiveMostrado == viajeId) return;
    _snackPinAbordoLiveMostrado = viajeId;
    _mostrarSnackPinAbordoListo(d);
  }

  void _maybeForzarPulseServidorPorStreamAtrasado({
    required String viajeId,
    required Map<String, dynamic> streamData,
  }) {
    final String tid =
        (streamData['uidTaxista'] ?? streamData['taxistaId'] ?? '')
            .toString()
            .trim();
    if (tid.isEmpty) return;

    final String est =
        EstadosViaje.normalizar((streamData['estado'] ?? '').toString());
    if (!(EstadosViaje.esAceptado(est) ||
        EstadosViaje.esEnCaminoPickup(est) ||
        EstadosViaje.esAbordo(est))) {
      return;
    }

    final DateTime now = DateTime.now();
    if (_ultimoPulseForzadoPorStream != null &&
        now.difference(_ultimoPulseForzadoPorStream!) <
            const Duration(seconds: 2)) {
      return;
    }
    _ultimoPulseForzadoPorStream = now;
    unawaited(_clienteViajeSyncPulseTick(viajeId));
  }

  void _ingestarPulsoServidorViaje(String viajeId, Map<String, dynamic> d) {
    final String id = viajeId.trim();
    if (id.isEmpty || d.isEmpty) return;
    _syncPulseViajeId = id;
    _syncPulseViajeData = Map<String, dynamic>.from(d);
  }

  Map<String, dynamic> _mergeViajeDataConPulsoServidor(
    String viajeId,
    Map<String, dynamic> streamData,
  ) {
    if (_syncPulseViajeId != viajeId || _syncPulseViajeData == null) {
      return streamData;
    }
    final Map<String, dynamic> merged = ClienteViajeDataMerge.merge(
      streamData,
      _syncPulseViajeData,
    );
    if (!ClienteViajeDataMerge.serverEstaAdelante(
      streamData,
      _syncPulseViajeData!,
    )) {
      _syncPulseViajeData = null;
    }
    return merged;
  }

  Future<void> _clienteViajeSyncPulseTick(String viajeId) async {
    if (!mounted) return;
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    try {
      final Map<String, dynamic>? d =
          await ViajesRepo.fetchViajeDocClienteAutoritativo(
        id,
        base: _syncPulseViajeData,
      );
      if (!mounted || d == null || d.isEmpty) return;

      final String est =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (EstadosViaje.esTerminal(est) || d['completado'] == true) {
        _ingestarPulsoServidorViaje(id, d);
        if (mounted) {
          _pinHost._manejarViajeCerradoSiCorresponde(
            viajeId: id,
            uid: FirebaseAuth.instance.currentUser?.uid ?? '',
            data: d,
            origen: 'syncPulse',
          );
          setState(() {});
        }
        return;
      }

      _ingestarPulsoServidorViaje(id, d);
      _aplicarAbordoPinEnVivo(viajeId: id, d: d);
      ActiveTripService.registrarViajeOperativoCliente(id);
      if (!ActiveTripService.flujoPostViajeClienteBloquea(id)) {
        ActiveTripService.mantenerOverlayViajeEnShell(
          NavigationService.kOverlayClienteViajeActivo,
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      print('[VIAJE_ACTIVO] cliente sync pulse error: $e');
    }
  }
  bool _clienteAbordoEnViajeDoc(Map<String, dynamic> viajeData, Viaje v) {
    if (viajeData['clienteAbordo'] == true) return true;
    if (v.extras?['clienteAbordo'] == true) return true;
    final dynamic ex = viajeData['extras'];
    if (ex is Map && ex['clienteAbordo'] == true) return true;
    return false;
  }

  bool _clienteAbordoEnMapData(Map<String, dynamic> viajeData) {
    if (viajeData['clienteAbordo'] == true) return true;
    final dynamic ex = viajeData['extras'];
    return ex is Map && ex['clienteAbordo'] == true;
  }

  void _marcarPinAbordoLive(String viajeId, Map<String, dynamic> d) {
    if (d['codigoVerificado'] == true) {
      if (_pinAbordoLiveViajeId == viajeId) _pinAbordoLiveViajeId = null;
      return;
    }
    if (!_clienteAbordoEnMapData(d) &&
        !EstadosViaje.esAbordo(
          EstadosViaje.normalizar((d['estado'] ?? '').toString()),
        )) {
      return;
    }
    _pinAbordoLiveViajeId = viajeId;
  }

  bool _codigoVerificadoEnDoc(Viaje v, Map<String, dynamic> viajeData) =>
      v.codigoVerificado ||
      ClienteViajeEstadoEfectivo.codigoVerificadoEnDoc(viajeData);

  /// Misma lógica que taxista: `clienteAbordo` puede llegar antes que `estado`.
  /// Tras PIN verificado → siempre «en curso» aunque Firestore tarde en actualizar.
  String _estadoEfectivoFlujoCliente(Viaje v, Map<String, dynamic> viajeData) {
    final Map<String, dynamic> merged = Map<String, dynamic>.from(viajeData)
      ..['estado'] = v.estado.isNotEmpty ? v.estado : viajeData['estado']
      ..['aceptado'] = v.aceptado
      ..['completado'] = v.completado
      ..['codigoVerificado'] = _codigoVerificadoEnDoc(v, viajeData);
    if (_clienteAbordoEnViajeDoc(viajeData, v)) {
      merged['clienteAbordo'] = true;
    }
    return ClienteViajeEstadoEfectivo.resolver(merged);
  }

  void _maybeExpandirSheetAbordoCliente({
    required Viaje v,
    required Map<String, dynamic> viajeData,
    required String estadoEfectivo,
    required bool mostrarCodigoCliente,
    required bool codigoVerificado,
  }) {
    final bool abordoUi = EstadosViaje.esAbordo(estadoEfectivo) ||
        _clienteAbordoEnViajeDoc(viajeData, v);
    if (codigoVerificado) return;
    if (!abordoUi && !mostrarCodigoCliente && v.uidTaxista.isEmpty) return;

    final bool faseAbordoPin = v.uidTaxista.isNotEmpty &&
        (abordoUi || mostrarCodigoCliente) &&
        !codigoVerificado;

    _pinHost._maybeAutoExpandirSheetPorFaseCliente(
      v: v,
      estadoBase: estadoEfectivo,
      faseAbordoPin: faseAbordoPin,
      codigoVerificado: codigoVerificado,
      faseEnRuta: codigoVerificado &&
          EstadosViaje.esEnCurso(estadoEfectivo),
      fasePickupConductor: v.uidTaxista.isNotEmpty &&
          !codigoVerificado &&
          (estadoEfectivo == EstadosViaje.aceptado ||
              estadoEfectivo == EstadosViaje.enCaminoPickup),
      esperandoConductor: v.uidTaxista.isEmpty &&
          (estadoEfectivo == EstadosViaje.pendiente ||
              estadoEfectivo == EstadosViaje.pendientePago),
    );
    if (faseAbordoPin && mostrarCodigoCliente) {
      _pinHost.prepararSheetPinAbordoVisible(
        viajeId: v.id,
        pin: ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
          viajeData: viajeData,
          codigoDesdeModelo: v.codigoVerificacion,
        ),
      );
    }
  }

  void _solicitarEnsureCodigoSiFalta(
    Viaje v,
    String codigo,
    Map<String, dynamic> viajeData,
  ) {
    if (v.codigoVerificado || _pinEnsureEnCurso) return;
    if (ViajeCodigoVerificacionHelper.uidTaxistaAsignado(
      viajeData: viajeData,
      uidTaxistaModelo: v.uidTaxista,
    ).isEmpty) {
      return;
    }
    if (!ViajeCodigoVerificacionHelper.necesitaGenerarPin(codigo)) {
      _pinEnsureViajeId = null;
      _pinEnsureUltimoIntento = null;
      return;
    }
    final DateTime ahora = DateTime.now();
    if (_pinEnsureViajeId == v.id &&
        _pinEnsureUltimoIntento != null &&
        ahora.difference(_pinEnsureUltimoIntento!) <
            const Duration(seconds: 2)) {
      return;
    }
    _pinEnsureViajeId = v.id;
    _pinEnsureUltimoIntento = ahora;
    unawaited(_ensureCodigoVerificacionViaje(v.id));
  }

  Future<void> _ensureCodigoVerificacionViaje(String viajeId) async {
    final int seq = ++_pinEnsureSeq;
    if (mounted) setState(() => _pinEnsureEnCurso = true);
    final String? pin = await ViajesRepo.ensureCodigoVerificacionViaje(viajeId);
    if (!mounted || seq != _pinEnsureSeq) return;
    setState(() {
      _pinEnsureEnCurso = false;
      if (pin == null || pin.length != 6) {
        _pinEnsureViajeId = null;
      } else {
        _ultimoPinUiMostrado = '';
        _lastLiveAbordoPinSig = '';
      }
    });
  }
  String _codigoVerificacionDesdeDoc(Viaje v, Map<String, dynamic> data) {
    return ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
      viajeData: data,
      codigoDesdeModelo: v.codigoVerificacion,
      bolaData: null,
    );
  }

  bool _clienteDebeMostrarCodigoVerificacion(
    Viaje v,
    String estadoBase,
    String codigo,
    Map<String, dynamic> viajeData,
  ) {
    final Map<String, dynamic> pinDoc = Map<String, dynamic>.from(viajeData);
    if (_clienteAbordoEnViajeDoc(viajeData, v)) {
      pinDoc['clienteAbordo'] = true;
    }
    final String estadoParaPin = _estadoEfectivoFlujoCliente(v, pinDoc);
    return ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
      viajeData: pinDoc,
      estadoNorm: estadoParaPin,
      codigoVerificado: _codigoVerificadoEnDoc(v, viajeData),
      uidTaxistaModelo: v.uidTaxista,
      clienteAbordoExtras: v.extras?['clienteAbordo'] == true,
      bolaData: null,
    );
  }

  String _watchDocUiSig(Map<String, dynamic> d) {
    final String est = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    final String pin = (d['codigoVerificacion'] ?? '').toString();
    final dynamic ex = d['extras'];
    final bool abordoExtras = ex is Map && ex['clienteAbordo'] == true;
    return '$est|${d['clienteAbordo']}|$abordoExtras|${d['codigoVerificado']}|$pin|'
        '${d['uidTaxista'] ?? d['taxistaId']}';
  }

  /// Firma mínima abordo + PIN: dispara UI en vivo aunque el stream tarde un frame.
  String _liveAbordoPinSig(Map<String, dynamic> d) {
    final String est = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    final String pin = ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
      viajeData: d,
    );
    final dynamic ex = d['extras'];
    final bool abordoExtras = ex is Map && ex['clienteAbordo'] == true;
    return '$est|${d['clienteAbordo']}|$abordoExtras|${d['codigoVerificado']}|$pin';
  }

  /// Evita setState durante build (StreamBuilder): encola el pulso abordo+PIN.
  void _encolarAbordoPinEnVivoDesdeBuild({
    required String viajeId,
    required Map<String, dynamic> d,
  }) {
    final String sig = _liveAbordoPinSig(d);
    final bool abordoUi = _clienteAbordoEnMapData(d) ||
        EstadosViaje.esAbordo(
          EstadosViaje.normalizar((d['estado'] ?? '').toString()),
        );
    if (abordoUi && d['codigoVerificado'] != true) {
      final bool pinLiveNuevo = _pinAbordoLiveViajeId != viajeId;
      _marcarPinAbordoLive(viajeId, d);
      _ajustarSyncPulseParaFaseAbordoPin(
        viajeId: viajeId,
        esperandoPinAbordo: true,
        codigoVerificado: false,
      );
      if (pinLiveNuevo) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {});
        });
      }
    }
    if (sig == _lastLiveAbordoPinSig) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _aplicarAbordoPinEnVivo(viajeId: viajeId, d: d);
    });
  }

  /// Taxista tocó «Cliente a bordo»: reflejar PIN al instante con app abierta.
  void _aplicarAbordoPinEnVivo({
    required String viajeId,
    required Map<String, dynamic> d,
  }) {
    final String sig = _liveAbordoPinSig(d);
    final String estN = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    final bool abordoUi =
        EstadosViaje.esAbordo(estN) || _clienteAbordoEnMapData(d);
    final bool codigoVerificado = d['codigoVerificado'] == true;

    if (abordoUi) {
      _marcarPinAbordoLive(viajeId, d);
      if (!codigoVerificado) {
        _ajustarSyncPulseParaFaseAbordoPin(
          viajeId: viajeId,
          esperandoPinAbordo: true,
          codigoVerificado: false,
        );
      }
    } else if (codigoVerificado && _pinAbordoLiveViajeId == viajeId) {
      _pinAbordoLiveViajeId = null;
    } else if (codigoVerificado) {
      _ajustarSyncPulseParaFaseAbordoPin(
        viajeId: viajeId,
        esperandoPinAbordo: false,
        codigoVerificado: true,
      );
    }

    final bool sigCambio = sig != _lastLiveAbordoPinSig;
    final bool pinLivePendienteUi =
        abordoUi && !codigoVerificado && _pinAbordoLiveViajeId == viajeId;
    if (!sigCambio && !pinLivePendienteUi) return;

    if (sigCambio) {
      _lastLiveAbordoPinSig = sig;
    }
    _ingestarPulsoServidorViaje(viajeId, d);

    if (abordoUi) {
      ActiveTripService.registrarViajeOperativoCliente(viajeId);
      if (ActiveTripService.flujoPostViajeClienteBloquea(viajeId)) return;
      ActiveTripService.cancelarForzarInicioClienteShellForzado();
      ActiveTripService.mantenerOverlayViajeEnShell(
        NavigationService.kOverlayClienteViajeActivo,
      );
      unawaited(_clienteViajeSyncPulseTick(viajeId));
      _notificarPinAbordoEnVivoSiCorresponde(
        viajeId: viajeId,
        d: d,
        abordoUi: abordoUi,
        codigoVerificado: codigoVerificado,
      );
      if (_pinHost._mapaDesactivadoPorError || !_pinHost._mapaPermitido) {
        _pinHost._programarReintentoMapaAutomatico(
          delay: const Duration(milliseconds: 400),
          resetIntentos: true,
        );
      }
    }

    if (mounted) setState(() {});

    void aplicarUiAbordoPin() {
      if (!mounted || !abordoUi) return;
      final Viaje v = Viaje.fromMap(viajeId, Map<String, dynamic>.from(d));
      final String pin = _codigoVerificacionDesdeDoc(v, d);
      final bool mostrarCodigoCliente =
    (_pinAbordoLiveViajeId == viajeId && !codigoVerificado) ||
        _clienteDebeMostrarCodigoVerificacion(
          v,
          estN,
          pin,
          d,
        ) ||
        (_clienteAbordoEnMapData(d) && !codigoVerificado);
      _maybeExpandirSheetAbordoCliente(
        v: v,
        viajeData: d,
        estadoEfectivo: ClienteViajeEstadoEfectivo.resolver(d),
        mostrarCodigoCliente: mostrarCodigoCliente,
        codigoVerificado: _codigoVerificadoEnDoc(v, d),
      );
      _solicitarEnsureCodigoSiFalta(v, pin, d);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => aplicarUiAbordoPin());
  }

  void _reactivarUiClienteDesdeWatchDoc({
    required String viajeId,
    required Map<String, dynamic> d,
    required String estN,
  }) {
    _ingestarPulsoServidorViaje(viajeId, d);
    final bool abordoUi =
        EstadosViaje.esAbordo(estN) || _clienteAbordoEnMapData(d);
    if (abordoUi) {
      _marcarPinAbordoLive(viajeId, d);
      ActiveTripService.registrarViajeOperativoCliente(viajeId);
      if (ActiveTripService.flujoPostViajeClienteBloquea(viajeId)) return;
      ActiveTripService.cancelarForzarInicioClienteShell();
      ActiveTripService.mantenerOverlayViajeEnShell(
        NavigationService.kOverlayClienteViajeActivo,
      );
    }
    if (mounted) setState(() {});
    if (abordoUi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final Viaje v = Viaje.fromMap(viajeId, Map<String, dynamic>.from(d));
        final String pin = (d['codigoVerificacion'] ?? '').toString();
        _maybeExpandirSheetAbordoCliente(
          v: v,
          viajeData: d,
          estadoEfectivo: ClienteViajeEstadoEfectivo.resolver(d),
          mostrarCodigoCliente: _clienteDebeMostrarCodigoVerificacion(
            v,
            estN,
            pin,
            d,
          ),
          codigoVerificado: d['codigoVerificado'] == true,
        );
        // Abordo marcado por el chofer: el PIN debe estar visible ya para dictarlo.
        _solicitarEnsureCodigoSiFalta(v, pin, d);
      });
    }
  }
  void _disposeDocWatch() {
    _viajeDocSub?.cancel();
    _viajeDocSub = null;
  }

  void _procesarAsignacionTaxistaClienteWatch({
    required String viajeId,
    required Map<String, dynamic> data,
    required String estN,
    required String tid,
  }) {
    if (CorporativoTaxistaService.debeOcultarEnAppCliente(data)) return;
    if (tid.isEmpty) {
      _ultimoTaxistaAsignadoEnWatch = '';
      return;
    }
    final String tipo =
        (data['tipoServicio'] ?? '').toString().trim().toLowerCase();
    if (tipo == 'turismo' && widget.delegarEsperaTurismoAlRouter) return;
    if (EstadosViaje.esTerminal(estN) || data['completado'] == true) return;
    final bool operativo = estN == EstadosViaje.aceptado ||
        estN == EstadosViaje.enCaminoPickup ||
        EstadosViaje.esAbordo(estN) ||
        EstadosViaje.esEnCurso(estN);
    if (!operativo) return;
    if (tid == _ultimoTaxistaAsignadoEnWatch) return;
    _ultimoTaxistaAsignadoEnWatch = tid;

    if (_pinHost._mapaDesactivadoPorError || !_pinHost._mapaPermitido) {
      _pinHost._programarReintentoMapaAutomatico(
        delay: const Duration(milliseconds: 600),
        resetIntentos: true,
      );
    }

    ActiveTripService.mantenerOverlayViajeEnShell(
      NavigationService.kOverlayClienteViajeActivo,
    );

    if (mounted) {
      final String nombre = (data['nombreTaxista'] ?? '').toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nombre.isNotEmpty
                ? '¡Conductor asignado: $nombre!'
                : '¡Tu conductor fue asignado!',
          ),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // Ya estamos en ViajeEnCursoCliente: solo UI (sheet). La navegación la
    // resuelve [ClienteShell] + overlay si el cliente estaba en tabs/home.
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pinHost._solicitarExpandirSheetCliente(
          target: _ViajeEnCursoClienteState._kViajeSheetPickupCompact,
          forzar: false,
        );
      });
    }
  }

  void _watchViajeDoc(String viajeId) {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    if (_viajeDocSub != null && _viajeIdAsignacionWatch == id) return;

    if (_viajeIdAsignacionWatch != id) {
      _viajeIdAsignacionWatch = id;
      _ultimoTaxistaAsignadoEnWatch = '';
      _lastWatchDocUiSig = '';
    }

    _disposeDocWatch();

    _viajeDocSub = FirebaseFirestore.instance
        .collection('viajes')
        .doc(id)
        .snapshots(includeMetadataChanges: true)
        .listen((DocumentSnapshot<Map<String, dynamic>> ds) async {
      if (!ds.exists) return;
      final Map<String, dynamic> d = ds.data() ?? {};
      final String estado = (d['estado'] ?? '').toString();
      final String estN = EstadosViaje.normalizar(estado);

      final String tid =
          (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();

      _procesarAsignacionTaxistaClienteWatch(
        viajeId: viajeId,
        data: d,
        estN: estN,
        tid: tid,
      );

      // uidTaxista vacío → asignado (aceptado / en camino): NO es cierre.
      if (tid.isNotEmpty &&
          _pinHost._viajeClienteSigueOperativoEnPantalla(d)) {
        _pinHost._salidaAutoSinViajeDisparada = false;
      } else {
        _pinHost._manejarViajeCerradoSiCorresponde(
          viajeId: id,
          uid: FirebaseAuth.instance.currentUser?.uid ?? '',
          data: d,
          origen: 'watchDoc',
        );
      }

      _aplicarAbordoPinEnVivo(viajeId: viajeId, d: d);

      final bool abordoWatch = _clienteAbordoEnMapData(d) ||
          EstadosViaje.esAbordo(estN);
      if (abordoWatch && d['codigoVerificado'] != true) {
        _ajustarSyncPulseParaFaseAbordoPin(
          viajeId: viajeId,
          esperandoPinAbordo: true,
          codigoVerificado: false,
        );
      }

      final String watchSig = _watchDocUiSig(d);
      if (watchSig != _lastWatchDocUiSig) {
        _lastWatchDocUiSig = watchSig;
        _reactivarUiClienteDesdeWatchDoc(
          viajeId: viajeId,
          d: d,
          estN: estN,
        );
      }

      final bool tieneTaxista = tid.isNotEmpty;
      final bool esEstadoValido = (estN == EstadosViaje.aceptado ||
          estN == EstadosViaje.enCaminoPickup);
      final bool esCambioEstado = _lastNotifiedState != estN;
      final bool noEsPendiente =
          estN != EstadosViaje.pendiente && estN != EstadosViaje.cancelado;

      if (esEstadoValido && esCambioEstado && tieneTaxista && noEsPendiente) {
        _lastNotifiedState = estN;
        ActiveTripService.mantenerOverlayViajeEnShell(
          NavigationService.kOverlayClienteViajeActivo,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tu taxista va en camino 🚕'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      // El conductor canceló → mensaje + salir de viaje en curso (no quedarse en pendiente).
      _pinHost._avisarSiConductorCancelo(d, estN, viajeId);

      // Post-viaje (recibo + calificación): solo desde [_abrirFlujoPostViaje].
      // `_postViajeFlujoIniciadoParaViajeId` evita abrir el flujo dos veces.
      _pinHost._intentarRedirigirEsperaTurismo(viajeId, d);
      _pinHost._syncTurismoReasignacion(viajeId, d);
    }, onError: (Object _) {});
  }
}
