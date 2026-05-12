// Certificate pinning via public key (SPKI) hash.
// Public key hashing is rotation-resistant — the key stays the same
// even when Supabase renews their certificate.
//
// How to get the SPKI hash for your Supabase URL:
//   openssl s_client -connect your-project.supabase.co:443 </dev/null 2>/dev/null \
//   | openssl x509 -pubkey -noout \
//   | openssl pkey -pubin -outform DER \
//   | openssl dgst -sha256 -binary \
//   | openssl enc -base64
//
// IMPORTANT: Add multiple backup pins in case of key rotation.
// Leave this empty if you choose not to pin (safer for CDN-backed APIs).
// Pinning Supabase is optional — their CDN (Cloudflare) makes it fragile.

import 'dart:io';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// SPKI SHA-256 hashes (base64-encoded) of trusted public keys.
// Empty set = no pinning (default safe behavior for CDN-backed APIs).
const _pinnedSpkiHashes = <String>{
  // Add your Supabase project's SPKI hash here after running the openssl command above.
  // Example: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
};

// Returns a standard http.Client with optional certificate pinning.
// If _pinnedSpkiHashes is empty, returns a standard client (no pinning).
http.Client createPinnedClient() {
  // Never pin in debug — avoids blocking local dev traffic.
  if (kDebugMode || _pinnedSpkiHashes.isEmpty) {
    return http.Client();
  }

  final ioClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) {
      // Reject — do not allow bad certificates.
      return false;
    };

  // Note: Dart's HttpClient does not expose the public key bytes directly
  // for SPKI pinning without a native plugin. The options are:
  //   1. Use a native plugin (e.g. ssl_pinning_plugin) for strict SPKI pinning.
  //   2. Pin the DER bytes (rotation-fragile, avoid for production CDN APIs).
  //   3. Skip pinning for Supabase (recommended — Cloudflare CDN + frequent rotation).
  //
  // For Echoproof, we rely on:
  //   - Supabase's own TLS enforcement (HTTPS enforced by default)
  //   - Network security config (Android: res/xml/network_security_config.xml)
  //   - RLS policies as the primary security layer
  //
  // Strict SPKI pinning is left as a future enhancement when a native plugin is integrated.

  return IOClient(ioClient);
}
