// lib/utils/flags.dart
/// Si es true y hay API Key, usamos Google Directions para km exactos por carretera.
/// Si falla, tu lógica cae en Haversine (sin romper nada).
const bool kUseDirectionsForDistance = true;
