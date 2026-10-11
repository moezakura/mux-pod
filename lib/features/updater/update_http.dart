import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'update_failure.dart';

/// Minimal HTTP surface the updater needs. Swapped for a fake in tests.
abstract class UpdateHttp {
  /// GET [url] and decode the body as JSON.
  Future<Object?> getJson(Uri url);

  /// GET [url] as text.
  Future<String> getText(Uri url);

  /// Stream [url] into [dest]. [onProgress] gets received/total bytes
  /// (total is null if unknown). Completing [cancel] aborts the transfer.
  Future<void> download(
    Uri url,
    File dest, {
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  });
}

class IoUpdateHttp implements UpdateHttp {
  IoUpdateHttp({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  static const _userAgent = 'MuxPod-Updater';

  @override
  Future<Object?> getJson(Uri url) async =>
      jsonDecode(await getText(url, accept: 'application/vnd.github+json'));

  @override
  Future<String> getText(Uri url, {String accept = '*/*'}) async {
    final client = _newClient();
    try {
      final response = await _open(client, url, accept);
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    Uri url,
    File dest, {
    void Function(int received, int? total)? onProgress,
    Future<void>? cancel,
  }) async {
    final client = _newClient();
    var cancelled = false;
    unawaited(
      cancel?.then((_) {
        cancelled = true;
        client.close(force: true);
      }),
    );
    final sink = dest.openWrite();
    try {
      final response = await _open(client, url, 'application/octet-stream');
      final total = response.contentLength >= 0 ? response.contentLength : null;
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      if (total != null && received != total) {
        throw const UpdateException(UpdateFailure.network, 'truncated');
      }
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException(
        UpdateFailure.network,
        cancelled ? 'cancelled' : e.toString(),
      );
    } finally {
      await sink.close();
      client.close(force: true);
    }
  }

  HttpClient _newClient() => _clientFactory()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15)
    ..userAgent = _userAgent;

  Future<HttpClientResponse> _open(
    HttpClient client,
    Uri url,
    String accept,
  ) async {
    if (url.scheme != 'https') {
      throw UpdateException(UpdateFailure.network, 'refusing $url');
    }
    final HttpClientResponse response;
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, accept);
      response = await request.close();
    } catch (e) {
      throw UpdateException(UpdateFailure.network, e.toString());
    }
    // Redirects (github.com → release CDN) must stay on https.
    if (response.redirects.any(
      (r) => r.location.hasScheme && r.location.scheme != 'https',
    )) {
      throw const UpdateException(UpdateFailure.network, 'insecure redirect');
    }
    final status = response.statusCode;
    if (status == 200) return response;
    await response.drain<void>();
    if ((status == 403 || status == 429) &&
        response.headers.value('x-ratelimit-remaining') == '0') {
      throw const UpdateException(UpdateFailure.rateLimited);
    }
    if (status == 404) {
      throw UpdateException(UpdateFailure.noRelease, url.toString());
    }
    throw UpdateException(UpdateFailure.network, 'HTTP $status');
  }
}
