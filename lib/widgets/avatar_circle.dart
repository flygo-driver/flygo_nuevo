import 'package:flutter/material.dart';

class AvatarCircle extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final double size;
  final VoidCallback? onTap;

  const AvatarCircle({
    super.key,
    this.imageUrl,
    this.name,
    this.size = 72,
    this.onTap,
  });

  String _initials(String? n) {
    final s = (n ?? '').trim();
    if (s.isEmpty) return '👤';
    final parts = s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '👤';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    final a = parts.first.substring(0, 1).toUpperCase();
    final b = parts.last.substring(0, 1).toUpperCase();
    return '$a$b';
  }

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;

    Widget avatar;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      avatar = ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(radius),
        ),
      );
    } else {
      avatar = _fallback(radius);
    }

    if (onTap != null) {
      avatar = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: avatar,
        ),
      );
    }

    return avatar;
  }

  Widget _fallback(double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF1F1F1F),
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
