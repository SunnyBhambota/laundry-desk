#!/usr/bin/env bash
# Shared Android project settings for every CI job.
set -e
flutter create --org com.brotrix --project-name laundry_desk --platforms android .
F=android/app/build.gradle.kts
[ -f "$F" ] || F=android/app/build.gradle
sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' "$F"
# Play Store / Firebase app id (fixed forever once published): com.brotrix.laundry
sed -i 's/applicationId = "com.brotrix.laundry_desk"/applicationId = "com.brotrix.laundry"/; s/applicationId "com.brotrix.laundry_desk"/applicationId "com.brotrix.laundry"/' "$F"
grep -n "applicationId" "$F"
sed -i '0,/^android {/s//android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }/' "$F"
M=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="laundry_desk"/android:label="LaundryCase"/' "$M"
# WhatsApp / phone / maps links (url_launcher) on Android 11+
grep -q '<queries>' "$M" && sed -i 's#<queries>#<queries>\n        <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="https" /></intent>\n        <intent><action android:name="android.intent.action.DIAL" /><data android:scheme="tel" /></intent>#' "$M"
# GPS for delivery tracking, internet for cloud + fonts
sed -i '0,/<application/s##<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.WAKE_LOCK" />\n    <uses-permission android:name="android.permission.USE_BIOMETRIC" />\n    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />\n    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />\n    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />\n    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />\n    <application#' "$M"
# fingerprint unlock (local_auth) needs a FragmentActivity and an AppCompat theme
MA=$(find android/app/src/main -name 'MainActivity.kt' | head -1)
sed -i 's/FlutterActivity/FlutterFragmentActivity/g' "$MA"
cat "$MA"
for st in android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml; do
  [ -f "$st" ] && sed -i 's/parent="@android:style\/Theme.Light.NoTitleBar"/parent="Theme.AppCompat.Light.NoActionBar"/; s/parent="@android:style\/Theme.Black.NoTitleBar"/parent="Theme.AppCompat.NoActionBar"/' "$st"
done
grep -n "parent=" android/app/src/main/res/values/styles.xml || true
printf '\ndependencies {\n    implementation("androidx.appcompat:appcompat:1.7.0")\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' >> "$F"
# flutter_local_notifications needs Java 8+ API desugaring
if grep -q "compileOptions {" "$F"; then
  sed -i '0,/compileOptions {/s//compileOptions {\n        isCoreLibraryDesugaringEnabled = true/' "$F"
fi
grep -n "Desugaring\|desugar" "$F"
grep -n "minSdk" "$F"
grep -n "label\|queries\|permission" "$M"


mkdir -p ~/.android
cp ci/debug.keystore ~/.android/debug.keystore
rm -f test/widget_test.dart
