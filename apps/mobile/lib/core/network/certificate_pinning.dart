// certificate pinning via public key (spki) hash
// public key hashing is rotation-resistant the key stays the same
// even when supabase renews their certificate
// how to get the spki hash for your supabase url:
// openssl s_client -connect your-project.supabase.co:443 </dev/null 2>/dev/null
// openssl x509 -pubkey -noout
// openssl pkey -pubin -outform der
// openssl dgst -sha256 -binary
// openssl enc -base64
// important: add multiple backup pins in case of key rotation
// leave this empty if you choose not to pin (safer for cdn-backed apis)
// pinning supabase is optional their cdn (cloudflare) makes it fragile

import 'dart:io';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// spki sha-256 hashes (base64-encoded) of trusted public keys
// empty set = no pinning (default safe behavior for cdn-backed apis)
const _pinnedSpkiHashes = <String>{
  // add your supabase project's spki hash here after running the openssl command above
  // example: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=',
};

// returns a standard http.client with optional certificate pinning
// if _pinnedspkihashes is empty, returns a standard client (no pinning)
http.Client createPinnedClient() {
  // never pin in debug avoids blocking local dev traffic
  if (kDebugMode || _pinnedSpkiHashes.isEmpty) {
    return http.Client();
  }

  final ioClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) {
      // reject do not allow bad certificates
      return false;
    };

  // note: dart's httpclient does not expose the public key bytes directly
  // for spki pinning without a native plugin. the options are:
  // 1. use a native plugin (e.g. ssl_pinning_plugin) for strict spki pinning
  // 2. pin the der bytes (rotation-fragile, avoid for production cdn apis)
  // 3. skip pinning for supabase (recommended cloudflare cdn + frequent rotation)
  // for echoproof, we rely on:
  // supabase's own tls enforcement (https enforced by default)
  // network security config (android: res/xml/network_security_config.xml)
  // rls policies as the primary security layer
  // strict spki pinning is left as a future enhancement when a native plugin is integrated

  return IOClient(ioClient);
}
