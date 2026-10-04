import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

String operationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((i) => i.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class GameApi {
  GameApi({http.Client? client, String? baseUrl, this._token})
    : client = client ?? http.Client(),
      baseUrl = (baseUrl ?? apiBaseUrl).replaceFirst(RegExp(r'/$'), '');
  final http.Client client;
  final String baseUrl;
  String? _token;
  bool _tokenSaved = false;
  String get sessionKey => 'lajkonik.session.v1:$baseUrl';

  Future<Map<String, dynamic>> load() async {
    if (_token == null) {
      final store = await SharedPreferences.getInstance();
      _token = store.getString(sessionKey);
      _tokenSaved = _token != null;
      if (_token == null) {
        final response = await _request('sessions', body: {}, retry: false);
        _token = response['token'] as String;
      }
      if (!_tokenSaved) {
        if (!await store.setString(sessionKey, _token!)) {
          throw StateError('Nie można zapamiętać konta. Spróbuj ponownie.');
        }
        _tokenSaved = true;
      }
    }
    // A supplied test token does not need browser storage. A newly created one does.
    if (!_tokenSaved && _token != null) {
      final store = await SharedPreferences.getInstance();
      if (!await store.setString(sessionKey, _token!)) {
        throw StateError('Nie można zapamiętać konta. Spróbuj ponownie.');
      }
      _tokenSaved = true;
    }
    return _request('state');
  }

  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (_token == null) throw StateError('Najpierw połącz się z kontem.');
    final response = await _request(
      path,
      body: {'request_id': operationId(), ...body},
    );
    return Map<String, dynamic>.from(response['state'] as Map);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
    bool retry = true,
  }) async {
    final uri = Uri.parse('$baseUrl/game/$path');
    final encoded = body == null ? null : jsonEncode(body);
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    for (var attempt = 0; ; attempt++) {
      try {
        final response =
            await (encoded == null
                    ? client.get(uri, headers: headers)
                    : client.post(uri, headers: headers, body: encoded))
                .timeout(const Duration(seconds: 15));
        Map<String, dynamic>? value;
        try {
          value = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {
          /* Non-JSON error from a proxy. */
        }
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            value == null) {
          throw StateError(
            value?['detail'] is String
                ? value!['detail'] as String
                : 'Nie udało się połączyć z kontem. Spróbuj ponownie.',
          );
        }
        return value;
      } on StateError {
        rethrow;
      } catch (_) {
        // Retry the exact body and request_id: a committed mutation cannot be applied twice.
        if (!retry || attempt >= 1) {
          throw StateError(
            'Brak połączenia z kontem. Punkty i wygląd nie zostały zmienione w aplikacji. Odśwież stan przed ponowną próbą.',
          );
        }
      }
    }
  }

  void dispose() => client.close();
}
