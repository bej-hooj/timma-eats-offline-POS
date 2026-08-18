import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:timma_kiosk/kiosk/catalog/dish_photo_cache.dart';

/// The dish photo cache: what it fetches, what it refuses, and what survives.
///
/// The refusals matter more than the fetches. This code runs on a tablet in a
/// public room, on a wifi the restaurant does not control, and it turns strings
/// from a database row into HTTP requests and then into files on disk. Every
/// test below is one way that could go wrong.
void main() {
  late Directory dir;
  late DishPhotoCache cache;

  const String host = 'abcdefgh.supabase.co';
  String url(String path) => 'https://$host/storage/v1/object/public/$path';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dish_photos');
    cache = DishPhotoCache(directory: dir, allowedHost: host);
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  group('what it refuses to touch at all', () {
    test('plaintext http is refused, even from the right host', () {
      // The kiosk shares a wifi with every customer in the room. A plaintext
      // image URL is one any of them can replace.
      expect(cache.isAllowed('http://$host/catalog/poulet.jpg'), isFalse);
    });

    test('another host is refused, even over https', () {
      expect(cache.isAllowed('https://evil.example/poulet.jpg'), isFalse);
      expect(
        cache.isAllowed('https://$host.evil.example/poulet.jpg'),
        isFalse,
        reason: 'a suffix match would accept exactly this',
      );
    });

    test('credentials in the URL are refused', () {
      expect(cache.isAllowed('https://user:pass@$host/x.jpg'), isFalse);
    });

    test('non-http schemes are refused', () {
      for (final String bad in <String>[
        'file:///etc/passwd',
        'data:image/png;base64,AAAA',
        'ftp://$host/x.jpg',
        '',
        'not a url at all',
      ]) {
        expect(cache.isAllowed(bad), isFalse, reason: bad);
      }
    });

    test('a refused URL cannot even name a file', () {
      // So no caller can construct a path for something the cache rejects.
      expect(cache.fileFor('http://$host/x.jpg'), isNull);
      expect(cache.fileFor('https://evil.example/x.jpg'), isNull);
    });
  });

  group('where the bytes land', () {
    test('the filename is content-addressed, never the remote path', () {
      final File file = cache.fileFor(url('catalog/../../../etc/passwd'))!;

      // A crafted URL must not steer the path. The name is a SHA-256 hex digest
      // plus `.img`, so traversal has nothing to work with.
      expect(file.parent.path, dir.path);
      expect(
        RegExp(r'^[0-9a-f]{64}\.img$').hasMatch(file.uri.pathSegments.last),
        isTrue,
      );
      expect(file.path.contains('..'), isFalse);
      expect(file.path.contains('passwd'), isFalse);
    });

    test(
      'the same URL always maps to the same file, different URLs do not',
      () {
        expect(
          cache.fileFor(url('a.jpg'))!.path,
          cache.fileFor(url('a.jpg'))!.path,
        );
        expect(
          cache.fileFor(url('a.jpg'))!.path,
          isNot(cache.fileFor(url('b.jpg'))!.path),
        );
      },
    );
  });

  group('reading, which happens inside build()', () {
    test('a miss is null, never a throw', () {
      expect(cache.readSync(url('missing.jpg')), isNull);
      expect(cache.readSync('http://nope'), isNull);
    });

    test('a hit returns the bytes that were written', () {
      final File file = cache.fileFor(url('poulet.jpg'))!;
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(<int>[1, 2, 3, 4]);

      expect(cache.readSync(url('poulet.jpg')), <int>[1, 2, 3, 4]);
    });

    test('an empty file reads as a miss, not as a blank photo', () {
      final File file = cache.fileFor(url('torn.jpg'))!;
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(<int>[]);

      expect(cache.readSync(url('torn.jpg')), isNull);
    });
  });

  group('warming the cache', () {
    test('it downloads once and reuses thereafter', () async {
      final _FakeHttp http = _FakeHttp(
        body: Uint8List.fromList(<int>[9, 9, 9]),
      );
      final DishPhotoCache warming = DishPhotoCache(
        directory: dir,
        allowedHost: host,
        clientFactory: http.client,
      );

      final DishPhotoCacheResult first = await warming.warm(<String>[
        url('a.jpg'),
        url('b.jpg'),
      ]);
      expect(first.fetched, 2);
      expect(first.reused, 0);
      expect(first.isComplete, isTrue);

      final DishPhotoCacheResult second = await warming.warm(<String>[
        url('a.jpg'),
        url('b.jpg'),
      ]);
      expect(
        second.fetched,
        0,
        reason: 'a pinned menu re-pinned must not refetch',
      );
      expect(second.reused, 2);

      expect(warming.readSync(url('a.jpg')), <int>[9, 9, 9]);
    });

    test('refused URLs are counted, not fetched', () async {
      final _FakeHttp http = _FakeHttp(body: Uint8List.fromList(<int>[1]));
      final DishPhotoCache warming = DishPhotoCache(
        directory: dir,
        allowedHost: host,
        clientFactory: http.client,
      );

      final DishPhotoCacheResult result = await warming.warm(<String>[
        'http://$host/a.jpg',
        'https://evil.example/b.jpg',
        url('good.jpg'),
      ]);

      expect(result.refused, 2);
      expect(result.fetched, 1);
      expect(http.requested, <String>[url('good.jpg')]);
      expect(result.isComplete, isFalse);
    });

    test('one dish failing does not cost the others', () async {
      final _FakeHttp http = _FakeHttp(
        body: Uint8List.fromList(<int>[7]),
        failFor: <String>{url('broken.jpg')},
      );
      final DishPhotoCache warming = DishPhotoCache(
        directory: dir,
        allowedHost: host,
        clientFactory: http.client,
      );

      final DishPhotoCacheResult result = await warming.warm(<String>[
        url('ok.jpg'),
        url('broken.jpg'),
      ]);

      expect(result.fetched, 1);
      expect(result.failed, 1);
      expect(warming.readSync(url('ok.jpg')), isNotNull);
      expect(warming.readSync(url('broken.jpg')), isNull);
    });

    test(
      'an oversize response is cut off mid-stream and leaves nothing',
      () async {
        final _FakeHttp http = _FakeHttp(
          body: Uint8List.fromList(List<int>.filled(5000, 1)),
        );
        final DishPhotoCache warming = DishPhotoCache(
          directory: dir,
          allowedHost: host,
          clientFactory: http.client,
          maxFileBytes: 1000,
        );

        final DishPhotoCacheResult result = await warming.warm(<String>[
          url('huge.jpg'),
        ]);

        expect(result.failed, 1);
        expect(
          warming.readSync(url('huge.jpg')),
          isNull,
          reason: 'a partial file must never become a torn photograph',
        );
      },
    );

    test(
      'a half-written file is never left behind under the real name',
      () async {
        final _FakeHttp http = _FakeHttp(
          body: Uint8List.fromList(List<int>.filled(5000, 1)),
        );
        final DishPhotoCache warming = DishPhotoCache(
          directory: dir,
          allowedHost: host,
          clientFactory: http.client,
          maxFileBytes: 1000,
        );
        await warming.warm(<String>[url('huge.jpg')]);

        final File target = warming.fileFor(url('huge.jpg'))!;
        expect(target.existsSync(), isFalse);
      },
    );
  });

  test('the cache stays inside its byte budget', () async {
    final _FakeHttp http = _FakeHttp(
      body: Uint8List.fromList(List<int>.filled(400, 1)),
    );
    final DishPhotoCache warming = DishPhotoCache(
      directory: dir,
      allowedHost: host,
      clientFactory: http.client,
      maxTotalBytes: 1000,
    );

    // Five files against a 1000-byte budget with a 400-byte per-file cap:
    // something has to give, and it must be the LATER photos rather than the
    // tablet's storage.
    final DishPhotoCacheResult result = await warming.warm(<String>[
      url('1.jpg'),
      url('2.jpg'),
      url('3.jpg'),
      url('4.jpg'),
      url('5.jpg'),
    ]);

    int total = 0;
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is File) {
        total += entity.lengthSync();
      }
    }
    expect(
      total,
      lessThanOrEqualTo(1000),
      reason: 'a big catalogue must not be able to fill the till tablet',
    );
    expect(result.fetched, greaterThan(0), reason: 'some photos still arrive');
    expect(
      result.skipped,
      greaterThan(0),
      reason: 'and the rest are reported as skipped, not silently missing',
    );
    expect(result.isComplete, isFalse);
  });

  test('a stale photo is evicted when the menu stops referencing it', () async {
    final _FakeHttp http = _FakeHttp(body: Uint8List.fromList(<int>[5, 5, 5]));
    final DishPhotoCache warming = DishPhotoCache(
      directory: dir,
      allowedHost: host,
      clientFactory: http.client,
      maxTotalBytes: 6,
    );

    await warming.warm(<String>[url('old.jpg')]);
    expect(warming.readSync(url('old.jpg')), isNotNull);

    // The dashboard replaces the dish. Yesterday's photo is the cheapest byte
    // on the tablet, so it goes before the new one is turned away.
    await warming.warm(<String>[url('new.jpg')]);

    expect(warming.readSync(url('old.jpg')), isNull, reason: 'evicted');
    expect(warming.readSync(url('new.jpg')), isNotNull, reason: 'and replaced');
  });
}

/// A fake `HttpClient` that serves bytes without a socket.
class _FakeHttp {
  _FakeHttp({required this.body, this.failFor = const <String>{}});

  final Uint8List body;
  final Set<String> failFor;
  final List<String> requested = <String>[];

  HttpClient client() => _FakeHttpClient(this);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._owner);

  final _FakeHttp _owner;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _owner.requested.add(url.toString());
    if (_owner.failFor.contains(url.toString())) {
      throw const SocketException('refused');
    }
    return _FakeRequest(_owner.body);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._body);

  final Uint8List _body;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._body);

  final Uint8List _body;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => -1;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // Delivered in small chunks so the streaming size cap is exercised the way
    // a real socket would exercise it, rather than in one convenient buffer.
    return Stream<List<int>>.fromIterable(<List<int>>[
      for (int i = 0; i < _body.length; i += 256)
        _body.sublist(i, i + 256 > _body.length ? _body.length : i + 256),
    ]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
