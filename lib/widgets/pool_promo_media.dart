import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flygo_nuevo/utils/pool_gira_tropical_theme.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Pantalla completa con banner (pinch para zoom).
void showPoolPromoImageDialog(
  BuildContext context, {
  required String imageUrl,
  required String title,
}) {
  final u = imageUrl.trim();
  if (u.isEmpty) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => _PoolPromoImageFullScreenPage(
        imageUrl: u,
        title: title,
      ),
    ),
  );
}

class _PoolPromoImageFullScreenPage extends StatelessWidget {
  const _PoolPromoImageFullScreenPage({
    required this.imageUrl,
    required this.title,
  });

  final String imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
                      title.isEmpty ? 'Banner del viaje' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
        ),
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 5,
        child: Center(
                      child: Image.network(
            imageUrl,
                        fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white54),
              );
            },
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
                        ),
                      ),
                    ),
      ),
    );
  }
}

/// Modos de apertura según plataforma (Safari iOS / Chrome Android).
List<LaunchMode> _poolPromoVideoExternalLaunchModes() {
  if (kIsWeb) {
    return const [LaunchMode.platformDefault, LaunchMode.externalApplication];
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return const [
        LaunchMode.externalApplication,
        LaunchMode.inAppBrowserView,
        LaunchMode.platformDefault,
      ];
    case TargetPlatform.android:
      return const [
        LaunchMode.externalApplication,
        LaunchMode.platformDefault,
        LaunchMode.inAppBrowserView,
      ];
    default:
      return const [
        LaunchMode.externalApplication,
        LaunchMode.platformDefault,
      ];
  }
}

/// Abre URL de video promocional fuera de la app (Safari / Chrome).
Future<bool> openPoolPromoVideoUrlExternally(Uri uri) async {
  for (final mode in _poolPromoVideoExternalLaunchModes()) {
    try {
      final ok = await launchUrl(uri, mode: mode);
      if (ok) return true;
    } catch (_) {
      // Siguiente modo
    }
  }
  return false;
}

/// Abre video fuera de la app con SnackBar y fallback al portapapeles.
Future<void> openPoolPromoVideoExternallyWithFeedback(
  BuildContext context,
  String videoUrl, {
  bool popRouteFirst = false,
}) async {
  final raw = videoUrl.trim();
  final uri = Uri.tryParse(raw);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace de video no válido.')),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  if (popRouteFirst) {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  final ok = await openPoolPromoVideoUrlExternally(uri);
  if (ok) {
    final msg = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? 'Abriendo video en Safari…'
        : 'Abriendo video en el navegador…';
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    return;
  }

  await Clipboard.setData(ClipboardData(text: raw));
  final failMsg = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
      ? 'No se pudo abrir Safari. Enlace copiado — pegalo en Safari.'
      : 'No se pudo abrir el reproductor. Enlace copiado — pegalo en Chrome.';
  messenger.showSnackBar(SnackBar(content: Text(failMsg)));
}

/// Reproductor simple en diálogo (video promocional del pool).
void showPoolPromoVideoDialog(
  BuildContext context, {
  required String videoUrl,
  required String title,
}) {
  final u = videoUrl.trim();
  if (u.isEmpty) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: _PoolVideoDialogBody(videoUrl: u, title: title),
      );
    },
  );
}

class _PoolVideoDialogBody extends StatefulWidget {
  const _PoolVideoDialogBody({required this.videoUrl, required this.title});

  final String videoUrl;
  final String title;

  @override
  State<_PoolVideoDialogBody> createState() => _PoolVideoDialogBodyState();
}

class _PoolVideoDialogBodyState extends State<_PoolVideoDialogBody> {
  VideoPlayerController? _controller;
  bool _inited = false;
  String? _error;
  bool _codecLikelyUnsupported = false;
  bool _openingExternal = false;

