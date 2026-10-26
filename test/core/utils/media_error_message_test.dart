import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/media_error_message.dart';

void main() {
  test('DNS errors show recovery advice without transport internals', () {
    final error = DioException(
      requestOptions: RequestOptions(path: 'https://example.com/private-token'),
      error: const SocketException('Failed host lookup'),
      type: DioExceptionType.connectionError,
    );
    final message = mediaErrorMessage(error);
    expect(message, contains('Check your internet connection'));
    expect(message, isNot(contains('private-token')));
    expect(message, isNot(contains('DioException')));
  });
  test('rate limits provide distinct advice', () {
    final options = RequestOptions(path: 'https://example.com');
    expect(
      mediaErrorMessage(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 429),
        ),
      ),
      contains('Wait a moment'),
    );
  });
  test('meaningful extractor explanations are preserved', () {
    expect(
      mediaErrorMessage(StateError('This video is private')),
      'This video is private',
    );
  });
}
