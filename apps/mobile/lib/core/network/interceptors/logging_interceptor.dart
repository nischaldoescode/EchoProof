// logs request and response summaries in debug mode only

import 'package:dio/dio.dart';
import '../../../core/utils/logger.dart';

class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.debug('network request ${options.method} ${options.uri.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    AppLogger.debug(
      'network response ${response.statusCode} '
      '${response.requestOptions.uri.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.error(
      'network request failed ${err.response?.statusCode ?? 'offline'} '
      '${err.requestOptions.uri.path}',
    );
    handler.next(err);
  }
}
