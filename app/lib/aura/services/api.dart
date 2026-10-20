import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// A sentence from the server the customer can read, e.g. "That time is no longer free."
class ApiException implements Exception {
  ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  bool get needsSignIn => status == 401;
  @override
  String toString() => message;
}

/// Talks to the Aura API (backend/). Adds the signed-in customer's token.
class Api {
  Api._();
  static final Api i = Api._();
  final _http = http.Client();

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = AuraConfig.apiUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers {
    final token = AuraConfig.live ? Supabase.instance.client.auth.currentSession?.accessToken : null;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// The free server sleeps when idle; the first call can take ~30 s to wake it.
  static const _timeout = Duration(seconds: 60);

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response r;
    try {
      r = await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('The server is taking too long. Check your internet and try again.');
    } catch (_) {
      throw ApiException('No internet connection. Please try again.');
    }
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 400) {
      final msg = body is Map && body['error'] != null ? body['error'].toString() : 'Something went wrong (${r.statusCode}). Please try again.';
      throw ApiException(msg, r.statusCode);
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) => _send(() => _http.get(_uri(path, query), headers: _headers));
  Future<dynamic> post(String path, [Object? body]) => _send(() => _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> put(String path, Object body) => _send(() => _http.put(_uri(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> delete(String path) => _send(() => _http.delete(_uri(path), headers: _headers));

  Future<dynamic> upload(String path, {required List<int> bytes, required String filename, String field = 'file', Map<String, String> fields = const {}}) {
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path));
      final h = Map.of(_headers)..remove('Content-Type');
      req.headers.addAll(h);
      req.fields.addAll(fields);
      final lower = filename.toLowerCase();
      final type = lower.endsWith('.png')
          ? 'png'
          : lower.endsWith('.webp')
              ? 'webp'
              : lower.endsWith('.pdf')
                  ? 'pdf'
                  : 'jpeg';
      req.files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename, contentType: MediaType(type == 'pdf' ? 'application' : 'image', type)));
      return http.Response.fromStream(await req.send());
    });
  }

}
