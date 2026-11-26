# R8 keep rules for release builds.
#
# Release builds shrink and obfuscate the DEX (see buildTypes.release in
# build.gradle.kts). Everything below exists because something would break
# without it — do not add blanket keeps for our own packages, because the DEX
# obfuscation ratio is what Google Play measures.
#
# When a release build fails with "Missing class ...", R8 writes the exact rules
# it wants to:
#   build/app/outputs/mapping/<variant>/missing_rules.txt
# Copy from there rather than guessing, and add a comment saying which
# dependency needed it.

# ---------------------------------------------------------------------------
# libbox / gomobile — the sing-box VPN core (android/app/libs/libbox.aar)
# ---------------------------------------------------------------------------
# The Go runtime resolves these classes and their methods by name over JNI, so
# renaming or removing any of them breaks the tunnel at runtime rather than at
# build time. The AAR ships the same two rules in its own proguard.txt; they are
# repeated here so the build does not depend on consumer rules being picked up
# from a local file dependency.
-keep class go.** { *; }
-keep class io.nekohasekai.libbox.** { *; }

# Our side of the bridge. These implement gomobile-generated interfaces that Go
# calls back into (PlatformInterface, the iterators, the command handlers).
# Overrides of kept interface methods keep their names, but the classes
# themselves are only ever instantiated from our code, so be explicit.
-keep class com.erebrus.vpn.ErebrusVpnService { *; }
-keep class com.erebrus.vpn.AndroidNetworkPlatform { *; }
-keep class com.erebrus.vpn.LibboxStatsMonitor { *; }
-keep class com.erebrus.vpn.SingboxBridge { *; }

# ---------------------------------------------------------------------------
# BouncyCastle — WireGuard x25519 keypair generation (MainActivity)
# ---------------------------------------------------------------------------
# Only the lightweight crypto API is used (no JCE provider registration), so R8
# can shrink the rest. The library references optional JDK APIs that do not
# exist on Android; silence those rather than keeping the classes.
-dontwarn org.bouncycastle.**
-dontwarn javax.naming.**

# ---------------------------------------------------------------------------
# Flutter
# ---------------------------------------------------------------------------
# The embedding references Play Core for deferred components, which this app
# does not use and does not depend on.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------
# Solana Mobile Wallet Adapter talks to wallet apps over intents and a bound
# service; its scenario classes are resolved reflectively by the adapter.
-dontwarn com.solanamobile.**

# Keep annotated JNI entry points anywhere in the app.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
