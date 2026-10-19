# R8 rules for PostBox release builds.
#
# A release build with R8 full mode can break Flutter plugins that use Kotlin
# coroutines + Pigeon, which shows up at startup as
#   NoSuchMethodError: no non-static method ...SharedPreferencesApiRegistrar.getAll(...)
# Keeping the plugin classes avoids it. Narrow these rules later if APK size matters.
-keep class io.flutter.plugins.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.llfbandit.app_links.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**
