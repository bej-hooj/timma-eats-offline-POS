import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Dish photographs that survive the outage they were downloaded for.
///
/// **Why this exists.** The kiosk's whole promise is that it keeps selling when
/// the internet drops. Photos were `Image.network`, so every dish picture was a
/// fresh HTTP GET: the moment the line went down the menu became a grid of grey
/// panels. A menu whose pictures vanish with the internet is not an offline
/// menu.
///
/// So the catalogue's photos are fetched **once, when the snapshot is pinned**,
/// and read from app-private storage forever after. Disk first, network second,
/// brand panel last.
///
/// ## What this cache is allowed to do
///
/// It is a **cache, never truth**. Prices, availability and names come from the
/// pinned snapshot the engine validated (§23.8). An image is decoration: a
/// missing, refused or corrupt one degrades to the brand panel and nothing else
/// in the kiosk notices.
///
/// ## The rules it enforces, and why each one is here
///
/// 1. **https only.** The tablet stands in a public room on a shop's wifi. A
///    plaintext image URL is one anybody on that wifi can replace.
/// 2. **Only the configured host.** The snapshot is authenticated, but a row
///    that somehow carried a foreign URL must not make a kiosk fetch from an
///    arbitrary server. Defence in depth costs one comparison.
/// 3. **Bounded, while streaming.** A per-file cap and a total budget, enforced
///    as bytes arrive rather than after, so a hostile or broken response cannot
///    fill a tablet's storage.
/// 4. **Content-addressed names.** The filename is the SHA-256 of the URL, hex.
///    No path element ever comes from the remote string, so no crafted URL can
///    traverse out of the cache directory.
/// 5. **Atomic writes.** Bytes land in a temp file and are renamed into place,
///    so a kill mid-download can never leave a half-image that renders as a
///    torn photograph.
/// 6. **No secrets.** Device keys and API keys never reach a filename, a log
///    line or an exception message here.
class DishPhotoCache {
  DishPhotoCache({
    required this.directory,
    required String allowedHost,
    HttpClient Function()? clientFactory,
    this.maxFileBytes = 2 * 1024 * 1024,
    this.maxTotalBytes = 128 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _allowedHost = allowedHost.toLowerCase(),
       _clientFactory = clientFactory ?? HttpClient.new;

  /// Where the images live: app-private storage, never external storage.
  final Directory directory;
  final String _allowedHost;
  final HttpClient Function() _clientFactory;

  /// A dish photograph that does not fit in this is not a dish photograph.
  final int maxFileBytes;

  /// The whole catalogue's budget on a tablet that also holds the shift's till.
  final int maxTotalBytes;

  final Duration requestTimeout;

  /// The file this URL would occupy, whether or not it exists yet.
  ///
  /// Returns null when the URL is one this cache refuses to touch at all, so a
  /// caller cannot accidentally construct a path for a rejected URL.
  File? fileFor(String url) {
    if (!isAllowed(url)) {
      return null;
    }
    final String name = sha256.convert(utf8.encode(url)).toString();
    return File('${directory.path}/$name.img');
  }

  /// True when this URL is one the kiosk is willing to fetch.
  bool isAllowed(String url) {
    if (url.isEmpty || url.length > 2048) {
      return false;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) {
      return false;
    }
    // `https` only, and only the host this build was configured with. Both
    // checks, not either: a `https://evil.example/x.jpg` is as unwelcome as a
    // `http://<our host>/x.jpg`.
    return uri.scheme == 'https' &&
        uri.host.toLowerCase() == _allowedHost &&
        uri.userInfo.isEmpty;
  }

  /// The bytes for [url] if they are already on disk, else null. Never fetches.
  ///
  /// Synchronous on purpose: it runs inside `build()` for every dish card on
  /// the menu, and an async gap there is a frame where the photo is missing and
  /// the card flickers through its fallback.
  Uint8List? readSync(String url) {
    final File? file = fileFor(url);
    if (file == null) {
      return null;
    }
    try {
      if (!file.existsSync()) {
        return null;
      }
      final Uint8List bytes = file.readAsBytesSync();
      return bytes.isEmpty ? null : bytes;
    } on Object {
      // A cache read is never allowed to take the menu down with it.
      return null;
    }
  }

  /// Downloads every photo in [urls] that is not already on disk.
  ///
  /// Best effort by design: one dish's photo failing must not cost the others,
  /// so failures are counted and reported, never thrown. Returns how many files
  /// the cache holds for these URLs afterwards.
  Future<DishPhotoCacheResult> warm(Iterable<String> urls) async {
    await _ensureDirectory();
    final Set<String> wanted = urls.where(isAllowed).toSet();
    int fetched = 0;
    int reused = 0;
    int failed = 0;
    int skipped = 0;
    final int refused = urls.where((String url) => !isAllowed(url)).length;

    // Yesterday's catalogue first. Photos nothing on the menu references are
    // the cheapest bytes on the tablet, so they go before the budget is ever
    // allowed to turn a download away.
    await _evictStale(keep: wanted);
    int total = await _totalBytes();

    for (final String url in wanted) {
      final File file = fileFor(url)!;
      if (file.existsSync() && file.lengthSync() > 0) {
        reused++;
        continue;
      }
      // ⚠ The budget is enforced BEFORE the request, not by deleting after it.
      // Evicting a photo the live menu wants would mean downloading it again on
      // the next pin, forever. A catalogue larger than the budget therefore
      // renders its remainder as brand panels — the honest outcome, and a
      // visible one in the returned counts.
      //
      // The download is capped at whatever budget is actually left, not at the
      // per-file maximum: reserving the worst case up front would turn every
      // photo away as soon as the remaining room fell below one large file.
      final int remaining = maxTotalBytes - total;
      if (remaining <= 0) {
        skipped++;
        continue;
      }
      final int limit = remaining < maxFileBytes ? remaining : maxFileBytes;
      try {
        await _download(url, file, limit: limit);
        total += await file.length();
        fetched++;
      } on _PhotoRejected catch (rejection) {
        // A photo stopped by the BUDGET is not a broken photo. Conflating the
        // two would have the diagnostics blame the network for a full disk.
        if (rejection.reason == _PhotoRejected.tooLarge &&
            limit < maxFileBytes) {
          skipped++;
        } else {
          failed++;
        }
      } on Object {
        // The URL is never put in the message: it is not secret, but the habit
        // of interpolating remote strings into logs is how one eventually is.
        failed++;
      }
    }

    return DishPhotoCacheResult(
      fetched: fetched,
      reused: reused,
      refused: refused,
      failed: failed,
      skipped: skipped,
    );
  }

  Future<int> _totalBytes() async {
    int total = 0;
    for (final FileSystemEntity entity in await directory.list().toList()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> _download(
    String url,
    File destination, {
    required int limit,
  }) async {
    final HttpClient client = _clientFactory();
    try {
      client.connectionTimeout = requestTimeout;
      final HttpClientRequest request = await client
          .getUrl(Uri.parse(url))
          .timeout(requestTimeout);
      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const _PhotoRejected('status');
      }
      // Declared length is a hint, not a promise — the real cap is enforced
      // below as the bytes actually arrive.
      if (response.contentLength > limit) {
        throw const _PhotoRejected(_PhotoRejected.tooLarge);
      }

      // Written to a temp file and renamed: a kill mid-download must not leave
      // a half-written image that renders as a torn photograph.
      final File temp = File('${destination.path}.part');
      final IOSink sink = temp.openWrite();
      int written = 0;
      try {
        await for (final List<int> chunk in response.timeout(requestTimeout)) {
          written += chunk.length;
          if (written > limit) {
            throw const _PhotoRejected(_PhotoRejected.tooLarge);
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (written == 0) {
        await temp.delete();
        throw const _PhotoRejected('empty');
      }
      await temp.rename(destination.path);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _ensureDirectory() async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  /// Deletes photos the current menu no longer references, oldest first.
  ///
  /// Only stale files: a photo the live menu wants is never evicted, because
  /// evicting it just means fetching it again on the next pin — and on a kiosk
  /// that may be the last fetch before the internet goes.
  Future<void> _evictStale({required Set<String> keep}) async {
    try {
      final Set<String> keepPaths = keep
          .map((String url) => fileFor(url)?.path)
          .whereType<String>()
          .toSet();
      final List<File> stale = (await directory.list().toList())
          .whereType<File>()
          .where((File file) => !keepPaths.contains(file.path))
          .toList();

      // A `.part` file is a download that died mid-flight; it is always stale.
      stale.sort(
        (File a, File b) =>
            a.statSync().modified.compareTo(b.statSync().modified),
      );
      // Every stale file goes, not only enough of them to get under budget: a
      // photo no dish references is dead weight, and keeping it just means the
      // next new dish is the one turned away.
      for (final File file in stale) {
        await file.delete();
      }
    } on Object {
      // Eviction is housekeeping. Failing it must never fail a service.
      debugPrint('[DishPhotoCache] eviction skipped');
    }
  }
}

/// What one warming pass did. Reported, never thrown.
@immutable
class DishPhotoCacheResult {
  const DishPhotoCacheResult({
    required this.fetched,
    required this.reused,
    required this.refused,
    required this.failed,
    this.skipped = 0,
  });

  final int fetched;
  final int reused;

  /// URLs this cache would not touch — not https, or not the configured host.
  final int refused;
  final int failed;

  /// Photos left un-fetched because the cache is at its byte budget. They
  /// render as the brand panel; nothing else about the menu changes.
  final int skipped;

  bool get isComplete => failed == 0 && refused == 0 && skipped == 0;

  @override
  String toString() =>
      'DishPhotoCacheResult(fetched: $fetched, reused: $reused, '
      'refused: $refused, failed: $failed, skipped: $skipped)';
}

class _PhotoRejected implements Exception {
  const _PhotoRejected(this.reason);

  static const String tooLarge = 'too large';

  final String reason;

  @override
  String toString() => 'PhotoRejected($reason)';
}
