/// Banners promocionales de giras por cupos (hasta 3 imágenes + compat. [bannerUrl]).
abstract final class PoolGiraBannerUrls {
  PoolGiraBannerUrls._();

  static const int maxCount = 3;

  /// Lee lista unificada desde Firestore (`bannerUrls` + `bannerUrl` legacy).
  static List<String> fromPool(Map<String, dynamic> pool) {
    final out = <String>[];
    void add(String raw) {
      final u = raw.trim();
      if (u.isEmpty) return;
      if (out.contains(u)) return;
      out.add(u);
    }

    final list = pool['bannerUrls'];
    if (list is List) {
      for (final e in list) {
        add(e.toString());
      }
    }
    add((pool['bannerUrl'] ?? '').toString());
    return out.length > maxCount ? out.sublist(0, maxCount) : out;
  }

  static String primary(Map<String, dynamic> pool) {
    final urls = fromPool(pool);
    return urls.isEmpty ? '' : urls.first;
  }

  static List<String> sanitizeForSave(Iterable<String> raw) {
    final out = <String>[];
    for (final e in raw) {
      final u = e.trim();
      if (u.isEmpty) continue;
      if (out.contains(u)) continue;
      out.add(u);
      if (out.length >= maxCount) break;
    }
    return out;
  }
}
