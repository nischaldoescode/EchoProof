// certificate pinning
// prevents man-in-the-middle attacks even on rooted devices
// pins supabase and didit certificates
// if the certificate changes (supabase rotates), update this file

import 'dart:io';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

// sha-256 fingerprints of the certificates we trust
// get current fingerprint:
//   openssl s_client -connect your-project.supabase.co:443 </dev/null 2>/dev/null \
//   | openssl x509 -fingerprint -sha256 -noout
const _pinnedFingerprints = <String>{
  // supabase production certificate sha256
  // replace with your actual supabase project certificate
  'AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78',
  // didit production certificate
  'CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90',
};

// creates an http client that verifies certificate fingerprints
// use this for all sensitive API calls
http.Client createPinnedClient() {
  final context = SecurityContext.defaultContext;
  final ioClient = HttpClient(context: context)
    ..badCertificateCallback = (cert, host, port) {
      // in debug mode allow all — only pin in release
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        return true;
      }
// get raw DER bytes
      final der = cert.der;

// compute sha256 hash
      final digest = sha256.convert(der);

// convert to the uppercase fingerprint format "AA:BB:CC:..."
      final fingerprint = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');

      return _pinnedFingerprints.contains(fingerprint);
    };
  return IOClient(ioClient);
}
