import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:refreezer/api/deezer.dart';
import 'package:refreezer/api/definitions.dart';
import 'package:refreezer/settings.dart';
import 'package:refreezer/service/app_diagnostics.dart';

Map<String, dynamic> session({dynamic id = '42', bool license = true}) => {
  'error': <String, dynamic>{},
  'results': {
    'SESSION_ID': 'test-session',
    'checkForm': 'test-form',
    'USER': {
      'USER_ID': id,
      'BLOG_NAME': 'Test',
      'LOVEDTRACKS_ID': 99,
      if (license) 'OPTIONS': {'license_token': 'test-license'},
    },
  },
};
http.Response reply(Map<String, dynamic> data) =>
    http.Response(jsonEncode(data), 200);
void main() {
  setUp(() => settings = Settings.fromJson({}));
  test('media snapshot uses the same SID and license as the catalog request', () async {
    String? cookie;
    final api = DeezerAPI(arl: 'fixture-account', client: MockClient((request) async {
      if (request.url.queryParameters['method'] == 'deezer.getUserData') return reply(session());
      cookie = request.headers['cookie'];
      return reply({'error': {}, 'results': {'data': []}});
    }));
    expect(api.playbackSession, isNull);
    expect(await api.authorize(), isTrue);
    final shared = api.playbackSession!;
    await api.callGwApi('song.getListData', params: {'sng_ids': ['42']});
    expect(cookie, contains('sid=${shared['sid']}'));
    expect(shared['token'], 'test-form'); expect(shared['licenseToken'], 'test-license');
    api.arl = 'different-account';
    expect(api.playbackSession, isNull);
  });
  test('catalog-only snapshot does not invent a media license', () async {
    final api = DeezerAPI(arl: 'fixture-account', client: MockClient((_) async => reply(session(license: false))));
    expect(await api.authorize(), isTrue);
    expect(api.playbackSession?['licenseToken'], '');
  });
  test(
    'valid string user IDs initialize SID and personal playlist IDs',
    () async {
      final api = DeezerAPI(
        arl: 'test-only',
        client: MockClient((_) async => reply(session())),
      );
      expect(await api.authorize(), isTrue);
      expect(api.userId, '42');
      expect(api.sid, 'test-session');
      expect(api.favoritesPlaylistId, '99');
      expect(api.licenseToken, 'test-license');
    },
  );
  test(
    'an account without stream options can still browse its library',
    () async {
      final api = DeezerAPI(
        arl: 'test-only',
        client: MockClient((_) async => reply(session(license: false))),
      );
      expect(await api.authorize(), isTrue);
      expect(api.licenseToken, isNull);
    },
  );
  for (final id in [0, '0', null]) {
    test('rejects anonymous or malformed user ID $id', () async {
      final api = DeezerAPI(
        arl: 'test-only',
        client: MockClient((_) async => reply(session(id: id))),
      );
      expect(await api.authorize(), isFalse);
      expect(api.token, isNull);
    });
  }
  test('concurrent authorization performs only one HTTP request', () async {
    var requests = 0;
    final gate = Completer<void>();
    final api = DeezerAPI(
      arl: 'test-only',
      client: MockClient((_) async {
        requests++;
        await gate.future;
        return reply(session());
      }),
    );
    final pending = List.generate(20, (_) => api.authorize());
    gate.complete();
    expect(await Future.wait(pending), everyElement(isTrue));
    expect(requests, 1);
  });
  test(
    'gateway waits for authorization before issuing a personal call',
    () async {
      final methods = <String?>[];
      final api = DeezerAPI(
        arl: 'test-only',
        client: MockClient((request) async {
          final method = request.url.queryParameters['method'];
          methods.add(method);
          if (method == 'deezer.getUserData') return reply(session());
          expect(request.headers['Cookie'], contains('sid=test-session'));
          expect(request.url.queryParameters['api_token'], 'test-form');
          return reply({
            'error': {},
            'results': {'value': 'ok'},
          });
        }),
      );
      expect(
        (await api.callGwApi('user.getAllFeedbacks'))['results']['value'],
        'ok',
      );
      expect(methods, ['deezer.getUserData', 'user.getAllFeedbacks']);
    },
  );
  test(
    'CSRF refresh is bounded even if the provider keeps refusing the token',
    () async {
      var authRequests = 0;
      var calls = 0;
      final api = DeezerAPI(
        arl: 'test-only',
        client: MockClient((request) async {
          if (request.url.queryParameters['method'] == 'deezer.getUserData') {
            authRequests++;
            return reply(session());
          }
          calls++;
          return reply({
            'error': {'VALID_TOKEN_REQUIRED': 'ignored'},
            'results': {},
          });
        }),
      );
      await expectLater(
        api.callGwApi('page.get'),
        throwsA(
          isA<DeezerApiException>().having(
            (e) => e.code,
            'code',
            'VALID_TOKEN_REQUIRED',
          ),
        ),
      );
      expect(authRequests, 2);
      expect(calls, 2);
    },
  );
  test('changing accounts clears all derived session credentials', () async {
    final api = DeezerAPI(
      arl: 'old-test',
      client: MockClient((_) async => reply(session())),
    );
    await api.authorize();
    api.arl = 'new-test';
    expect(api.sid, isNull);
    expect(api.token, isNull);
    expect(api.licenseToken, isNull);
    expect(api.userId, isNull);
    expect(api.favoritesPlaylistId, isNull);
  });
  test('an old in-flight session cannot overwrite a new account', () async {
    final gate = Completer<void>();
    final api = DeezerAPI(
      arl: 'old-test',
      client: MockClient((_) async {
        await gate.future;
        return reply(session());
      }),
    );
    final pending = api.authorize();
    api.arl = 'new-test';
    gate.complete();
    expect(await pending, isFalse);
    expect(api.token, isNull);
    expect(api.sid, isNull);
  });
  test('HTTP failures expose codes without exposing response bodies', () async {
    final api = DeezerAPI(
      arl: 'test-only',
      client: MockClient((_) async => http.Response('secret-content', 403)),
    );
    final errors = <Object>[];
    expect(await api.rawAuthorize(onError: errors.add), isFalse);
    expect(errors.single.toString(), contains('HTTP 403'));
    expect(errors.single.toString(), isNot(contains('secret-content')));
    expect(AppDiagnostics.instance.report(), isNot(contains('secret-content')));
  });
  test('a 200 HTML interstitial cannot be mistaken for JSON', () async {
    final api = DeezerAPI(
      arl: 'test-only',
      client: MockClient(
        (_) async => http.Response('<html>blocked</html>', 200),
      ),
    );
    final errors = <Object>[];
    expect(await api.rawAuthorize(onError: errors.add), isFalse);
    expect((errors.single as DeezerApiException).code, 'INVALID_JSON');
  });
  test('tracks without artists or lyrics round-trip through history', () {
    final restored = Track.fromMediaItem(
      Track(id: '1', title: 'Test', artists: []).toMediaItem(),
    );
    expect(restored.id, '1');
    expect(restored.lyrics, isNull);
    expect(restored.artists, isEmpty);
  });
  test('catalog numeric metadata accepts both strings and integers', () {
    final track = Track.fromPrivateJson({
      'SNG_ID': 1,
      'SNG_TITLE': 'Test',
      'DURATION': 180,
      'ALB_ID': 2,
      'ALB_TITLE': 'Album',
      'ALB_PICTURE': '',
      'ARTISTS': [],
      'DISK_NUMBER': 1,
      'DATE_ADD': '123',
    });
    expect(track.duration, const Duration(seconds: 180));
    expect(track.diskNumber, 1);
    expect(track.addedDate, 123);
  });
}
