// dio http client for calls to non-supabase endpoints
// used for: hugging face api, openai api (if calling from flutter — avoid this)
// supabase calls go through the supabase_flutter sdk, not dio

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/logging_interceptor.dart';

Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.addAll([
    LoggingInterceptor(),
    AuthInterceptor(),
  ]);

  return dio;
}

final dioProvider = Provider<Dio>((ref) => createDioClient());