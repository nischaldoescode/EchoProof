# keep flutter classes
-keep class io.flutter.** { *; }

# keep firebase
-keep class com.google.firebase.** { *; }

# keep gson / json (common)
-keep class com.google.gson.** { *; }

# don't warn
-dontwarn io.flutter.embedding.**

# reduce readable breadcrumbs in optimized android bytecode
# dart code still needs flutter build --obfuscate --split-debug-info for release
-adaptclassstrings
-renamesourcefileattribute EchoProof
