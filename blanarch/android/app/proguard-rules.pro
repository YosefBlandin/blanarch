# Pigeon messages are built by the generated codec, not by reflection, but keep the
# bridge package intact so stack traces from the platform channel stay readable.
-keep class com.blanarch.app.bridge.** { *; }
# The service and application class are referenced from the manifest (kept by AAPT);
# the config JSON is parsed with org.json from the platform, nothing to keep there.
