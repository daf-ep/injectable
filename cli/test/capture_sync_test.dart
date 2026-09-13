// Copyright (C) 2026 Fiber
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0. A
// copy of it is available at
// https://polyformproject.org/licenses/noncommercial/1.0.0, and in the LICENSE
// file at the root of this repository.
//
// What you may do:
// - Use, study, and modify this software for any noncommercial purpose,
//   including personal use, research, education, and use by a charitable,
//   public research, public safety, health, environmental, or government
//   institution.
// - Distribute copies of it, with or without your changes, for those same
//   noncommercial purposes.
//
// What you may not do:
// - Use this software, or a modified or combined version of it, in a
//   commercial product or service, or for any other commercial purpose.
// - Sublicense it, or transfer your licence to someone else.
//
// What you must do in return:
// - Keep this notice on every file you received it on.
//
// Disclaimer:
// AS FAR AS THE LAW ALLOWS, THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY
// OR CONDITION OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR
// NON-INFRINGEMENT. IN NO EVENT SHALL FIBER BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING BUT NOT
// LIMITED TO LOSS OF USE, DATA, PROFITS, OR BUSINESS INTERRUPTION) ARISING OUT
// OF OR RELATED TO THESE TERMS OR THE USE OR NATURE OF THE SOFTWARE, UNDER ANY
// KIND OF LEGAL CLAIM.
//
// This header is a summary written for convenience. Where it differs from the
// LICENSE file, the LICENSE file governs.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cli/src/capture.dart';
import 'package:cli/src/capture_sync.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String databasePath;
  late http.Client httpClient;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('injectable_capture_sync_');
    databasePath = p.join(tempDir.path, 'captures.sqlite3');
    httpClient = http.Client();
  });

  tearDown(() {
    httpClient.close();
    tempDir.deleteSync(recursive: true);
  });

  test('sends every pending capture and removes each one the backend accepts', () async {
    _seed(databasePath, projectId: 'github.com/a/b', direction: 'input', exchangeId: 'p1');
    _seed(databasePath, projectId: 'github.com/a/b', direction: 'output', exchangeId: 'p1');

    final receivedAuth = <String>[];
    final receivedBodies = <Map<String, dynamic>>[];
    final server = await _fakeBackend((auth, body) {
      receivedAuth.add(auth);
      receivedBodies.add(body);
      return 202;
    });

    try {
      await syncCaptures(
        httpClient: httpClient,
        backendBaseUrl: 'http://${server.address.host}:${server.port}',
        databasePath: databasePath,
        sessionToken: 'a-real-looking-token',
      );

      expect(pendingCaptures(databasePath: databasePath), isEmpty);
      expect(receivedAuth, everyElement('Bearer a-real-looking-token'));
      expect(receivedBodies.map((b) => b['project']), everyElement('github.com/a/b'));
      expect(base64Decode(receivedBodies[0]['payload'] as String), utf8.encode('sealed-input'));
    } finally {
      await server.close(force: true);
    }
  });

  test('leaves a capture queued when the backend rejects it, and never sends the next one', () async {
    _seed(databasePath, projectId: 'github.com/a/b', direction: 'input', exchangeId: 'p1');
    _seed(databasePath, projectId: 'github.com/a/b', direction: 'output', exchangeId: 'p1');

    var callCount = 0;
    final server = await _fakeBackend((_, _) {
      callCount++;
      return 500;
    });

    try {
      await syncCaptures(
        httpClient: httpClient,
        backendBaseUrl: 'http://${server.address.host}:${server.port}',
        databasePath: databasePath,
        sessionToken: 'token',
      );

      expect(pendingCaptures(databasePath: databasePath), hasLength(2));
      expect(callCount, 1, reason: 'a rejection stops the batch rather than trying the next row anyway');
    } finally {
      await server.close(force: true);
    }
  });

  test('never creates the database when nothing has ever been captured', () async {
    await syncCaptures(
      httpClient: httpClient,
      backendBaseUrl: 'http://127.0.0.1:1',
      databasePath: databasePath,
      sessionToken: 'token',
    );

    expect(File(databasePath).existsSync(), isFalse);
  });

  test('leaves every capture queued when the backend cannot be reached at all', () async {
    _seed(databasePath, projectId: 'github.com/a/b', direction: 'input', exchangeId: 'p1');

    await syncCaptures(
      httpClient: httpClient,
      backendBaseUrl: 'http://127.0.0.1:1',
      databasePath: databasePath,
      sessionToken: 'token',
    );

    expect(pendingCaptures(databasePath: databasePath), hasLength(1));
  });

  test('a request the backend never answers gives up after uploadTimeout rather than hanging', () async {
    _seed(databasePath, projectId: 'github.com/a/b', direction: 'input', exchangeId: 'p1');

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSub = server.listen((request) {
      // Never responds: the connection is accepted, then left hanging.
    });

    try {
      final stopwatch = Stopwatch()..start();
      await syncCaptures(
        httpClient: httpClient,
        backendBaseUrl: 'http://${server.address.host}:${server.port}',
        databasePath: databasePath,
        sessionToken: 'token',
      );
      stopwatch.stop();

      expect(pendingCaptures(databasePath: databasePath), hasLength(1));
      expect(stopwatch.elapsed, lessThan(uploadTimeout + const Duration(seconds: 2)));
    } finally {
      await serverSub.cancel();
      await server.close(force: true);
    }
  });
}

void _seed(String databasePath, {required String projectId, required String direction, required String exchangeId}) {
  recordCapture(
    databasePath: databasePath,
    projectId: projectId,
    accountHost: 'github',
    accountLogin: 'someone',
    exchange: CapturedExchange(
      direction: direction,
      exchangeId: exchangeId,
      payload: Uint8List.fromList(utf8.encode('sealed-$direction')),
    ),
  );
}

/// A real local HTTP server standing in for `dpw-backend`'s
/// `POST /v1/context/captures`: [onRequest] reads the `authorization` header
/// and the decoded JSON body of each call and returns the status this
/// backend should answer with.
Future<HttpServer> _fakeBackend(int Function(String authorization, Map<String, dynamic> body) onRequest) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    final body = jsonDecode(rawBody) as Map<String, dynamic>;
    final status = onRequest(request.headers.value('authorization') ?? '', body);
    request.response.statusCode = status;
    await request.response.close();
  });
  return server;
}
