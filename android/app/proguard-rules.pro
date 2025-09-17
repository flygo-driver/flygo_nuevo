# Flutter
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.app.** { *; }

# Firebase / GMS
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Gson / Protobuf (comunes)
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Recursos generados
-keep class **.R$* { *; }
