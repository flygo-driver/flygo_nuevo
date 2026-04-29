import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Diálogo a pantalla casi completa con imagen del banner (zoom con [InteractiveViewer]).
void showPoolPromoImageDialog(
  BuildContext context, {
  required String imageUrl,
  required String title,
}) {
  final u = imageUrl.trim();
  if (u.isEmpty) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) {
      final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
      final surface = isDark ? Colors.black : Colors.white;
      final onSurface = isDark ? Colors.white : const Color(0xFF101828);
      final muted = isDark ? Colors.white54 : const Color(0xFF667085);
      final headerBg = isDark ? Colors.white10 : const Color(0xFFEFF1F5);
      final border = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Container(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    color: headerBg,
                    child: Text(
                      title.isEmpty ? 'Banner del viaje' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: onSurface, fontWeight: FontWeight.w700),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 520),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.network(
                        u,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => SizedBox(
                          height: 220,
                          child: Center(
                              child: Icon(Icons.broken_image,
                                  color: muted, size: 40)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: Icon(Icons.close, color: onSurface),
              ),
            ),
          ],
        ),
      );
    },
  );
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
    final u = Uri.tryParse(widget.videoUrl.trim());
    if (u == null) return;
    await launchUrl(u, mode: LaunchMode.externalApplication);
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
              if (_error != null) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: onSurface.withValues(alpha: 0.9)),
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: OutlinedButton.icon(
                    onPressed: _openVideoExternally,
                    icon: const Icon(Icons.open_in_browser, size: 20),
                    label: const Text('Abrir video fuera de la app'),
                  ),
                ),
              ] else if (!_inited)
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
                      height: 220,
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
              if (_inited && _error == null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _openVideoExternally,
                    icon: Icon(Icons.open_in_new,
                        size: 18, color: onSurface.withValues(alpha: 0.7)),
                    label: Text('Abrir fuera',
                        style:
                            TextStyle(color: onSurface.withValues(alpha: 0.7))),
                  ),
                ),
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

/// Franja promocional: imagen opcional, video opcional, o ambos (imagen + botón play para el video).
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
  });

  final String bannerUrl;
  final String bannerVideoUrl;
  final String title;
  final double height;
  final BorderRadius borderRadius;
  final Color textPrimary;
  final Color textMuted;
  final Color softFill;

  @override
  Widget build(BuildContext context) {
    final b = bannerUrl.trim();
    final v = bannerVideoUrl.trim();
    if (b.isEmpty && v.isEmpty) return const SizedBox.shrink();

    final hasI = b.isNotEmpty;
    final hasV = v.isNotEmpty;

    String chipText;
    if (hasI && hasV) {
      chipText = 'Toca la imagen para ampliar · ▶ para el video';
    } else if (hasI) {
      chipText = 'Toca para ampliar';
    } else {
      chipText = 'Toca para ver video';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasI)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showPoolPromoImageDialog(context,
                        imageUrl: b, title: title),
                    child: Image.network(
                      b,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: softFill,
                        alignment: Alignment.center,
                        child:
                            Icon(Icons.image_not_supported, color: textMuted),
                      ),
                    ),
                  )
                else
                  Material(
                    color: Colors.black.withValues(alpha: 0.75),
                    child: InkWell(
                      onTap: () => showPoolPromoVideoDialog(context,
                          videoUrl: v, title: title),
                      child: Center(
                        child: Icon(Icons.play_circle_fill,
                            size: 64,
                            color: textPrimary.withValues(alpha: 0.9)),
                      ),
                    ),
                  ),
                if (hasV && hasI)
                  Positioned(
                    right: 8,
                    bottom: 32,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        tooltip: 'Ver video',
                        onPressed: () => showPoolPromoVideoDialog(context,
                            videoUrl: v, title: title),
                        icon: Icon(Icons.play_circle_outline,
                            size: 36, color: textPrimary),
                      ),
                    ),
                  ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        chipText,
                        style: TextStyle(color: textPrimary, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
