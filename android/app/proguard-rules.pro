# Keep what the notification packages need when the app is shrunk.

# flutter_local_notifications (phone notification while the app is open)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*

# Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }

# Flutter (Play Store split parts, not used by this app)
-dontwarn com.google.android.play.core.**
