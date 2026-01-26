import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

/// Base API service for HTTP operations
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  
  final String _baseUrl = AppConstants.baseUrl;
  
  /// Build URL with action and optional parameters
  String _buildUrl(String action, [Map<String, dynamic>? params]) {
    final queryParams = {'action': action, ...?params};
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
        .join('&');
    return '$_baseUrl?$queryString';
  }
  
  /// GET request
  Future<ApiResponse> get(String action, [Map<String, dynamic>? params]) async {
    try {
      final url = _buildUrl(action, params);
      final response = await http.get(
        Uri.parse(url),
      ).timeout(
        Duration(seconds: AppConstants.connectionTimeout),
      );
      
      return _handleResponse(response);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }
  
  /// POST request with JSON body
  Future<ApiResponse> post(String action, Map<String, dynamic> body, [Map<String, dynamic>? params]) async {
    try {
      final url = _buildUrl(action, params);
      final response = await http.post(
        Uri.parse(url),
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        Duration(seconds: AppConstants.connectionTimeout),
      );
      
      return _handleResponse(response);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }
  
  /// Upload file with multipart request
  Future<ApiResponse> uploadFile({
    required String action,
    required File file,
    required Map<String, String> fields,
    String fileField = 'image',
  }) async {
    try {
      final url = _buildUrl(action, fields);
      final request = http.MultipartRequest('POST', Uri.parse(url));
      
      // Add file
      request.files.add(await http.MultipartFile.fromPath(
        fileField,
        file.path,
      ));
      
      // Add fields
      request.fields.addAll(fields);
      
      final streamedResponse = await request.send().timeout(
        Duration(seconds: AppConstants.uploadTimeout),
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }
  
  /// Get image URL
  String getImageUrl(int imageId, {bool thumbnail = false}) {
    final action = thumbnail ? AppConstants.actionGetThumb : AppConstants.actionGetImage;
    return _buildUrl(action, {'id': imageId.toString()});
  }
  
  /// Fetch all references for a company
  /// Returns API response with list of references in 'data' field
  Future<ApiResponse> getAllReferencesByCompany(int companyId) {
    return post(AppConstants.actionGetAllReferences, {'companyId': companyId});
  }
  
  /// Handle HTTP response
  ApiResponse _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = response.body;
      
      // Try to parse as JSON
      try {
        final json = jsonDecode(body);
        return ApiResponse.success(json);
      } catch (_) {
        // Return raw string if not JSON
        return ApiResponse.success(body);
      }
    } else {
      return ApiResponse.error(
        'HTTP Error: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }
}

/// API Response wrapper
class ApiResponse {
  final bool isSuccess;
  final dynamic data;
  final String? error;
  final int? statusCode;
  
  ApiResponse._({
    required this.isSuccess,
    this.data,
    this.error,
    this.statusCode,
  });
  
  factory ApiResponse.success(dynamic data) {
    return ApiResponse._(isSuccess: true, data: data);
  }
  
  factory ApiResponse.error(String error, {int? statusCode}) {
    return ApiResponse._(
      isSuccess: false,
      error: error,
      statusCode: statusCode,
    );
  }
  
  @override
  String toString() {
    return 'ApiResponse(isSuccess: $isSuccess, data: $data, error: $error)';
  }
}
