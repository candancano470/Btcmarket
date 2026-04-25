# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# WebView
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
}

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }