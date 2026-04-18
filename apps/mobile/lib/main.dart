// echoproof app entry point
// initializes supabase, hive, and flutter before runApp

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // lock to portrait — echoproof is a portrait-first app
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // initialize hive for local caching + draft storage
  await Hive.initFlutter();
  await Hive.openBox('app_settings');
  await Hive.openBox('echo_cache');

  // initialize supabase
  // TODO: move url and anonKey to --dart-define or a .env loader
  // never hardcode production keys here
  // wire: use flutter_dotenv or --dart-define-from-file=.env at build time
  // parameters: SUPABASE_URL, SUPABASE_ANON_KEY as environment variables
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');

  runApp(
    const ProviderScope(
      child: EchoProofApp(),
    ),
  );
}