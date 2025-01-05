import 'dart:convert';

import 'package:dio/dio.dart';

class AppInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print('${options.method} ${options.uri}');

    if (options.data != null) {
      print('Data: ${jsonEncode(options.data)}');
    }

    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('${err.requestOptions.uri}');
    super.onError(err, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('${response.statusCode} ${response.requestOptions.uri}');

    if (response.data != null) {
      print('Response: ${jsonEncode(response.data)}');
    }

    super.onResponse(response, handler);
  }
}
