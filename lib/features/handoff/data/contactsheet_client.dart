import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/handoff/domain/cs_models.dart';
import 'package:http/http.dart' as http;

/// A ContactSheet API error (network failure or a non-success HTTP status),
/// with a message safe to surface to the user.
class ContactSheetException implements Exception {
  /// Creates an exception.
  const ContactSheetException(this.message, {this.statusCode});

  /// Human-readable reason.
  final String message;

  /// The HTTP status, when the failure was a response (else null).
  final int? statusCode;

  @override
  String toString() => 'ContactSheetException: $message';
}

/// Minimal client for Niels' self-hosted ContactSheet (`BUILD_PLAN.md` §7b).
/// Push side only for now: list/create galleries and upload images with a
/// `cs_pat_…` personal access token. The injectable [http.Client] lets tests
/// drive it with a `MockClient`.
class ContactSheetClient {
  /// Creates a client for [baseUrl] (e.g. `https://contactsheet.example.com`)
  /// authenticating with the bearer [token].
  ContactSheetClient({
    required String baseUrl,
    required this.token,
    http.Client? client,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  /// Base URL with any trailing slash stripped.
  final String baseUrl;

  /// The `cs_pat_…` personal access token.
  final String token;

  final http.Client _client;

  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $token'};

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Lists galleries the token can see (`galleries:read`) — for the destination
  /// picker.
  Future<List<CsGallery>> listGalleries() async {
    final res = await _send(
      () => _client.get(_uri('/api/galleries'), headers: _authHeaders),
    );
    _ensureStatus(res, 200);
    final list = jsonDecode(res.body) as List<dynamic>;
    return [
      for (final e in list) CsGallery.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Creates a top-level gallery named [name] (`galleries:write`).
  Future<CsGallery> createGallery({
    required String name,
    String? parentId,
  }) async {
    final res = await _send(
      () => _client.post(
        _uri('/api/galleries'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'parent_id': ?parentId}),
      ),
    );
    _ensureStatus(res, 201);
    return CsGallery.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Uploads [files] into gallery [galleryId] (`images:write`). The server
  /// sniffs each file's real format from its bytes, so no content-type is set.
  Future<List<CsUpload>> uploadImages({
    required String galleryId,
    required List<File> files,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/galleries/$galleryId/images'),
    )..headers.addAll(_authHeaders);
    for (final file in files) {
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }
    final res = await _send(
      () async => http.Response.fromStream(await _client.send(request)),
    );
    _ensureStatus(res, 201);
    final list = jsonDecode(res.body) as List<dynamic>;
    return [
      for (final e in list) CsUpload.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Pulls the client review state for a gallery via its public [shareToken]
  /// (`GET /api/public/g/{shareToken}/images`) — ratings, colour flags and
  /// likes per image (§7b pull). The endpoint is share-token-gated, so no
  /// bearer token is sent; password-protected galleries aren't supported yet.
  Future<List<CsImageMark>> pullGalleryMarks(String shareToken) async {
    final res = await _send(
      () => _client.get(_uri('/api/public/g/$shareToken/images')),
    );
    _ensureStatus(res, 200);
    final list = jsonDecode(res.body) as List<dynamic>;
    return [
      for (final e in list) CsImageMark.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Pulls the gallery's client-made collections via its public [shareToken]
  /// (`GET /api/public/g/{shareToken}/collections`). 403s when the gallery has
  /// collections disabled (the caller treats that as "no collections").
  Future<List<CsCollection>> pullCollections(String shareToken) async {
    final res = await _send(
      () => _client.get(_uri('/api/public/g/$shareToken/collections')),
    );
    _ensureStatus(res, 200);
    final list = jsonDecode(res.body) as List<dynamic>;
    return [
      for (final e in list) CsCollection.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Closes the underlying client.
  void close() => _client.close();

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on ContactSheetException {
      rethrow;
    } on Object catch (e) {
      throw ContactSheetException('Could not reach ContactSheet ($e)');
    }
  }

  void _ensureStatus(http.Response res, int expected) {
    if (res.statusCode == expected) return;
    final reason = switch (res.statusCode) {
      401 || 403 => 'Not authorised — check the token and its scopes',
      404 => 'Not found — check the URL or gallery',
      _ => 'Server returned ${res.statusCode}',
    };
    throw ContactSheetException(reason, statusCode: res.statusCode);
  }
}
