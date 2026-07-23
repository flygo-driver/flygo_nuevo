import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_radius.dart';

/// Mapa protagonista en la pantalla Viajes (solo visual).
class PoolViajesMapaHero extends StatelessWidget {
  const PoolViajesMapaHero({
    super.key,
    required this.latitude,
    required this.longitude,
    this.bearing,
  });

  final double latitude;
  final double longitude;
  final double? bearing;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.32;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RaiDsRadius.xxl),
        child: SizedBox(
          height: height.clamp(180, 320),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(latitude, longitude),
                  zoom: 14.2,
                  bearing: bearing ?? 0,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                liteModeEnabled: false,
                style: _darkMapStyle,
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: RaiDsColors.card.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: RaiDsColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.near_me_rounded,
                          color: RaiDsColors.neon, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Tu zona',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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

const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0d0d0d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0d0d0d"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1c1c1c"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#242424"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#090909"}]}
]
''';
