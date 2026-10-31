// runtime configuration is supplied by dart defines at build time.
//
// the mobile client must receive a publishable supabase key only. this helper
// accepts the older anon-key define as a compatibility fallback so an older
// build command keeps working while the project moves to the current key name.
// neither name should ever contain a service-role or secret key.
abstract final class RuntimeConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
}
