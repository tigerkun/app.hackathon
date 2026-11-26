# SafeSphere ProGuard / R8 keep rules (used when isMinifyEnabled = true in release)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep flutter_secure_storage / Tink & biometric classes if R8 shrinks plugins
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.biometric.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
