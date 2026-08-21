import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

class NotificationService {
  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<List<Map<String, dynamic>>> listUnread(String token) async {
    final response = await http
        .get(_uri('/notifications'), headers: {'Authorization': 'Bearer $token'})
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, '알림을 불러오지 못했습니다.');
    }
    return ((jsonDecode(response.body) as Map<String, dynamic>)['notifications'] as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> markRead(String token, String eventId) async {
    final response = await http
        .patch(
          _uri('/notifications/${Uri.encodeComponent(eventId)}/read'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, '알림을 읽음 처리하지 못했습니다.');
    }
  }
}
