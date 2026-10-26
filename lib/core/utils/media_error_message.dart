import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Actionable extraction errors without HTTP-client internals or signed URLs.
String mediaErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (error is SocketException ||
      (error is DioException && error.error is SocketException) ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable')) {
    return 'Could not connect to the media site. Check your internet connection and try again.';
  }
  if (error is TimeoutException ||
      (error is DioException &&
          {
            DioExceptionType.connectionTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.sendTimeout,
          }.contains(error.type))) {
    return 'The media site took too long to respond. Please try again.';
  }
  if (error is DioException) {
    switch (error.response?.statusCode) {
      case 403:
        return 'The media site denied access to this stream. Please retry or choose another available format.';
      case 404:
        return 'This media could not be found. Check the link and whether it is still public.';
      case 429:
        return 'The media site is receiving too many requests. Wait a moment and try again.';
    }
    return 'Could not load this media. Check your connection and try again.';
  }
  // Retain meaningful extractor explanations (private, removed, unsupported).
  return message.replaceFirst(RegExp(r'^(Exception|Bad state):\s*'), '');
}