  static bool _urlLooksLikeMov(String url) {
    final u = url.toLowerCase();
    return u.contains('.mov') || u.contains('video%2fquicktime');
  }

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.videoUrl.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _error = 'URL de video no válida.';
      return;
    }

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        _urlLooksLikeMov(widget.videoUrl)) {
      _codecLikelyUnsupported = true;
    }

    final c = VideoPlayerController.networkUrl(
      uri,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..setLooping(true);
    _controller = c;

    c.addListener(_onControllerTick);
    c.initialize().then((_) async {
      if (!mounted) return;
      if (c.value.hasError) {
        setState(() {
          _error = c.value.errorDescription ?? 'Error del reproductor';
        });
        return;
      }
      final sz = c.value.size;
      if (sz.width < 1 || sz.height < 1) {
        setState(() {
          _inited = false;
          _error =
              'Este formato de video no se puede mostrar en el teléfono (p. ej. .mov de iPhone en Android). '
              'Sube un MP4 (H.264) o abre el enlace abajo.';
        });
        return;
      }
      setState(() => _inited = true);
      await c.setVolume(1);
      await c.seekTo(Duration.zero);
      await c.play();
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    });
  }

  void _onControllerTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    if (c.value.hasError && _error == null) {
      setState(() {
        _error = c.value.errorDescription ?? 'Error al reproducir';
        _inited = false;
      });
      return;
    }
    setState(() {});
  }

  Future<void> _openVideoExternally() async {
    if (_openingExternal) return;
    setState(() => _openingExternal = true);
    await openPoolPromoVideoExternallyWithFeedback(
      context,
      widget.videoUrl,
      popRouteFirst: true,
    );
  }

  Widget _externalOpenButton(Color onSurface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: OutlinedButton.icon(
        onPressed: _openingExternal ? null : _openVideoExternally,
        icon: _openingExternal
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.open_in_new, size: 18),
        label: Text(
          _openingExternal ? 'Abriendo…' : 'Abrir video fuera de la app',
        ),
      ),
    );
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      c.removeListener(_onControllerTick);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF101010) : Colors.white;
    final onSurface = isDark ? Colors.white : const Color(0xFF101828);
    final headerBg = isDark ? Colors.white10 : const Color(0xFFEFF1F5);
    final border = isDark ? Colors.white24 : const Color(0xFFD0D5DD);

    return Stack(
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: headerBg,
                child: Text(
                  widget.title.isEmpty ? 'Video promocional' : widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: onSurface, fontWeight: FontWeight.w700),
                ),
              ),
              if (_codecLikelyUnsupported && _error == null && !_inited)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    'En Android los videos .mov de iPhone a veces no se ven aquí. Si pasa, usa MP4 o "Abrir fuera de la app".',
                    style: TextStyle(
                        color: onSurface.withValues(alpha: 0.75), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: onSurface.withValues(alpha: 0.9)),
                    textAlign: TextAlign.center,
                  ),
                )
              else if (!_inited)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(),
                )
              else
                Builder(
                  builder: (context) {
                    final c = _controller!;
                    return SizedBox(
                      width: double.infinity,
                      height: 280,
                      child: ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: c.value.aspectRatio == 0
                                ? 16 / 9
                                : c.value.aspectRatio,
                            child: VideoPlayer(c),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (_inited && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () async {
                          final c = _controller;
                          if (c == null) return;
                          if (c.value.isPlaying) {
                            await c.pause();
                          } else {
                            await c.play();
                          }
                          if (mounted) setState(() {});
                        },
                        icon: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: onSurface,
                        ),
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          _controller!,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: isDark
                                ? Colors.greenAccent
                                : const Color(0xFF0F9D58),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _externalOpenButton(onSurface),
            ],
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: onSurface),
          ),
        ),
      ],
    );
  }
}

/// Logo de agencia/tour arriba del banner promocional (detalle y lista).
class PoolAgencyLogoHeader extends StatelessWidget {
  const PoolAgencyLogoHeader({
    super.key,
    required this.logoUrl,
    required this.title,
    this.compact = false,
    this.accent = const Color(0xFF00C9A7),
  });

