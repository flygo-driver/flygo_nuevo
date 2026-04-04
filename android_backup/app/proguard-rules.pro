# ==========================
# Flutter / Plugins
# ==========================
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.app.** { *; }
-dontwarn io.flutter.**

# ==========================
# Firebase / Google Play Services
# ==========================
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Inicialización Firebase / Componentes
-keep class com.google.firebase.provider.FirebaseInitProvider { *; }
-keep class com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.firebase.**Registrar { *; }

# ==========================
# Firebase Messaging / Notificaciones
# ==========================
-keep class ** extends com.google.firebase.messaging.FirebaseMessagingService { *; }
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.messaging.**

# NotificationCompat builder
-keep class androidx.core.app.NotificationCompat$Builder { *; }
-dontwarn androidx.core.app.**

# ==========================
# WorkManager (background tasks)
# ==========================
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# ==========================
# flutter_local_notifications / audioplayers
# (PAQUETE ANTIGUO - mantener)
# ==========================
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# ==========================
# flutter_local_notifications (PAQUETE OFICIAL ACTUAL)
# >>> Estas dos líneas son las que faltaban <<<
# ==========================
-keep class io.flutter.plugins.flutter_local_notifications.** { *; }
-dontwarn io.flutter.plugins.flutter_local_notifications.**

# ==========================
# Google Places / Maps / Utils
# ==========================
-keep class com.google.android.libraries.places.** { *; }
-dontwarn com.google.android.libraries.places.**
-keep class com.google.maps.android.** { *; }
-dontwarn com.google.maps.android.**

# Gson / Protobuf (por si acaso)
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# ExoPlayer (si alguna lib lo trae)
-dontwarn com.google.android.exoplayer2.**

# Recursos generados
-keep class **.R$* { *; }

# OkHttp/Okio/Retrofit (opcional)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**

# ==========================
# Play Core (SplitCompat / SplitInstall)
# ==========================
-keep class com.google.android.play.** { *; }
-dontwarn com.google.android.play.**
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-dontwarn io.flutter.embedding.**

# ==========================
# Tu paquete (por si hay reflexión o nombres en Manifest)
# ==========================
-keep class com.flygo.rd.** { *; }
