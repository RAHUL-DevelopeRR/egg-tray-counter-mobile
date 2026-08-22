import 'dart:io';

import 'package:dio/dio.dart';

import '../models/capture_view.dart';
import '../models/scan_result.dart';
import '../models/scan_session.dart';

class ApiClient {
  ApiClient(String baseUrl)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

  final Dio _dio;
  CancelToken? _cancelToken;

  Future<bool> health() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/health');
      return response.statusCode == 200 && response.data?['status'] == 'ok';
    } on DioException {
      return false;
    }
  }

  Future<ScanResult> countScan(
    ScanSession session, {
    required void Function(int sent, int total) onProgress,
  }) async {
    if (!session.isComplete) {
      throw StateError('LEFT, RIGHT, and STRAIGHT are required');
    }
    _cancelToken = CancelToken();
    DioException? lastError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        final form = FormData.fromMap({
          'scan_id': session.scanId,
          'left': await MultipartFile.fromFile(
            session.pathFor(CaptureView.left)!,
            filename: 'left.jpg',
            contentType: DioMediaType.parse('image/jpeg'),
          ),
          'right': await MultipartFile.fromFile(
            session.pathFor(CaptureView.right)!,
            filename: 'right.jpg',
            contentType: DioMediaType.parse('image/jpeg'),
          ),
          'straight': await MultipartFile.fromFile(
            session.pathFor(CaptureView.straight)!,
            filename: 'straight.jpg',
            contentType: DioMediaType.parse('image/jpeg'),
          ),
        });
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/scans/count',
          data: form,
          cancelToken: _cancelToken,
          onSendProgress: onProgress,
        );
        final data = response.data;
        if (data == null) throw const FormatException('Empty API response');
        return ScanResult.fromJson(data);
      } on DioException catch (error) {
        lastError = error;
        if (CancelToken.isCancel(error) || !_retryable(error) || attempt == 1) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    throw lastError ?? const HttpException('Scan request failed');
  }

  bool _retryable(DioException error) => {
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
  }.contains(error.type);

  void cancel() {
    _cancelToken?.cancel('Operator cancelled scan');
  }
}