  final String logoUrl;
  final String title;
  final bool compact;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final logo = logoUrl.trim();
    final label = title.trim();
    if (logo.isEmpty && label.isEmpty) return const SizedBox.shrink();

    final tropical = PoolGiraTropicalTheme.of(context);
    final double box = compact ? 96.0 : 132.0;
    final double radius = compact ? 16.0 : 20.0;

    Widget logoWidget;
    if (logo.isNotEmpty) {
      logoWidget = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: () => showPoolPromoImageDialog(
            context,
            imageUrl: logo,
            title: label.isEmpty ? 'Agencia / tour' : label,
          ),
          child: Container(
            width: box,
            height: box,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: accent.withValues(alpha: compact ? 0.4 : 0.5),
                width: compact ? 2 : 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: tropical.shadow,
                  blurRadius: compact ? 10 : 16,
                  offset: Offset(0, compact ? 3 : 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  logo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: tropical.cardFill,
                    child: Icon(
                      Icons.business,
                      size: compact ? 32 : 44,
                      color: accent.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                if (!compact)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.black.withValues(alpha: 0.5),
                      child: const Text(
                        'Toca para ampliar',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      logoWidget = Container(
        width: box,
        height: box,
        decoration: BoxDecoration(
          color: tropical.cardFill,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: tropical.cardBorder),
        ),
        child: Icon(Icons.business, size: compact ? 36 : 48, color: accent),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logoWidget,
        if (label.isNotEmpty) ...[
          SizedBox(height: compact ? 6 : 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: compact ? 14 : 16,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ],
    );
  }
}

/// Franja promocional: imagen opcional, video opcional, o ambos (imagen + botón play para el video).
/// Con [routeLabel] / [priceLabel] activa diseño hero con overlay (detalle cliente).
class PoolPromoStrip extends StatelessWidget {
  const PoolPromoStrip({
    super.key,
    required this.bannerUrl,
    required this.bannerVideoUrl,
    required this.title,
    required this.height,
    required this.borderRadius,
    required this.textPrimary,
    required this.textMuted,
    required this.softFill,
    this.routeLabel,
    this.originLabel,
    this.destinationLabel,
    this.pickupPoints = const <String>[],
    this.priceLabel,
    this.dateLabel,
    this.publisherLabel,
    this.agencyLogoUrl,
    this.heroAccent = const Color(0xFF00C9A7),
    this.mediaOnly = false,
  });

  final String bannerUrl;
  final String bannerVideoUrl;
  final String title;
  final double height;
  final BorderRadius borderRadius;
  final Color textPrimary;
  final Color textMuted;
  final Color softFill;
  final String? routeLabel;
  final String? originLabel;
  final String? destinationLabel;
  final List<String> pickupPoints;
  final String? priceLabel;
  final String? dateLabel;
  final String? publisherLabel;
  /// Logo agencia/tour visible sobre el hero (toca para ampliar).
  final String? agencyLogoUrl;
  final Color heroAccent;
  /// Solo foto/video sin overlays (detalle cliente: info va en tarjetas abajo).
  final bool mediaOnly;

  bool get _heroMode =>
      !mediaOnly &&
      ((routeLabel ?? '').trim().isNotEmpty ||
          (originLabel ?? '').trim().isNotEmpty ||
          (destinationLabel ?? '').trim().isNotEmpty ||
          (priceLabel ?? '').trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final b = bannerUrl.trim();
    final v = bannerVideoUrl.trim();
    if (b.isEmpty && v.isEmpty) return const SizedBox.shrink();

    final tropical = PoolGiraTropicalTheme.of(context);
    final hasI = b.isNotEmpty;
    final hasV = v.isNotEmpty;
    final logo = (agencyLogoUrl ?? '').trim();
    final hasLogo = logo.isNotEmpty;

    String chipText;
    if (hasI && hasV) {
      chipText = 'Toca la imagen · ▶ video';
    } else if (hasI) {
      chipText = 'Toca para ampliar';
    } else {
      chipText = 'Toca para ver video';
    }

    final media = ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
            if (mediaOnly) const ColoredBox(color: Colors.black),
                if (hasI)
              Image.network(
                      b,
                      fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _TropicalPlaceholder(
                  tropical: tropical,
                  softFill: softFill,
                  textMuted: textMuted,
                    ),
                  )
                else
              _TropicalPlaceholder(
                tropical: tropical,
                softFill: softFill,
                textMuted: textMuted,
                showPlay: true,
                onPlay: () => showPoolPromoVideoDialog(context,
                          videoUrl: v, title: title),
              ),
            if (_heroMode) ...[
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: tropical.heroGradient,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -20,
                right: -20,
                child: IgnorePointer(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          tropical.sand.withValues(alpha: 0.55),
                          tropical.sunset.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: tropical.overlayBottom,
                      stops: const [0.0, 0.42, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: IgnorePointer(
                  child: _RaiHeroBadge(tropical: tropical),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IgnorePointer(
                  child: _TropicalVeranoChip(tropical: tropical),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((publisherLabel ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            publisherLabel!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      if ((originLabel ?? '').trim().isNotEmpty ||
                          (destinationLabel ?? '').trim().isNotEmpty)
                        _HeroRouteSplit(
                          origin: (originLabel ?? '').trim(),
                          destination: (destinationLabel ?? '').trim(),
                          tropical: tropical,
                        )
                      else
                        Text(
                          (routeLabel ?? title).trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: -0.4,
                            shadows: [
                              Shadow(
                                color: tropical.coral.withValues(alpha: 0.45),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      if (pickupPoints.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final p in pickupPoints.take(3))
                              _HeroParadaChip(label: p, tropical: tropical),
                            if (pickupPoints.length > 3)
                              _HeroParadaChip(
                                label: '+${pickupPoints.length - 3} paradas',
                                tropical: tropical,
                                muted: true,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if ((dateLabel ?? '').trim().isNotEmpty)
                            _HeroChip(
                              icon: Icons.wb_sunny_outlined,
                              label: dateLabel!.trim(),
                              tropical: tropical,
                            ),
                          if ((priceLabel ?? '').trim().isNotEmpty)
                            _HeroChip(
                              icon: Icons.confirmation_number_outlined,
                              label: priceLabel!.trim(),
                              tropical: tropical,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: IgnorePointer(
                      child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen,
                              size: 14, color: Colors.white.withValues(alpha: 0.9)),
                          const SizedBox(width: 4),
                          Text(
                            'Toca para ver completo',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (hasI)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => showPoolPromoImageDialog(
                      context,
                      imageUrl: b,
                      title: title,
                    ),
                  ),
                ),
              ),
            if (!hasI && hasV)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => showPoolPromoVideoDialog(
                      context,
                      videoUrl: v,
                      title: title,
                    ),
                  ),
                ),
              ),
            if (hasLogo && _heroMode)
              Positioned(
                right: 12,
                top: 52,
                child: _AgencyLogoHeroBadge(
                  logoUrl: logo,
                  label: (publisherLabel ?? title).trim(),
                    ),
                  ),
                if (hasV && hasI)
                  Positioned(
                    right: 8,
                bottom: _heroMode ? 92 : 32,
                    child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        tooltip: 'Ver video',
                        onPressed: () => showPoolPromoVideoDialog(context,
                            videoUrl: v, title: title),
                    icon: const Icon(Icons.play_circle_outline,
                        size: 36, color: Colors.white),
                      ),
                    ),
                  ),
            if (hasV)
              Positioned(
                top: hasI ? null : 10,
                right: hasI ? null : 10,
                left: hasI ? 10 : null,
                bottom: hasI ? (_heroMode ? 88 : 36) : null,
                child: _PoolPromoAbrirFueraChip(videoUrl: v),
              ),
            if (!_heroMode)
                Positioned(
                left: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        chipText,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );

    if (!_heroMode) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [media],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: tropical.frameGradient,
        boxShadow: [
          BoxShadow(
            color: tropical.shadow,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: tropical.coral.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: media,
    );
  }
}

/// Chip sobre el banner: abre el video en Safari/Chrome sin pasar por el diálogo.
class _PoolPromoAbrirFueraChip extends StatelessWidget {
  const _PoolPromoAbrirFueraChip({required this.videoUrl});

  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            openPoolPromoVideoExternallyWithFeedback(context, videoUrl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_in_new,
                size: 14,
                color: Colors.white.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 4),
              Text(
                'Abrir fuera',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TropicalPlaceholder extends StatelessWidget {
  const _TropicalPlaceholder({
    required this.tropical,
    required this.softFill,
    required this.textMuted,
    this.showPlay = false,
    this.onPlay,
  });

  final PoolGiraTropicalColors tropical;
  final Color softFill;
  final Color textMuted;
  final bool showPlay;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tropical.sunset.withValues(alpha: 0.85),
            tropical.sand.withValues(alpha: 0.75),
            tropical.ocean.withValues(alpha: 0.9),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: showPlay
          ? Icon(Icons.play_circle_fill,
              size: 64, color: Colors.white.withValues(alpha: 0.95))
          : Icon(Icons.beach_access, size: 48, color: textMuted),
    );
    if (showPlay && onPlay != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: onPlay, child: body),
      );
    }
    return body;
  }
}

class _TropicalVeranoChip extends StatelessWidget {
  const _TropicalVeranoChip({required this.tropical});

  final PoolGiraTropicalColors tropical;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tropical.coral.withValues(alpha: 0.85),
            tropical.sunset.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: tropical.sunset.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wb_sunny, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'GIRA VERANO',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaiHeroBadge extends StatelessWidget {
  const _RaiHeroBadge({required this.tropical});

  final PoolGiraTropicalColors tropical;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tropical.lagoon.withValues(alpha: 0.75)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RaiHeaderLogo(height: 18, semanticLabel: null),
          SizedBox(width: 6),
          Text(
            'RAI Driver',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgencyLogoHeroBadge extends StatelessWidget {
  const _AgencyLogoHeroBadge({
    required this.logoUrl,
    required this.label,
  });

  final String logoUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showPoolPromoImageDialog(
          context,
          imageUrl: logoUrl,
          title: label.isEmpty ? 'Agencia / tour' : label,
        ),
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                logoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Icon(Icons.business, color: Colors.white70, size: 36),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  color: Colors.black.withValues(alpha: 0.55),
                  child: const Text(
                    'Toca logo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
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

/// Panel detallado: salida, paradas y destino (visible al abrir la gira).
class PoolRutaRecorridoCard extends StatelessWidget {
  const PoolRutaRecorridoCard({
    super.key,
    required this.origen,
    required this.destino,
    required this.paradas,
    this.fechaLabel,
    this.fechaLabels,
    this.sentidoLabel,
    this.cuposLabel,
    this.estiloOscuroRojo = false,
  });

  final String origen;
  final String destino;
  final List<String> paradas;
  final String? fechaLabel;
  final List<String>? fechaLabels;
  final String? sentidoLabel;
  final String? cuposLabel;
  final bool estiloOscuroRojo;

  static const Color _kOscuroFondo = Color(0xFF0A0A0A);
  static const Color _kOscuroBorde = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final tropical = PoolGiraTropicalTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = estiloOscuroRojo
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF101828));
    final textMuted = estiloOscuroRojo
        ? const Color(0xFF9CA3AF)
        : (isDark ? Colors.white60 : const Color(0xFF667085));
    final accent = estiloOscuroRojo ? _kOscuroBorde : tropical.ocean;
    final accent2 = estiloOscuroRojo ? const Color(0xFFFBBF24) : tropical.sunset;
    final accent3 = estiloOscuroRojo ? const Color(0xFFFCD34D) : tropical.lagoon;
    final accent4 = estiloOscuroRojo ? _kOscuroBorde : tropical.coral;

    final o = origen.trim().isEmpty ? '—' : origen.trim();
    final d = destino.trim().isEmpty ? '—' : destino.trim();
    final stops = paradas.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final List<String> fechasPill = <String>[
      ...?fechaLabels?.where((e) => e.trim().isNotEmpty),
      if ((fechaLabels == null || fechaLabels!.isEmpty) &&
          (fechaLabel ?? '').trim().isNotEmpty)
        fechaLabel!.trim(),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: estiloOscuroRojo
          ? BoxDecoration(
              color: _kOscuroFondo,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kOscuroBorde, width: 1.5),
            )
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tropical.ocean.withValues(alpha: isDark ? 0.14 : 0.08),
                  tropical.sunset.withValues(alpha: isDark ? 0.1 : 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tropical.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: tropical.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, color: accent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Recorrido de la gira',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          if (fechasPill.isNotEmpty ||
              (sentidoLabel ?? '').trim().isNotEmpty ||
              (cuposLabel ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final linea in fechasPill)
                  _InfoPill(
                    icon: Icons.schedule,
                    label: linea,
                    color: accent2,
                  ),
                if ((sentidoLabel ?? '').trim().isNotEmpty)
                  _InfoPill(
                    icon: Icons.swap_horiz_rounded,
                    label: sentidoLabel!.trim(),
                    color: accent3,
                  ),
                if ((cuposLabel ?? '').trim().isNotEmpty)
                  _InfoPill(
                    icon: Icons.event_seat_outlined,
                    label: cuposLabel!.trim(),
                    color: accent,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _RutaTimelineStop(
            icon: Icons.trip_origin,
            iconColor: accent,
            lineColor: accent3,
            title: 'Sale desde',
            subtitle: o,
            isFirst: true,
            isLast: stops.isEmpty,
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
          for (var i = 0; i < stops.length; i++)
            _RutaTimelineStop(
              icon: Icons.place_outlined,
              iconColor: accent2,
              lineColor: accent3,
              title: 'Parada ${i + 1}',
              subtitle: stops[i],
              isFirst: false,
              isLast: false,
              textPrimary: textPrimary,
              textMuted: textMuted,
            ),
          _RutaTimelineStop(
            icon: Icons.flag_rounded,
            iconColor: accent4,
            lineColor: accent3,
            title: 'Llega a',
            subtitle: d,
            isFirst: false,
            isLast: true,
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
          if (stops.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Sin paradas intermedias publicadas — salida directa al destino.',
              style: TextStyle(color: textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ícono según el texto del ítem incluido (Buggy, comida, guía, etc.).
IconData poolIncluyeIcon(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('comida') ||
      s.contains('almuerzo') ||
      s.contains('bebida') ||
      s.contains('desayuno')) {
    return Icons.restaurant_rounded;
  }
  if (s.contains('buggy') ||
      s.contains('motor') ||
      s.contains('vehic') ||
      s.contains('transporte')) {
    return Icons.directions_car_filled_rounded;
  }
  if (s.contains('bote') || s.contains('barco') || s.contains('catamaran')) {
    return Icons.directions_boat_filled_rounded;
  }
  if (s.contains('guia') || s.contains('guía') || s.contains('guian')) {
    return Icons.record_voice_over_rounded;
  }
  if (s.contains('snorkel') || s.contains('buceo') || s.contains('mar')) {
    return Icons.scuba_diving_rounded;
  }
  if (s.contains('foto') || s.contains('video')) {
    return Icons.photo_camera_rounded;
  }
  if (s.contains('entrada') ||
      s.contains('ticket') ||
      s.contains('parque')) {
    return Icons.confirmation_number_rounded;
  }
  if (s.contains('hotel') || s.contains('hosped')) {
    return Icons.hotel_rounded;
  }
  if (s.contains('seguro') || s.contains('asist')) {
    return Icons.health_and_safety_rounded;
  }
  return Icons.check_circle_rounded;
}

/// Todo lo que incluye la gira — tarjetas grandes para motivar la reserva.
class PoolGiraIncluyeCard extends StatelessWidget {
  const PoolGiraIncluyeCard({
    super.key,
    required this.items,
    this.estiloOscuroRojo = false,
  });

  final List<String> items;
  final bool estiloOscuroRojo;

  static const Color _kOscuroFondo = Color(0xFF0A0A0A);
  static const Color _kOscuroBorde = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final tropical = PoolGiraTropicalTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = estiloOscuroRojo
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF101828));
    final textMuted = estiloOscuroRojo
        ? const Color(0xFF9CA3AF)
        : (isDark ? Colors.white60 : const Color(0xFF667085));
    final clean =
        items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (clean.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: estiloOscuroRojo
          ? BoxDecoration(
              color: _kOscuroFondo,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kOscuroBorde, width: 1.5),
            )
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tropical.sunset.withValues(alpha: isDark ? 0.16 : 0.1),
                  tropical.sand.withValues(alpha: isDark ? 0.12 : 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tropical.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: tropical.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: estiloOscuroRojo
                        ? [_kOscuroBorde, const Color(0xFFFBBF24)]
                        : [tropical.sunset, tropical.ocean],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.star_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Todo lo que incluye tu cupo',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reservá con confianza: esto va incluido en la experiencia.',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 340 ? 2 : 1;
              final tileW = cols == 2
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in clean)
                    SizedBox(
                      width: tileW,
                      child: _IncluyeTile(
                        label: item,
                        icon: poolIncluyeIcon(item),
                        tropical: tropical,
                        textPrimary: textPrimary,
                        estiloOscuroRojo: estiloOscuroRojo,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IncluyeTile extends StatelessWidget {
  const _IncluyeTile({
    required this.label,
    required this.icon,
    required this.tropical,
    required this.textPrimary,
    this.estiloOscuroRojo = false,
  });

  final String label;
  final IconData icon;
  final PoolGiraTropicalColors tropical;
  final Color textPrimary;
  final bool estiloOscuroRojo;

  static const Color _kOscuroBorde = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: estiloOscuroRojo
            ? const Color(0xFF141414)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: estiloOscuroRojo
              ? _kOscuroBorde.withValues(alpha: 0.65)
              : tropical.lagoon.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: estiloOscuroRojo
                    ? [
                        _kOscuroBorde.withValues(alpha: 0.9),
                        const Color(0xFFFBBF24).withValues(alpha: 0.9),
                      ]
                    : [
                        tropical.ocean.withValues(alpha: 0.85),
                        tropical.lagoon.withValues(alpha: 0.85),
                      ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.25,
              ),
            ),
          ),
          Icon(
            Icons.check,
            color: estiloOscuroRojo ? _kOscuroBorde : tropical.ocean,
            size: 18,
          ),
        ],
      ),
    );
  }
}

/// Plan del viaje, recomendaciones y qué llevar.
class PoolGiraPlanLlevarCard extends StatelessWidget {
  const PoolGiraPlanLlevarCard({
    super.key,
    required this.texto,
    this.estiloOscuroRojo = false,
  });

  final String texto;
  final bool estiloOscuroRojo;

  static const Color _kOscuroFondo = Color(0xFF0A0A0A);
  static const Color _kOscuroBorde = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final tropical = PoolGiraTropicalTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = estiloOscuroRojo
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF101828));
    final textMuted = estiloOscuroRojo
        ? const Color(0xFF9CA3AF)
        : (isDark ? Colors.white60 : const Color(0xFF667085));
    final t = texto.trim();
    if (t.isEmpty) return const SizedBox.shrink();

    final lineas = t
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: estiloOscuroRojo
          ? BoxDecoration(
              color: _kOscuroFondo,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kOscuroBorde, width: 1.5),
            )
          : BoxDecoration(
              color: tropical.cardFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tropical.cardBorder, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: tropical.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: estiloOscuroRojo
                      ? _kOscuroBorde.withValues(alpha: 0.18)
                      : tropical.lagoon.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: estiloOscuroRojo
                        ? _kOscuroBorde
                        : tropical.lagoon.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  Icons.backpack_outlined,
                  color: estiloOscuroRojo ? _kOscuroBorde : tropical.ocean,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plan del viaje y qué debes llevar',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Preparate con tiempo — así disfrutás la gira al máximo.',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (lineas.length <= 1)
            Text(
              t,
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            ...lineas.map((linea) {
              final lower = linea.toLowerCase();
              final bool esLlevar = lower.contains('llevar') ||
                  lower.contains('traer') ||
                  lower.contains('recomend') ||
                  lower.contains('indispensable') ||
                  lower.contains('no olvid');
              final IconData icon = esLlevar
                  ? Icons.luggage_outlined
                  : Icons.check_circle_outline_rounded;
              final Color iconColor = estiloOscuroRojo
                  ? (esLlevar ? const Color(0xFFFBBF24) : _kOscuroBorde)
                  : (esLlevar ? tropical.coral : tropical.ocean);
              final String textoLinea = linea.replaceFirst(RegExp(r'^[-•*]\s*'), '');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(icon, size: 18, color: iconColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        textoLinea,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 15,
                          height: 1.45,
                          fontWeight:
                              esLlevar ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: estiloOscuroRojo
                    ? [
                        _kOscuroBorde.withValues(alpha: 0.16),
                        const Color(0xFFFBBF24).withValues(alpha: 0.12),
                      ]
                    : [
                        tropical.ocean.withValues(alpha: 0.12),
                        tropical.sunset.withValues(alpha: 0.1),
                      ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: estiloOscuroRojo
                    ? _kOscuroBorde.withValues(alpha: 0.55)
                    : tropical.ocean.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.celebration_outlined,
                  color: estiloOscuroRojo ? _kOscuroBorde : tropical.sunset,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cupos limitados — reservá hoy y asegurá tu lugar en esta salida.',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RutaTimelineStop extends StatelessWidget {
  const _RutaTimelineStop({
    required this.icon,
    required this.iconColor,
    required this.lineColor,
    required this.title,
    required this.subtitle,
    required this.isFirst,
    required this.isLast,
    required this.textPrimary,
    required this.textMuted,
  });

  final IconData icon;
  final Color iconColor;
  final Color lineColor;
  final String title;
  final String subtitle;
  final bool isFirst;
  final bool isLast;
  final Color textPrimary;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                if (!isFirst)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: lineColor.withValues(alpha: 0.45),
                    ),
                  ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: iconColor, width: 2),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: lineColor.withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: isFirst ? 0 : 4,
                bottom: isLast ? 0 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRouteSplit extends StatelessWidget {
  const _HeroRouteSplit({
    required this.origin,
    required this.destination,
    required this.tropical,
  });

  final String origin;
  final String destination;
  final PoolGiraTropicalColors tropical;

  @override
  Widget build(BuildContext context) {
    final o = origin.isEmpty ? '—' : origin;
    final d = destination.isEmpty ? '—' : destination;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DESDE',
                style: TextStyle(
                  color: tropical.sand.withValues(alpha: 0.95),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                o,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: tropical.sand,
              size: 20,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'HACIA',
                style: TextStyle(
                  color: tropical.sand.withValues(alpha: 0.95),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                d,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroParadaChip extends StatelessWidget {
  const _HeroParadaChip({
    required this.label,
    required this.tropical,
    this.muted = false,
  });

  final String label;
  final PoolGiraTropicalColors tropical;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: muted ? 0.35 : 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tropical.lagoon.withValues(alpha: muted ? 0.35 : 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!muted)
            Icon(Icons.place_outlined, size: 12, color: tropical.sand),
          if (!muted) const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: muted ? 0.85 : 0.95),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    required this.tropical,
  });

  final IconData icon;
  final String label;
  final PoolGiraTropicalColors tropical;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tropical.chipFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tropical.chipBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
