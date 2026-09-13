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
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_git_repo.dart';
import '../support/fake_session.dart';

void main() {
  late Directory project;
  late String binPath;

  setUp(() {
    project = Directory.systemTemp.createTempSync('injectable_bridge_command_e2e_');
    binPath = p.join(Directory.current.path, 'bin', 'injectable.dart');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('a real --input, then --end, seal and record both halves under the same exchange id', () async {
    await initFakeGitRepo(project);
    final credentialsPath = writeFakeSession(project);
    final recipient = await X25519().newKeyPair();
    final recipientPublicKey = await recipient.extractPublicKey();
    final capturesDatabase = p.join(project.path, 'captures.sqlite3');
    final env = {
      'INJECTABLE_CREDENTIALS_PATH': credentialsPath,
      'INJECTABLE_CAPTURES_DATABASE': capturesDatabase,
      'INJECTABLE_CAPTURE_PUBLIC_KEY': base64Encode(recipientPublicKey.bytes),
      // A stored session makes this run's bridge also attempt syncCaptures
      // (see capture_sync_test.dart for that behaviour on its own). Pinned
      // to a port nothing ever listens on so this test's own assertions,
      // reading the two rows back before any sync could consume one, never
      // depend on what else happens to be running on the host.
      'INJECTABLE_BACKEND_URL': 'http://127.0.0.1:1',
    };

    await _runBridge(
      binPath,
      project,
      flag: '--input',
      payload: '{"prompt_id":"prompt-1","user_input":"refactor the login module"}',
      extraEnvironment: env,
    );
    await _runBridge(
      binPath,
      project,
      flag: '--end',
      payload: '{"prompt_id":"prompt-1","last_assistant_message":"done, see the diff"}',
      extraEnvironment: env,
    );

    final rows = pendingCaptures(databasePath: capturesDatabase);
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.exchangeId).toSet(), {'prompt-1'});
    expect(rows.map((row) => row.direction).toSet(), {'input', 'output'});

    final openedInput = await _open(rows.firstWhere((row) => row.direction == 'input').payload, recipient);
    final openedOutput = await _open(rows.firstWhere((row) => row.direction == 'output').payload, recipient);
    expect(utf8.decode(openedInput), 'refactor the login module');
    expect(utf8.decode(openedOutput), 'done, see the diff');
  });

  test('records nothing without a capture public key configured', () async {
    await initFakeGitRepo(project);
    final credentialsPath = writeFakeSession(project);
    final capturesDatabase = p.join(project.path, 'captures.sqlite3');

    await _runBridge(
      binPath,
      project,
      flag: '--input',
      payload: '{"prompt_id":"prompt-1","user_input":"refactor the login module"}',
      extraEnvironment: {
        'INJECTABLE_CREDENTIALS_PATH': credentialsPath,
        'INJECTABLE_CAPTURES_DATABASE': capturesDatabase,
      },
    );

    expect(File(capturesDatabase).existsSync(), isFalse);
  });

  test('succeeds without a stored session, since it never calls the backend', () async {
    await initFakeGitRepo(project);

    final exitCode = await _runBridge(binPath, project, flag: '--end', payload: '{"last_assistant_message":"done"}');

    expect(exitCode, 0);
  });

  test('succeeds and writes nothing, called with --start', () async {
    await initFakeGitRepo(project);

    final exitCode = await _runBridge(binPath, project, flag: '--start', payload: '{}');

    expect(exitCode, 0);
    expect(File(p.join(project.path, '.claude', 'context')).existsSync(), isFalse);
  });

  test('succeeds and writes nothing, called with no flag', () async {
    await initFakeGitRepo(project);

    final exitCode = await _runBridge(binPath, project, flag: null, payload: '{}');

    expect(exitCode, 0);
    expect(File(p.join(project.path, '.claude', 'context')).existsSync(), isFalse);
  });

  test('succeeds and writes nothing outside a git repository either', () async {
    final exitCode = await _runBridge(binPath, project, flag: '--end', payload: '{}');

    expect(exitCode, 0);
    expect(File(p.join(project.path, '.claude', 'context')).existsSync(), isFalse);
  });

  test('drains a payload larger than a pipe buffer without blocking', () async {
    await initFakeGitRepo(project);
    final largePayload = '{"transcript":"${'x' * (256 * 1024)}"}';

    final exitCode = await _runBridge(binPath, project, flag: '--end', payload: largePayload);

    expect(exitCode, 0);
  });
}

Future<int> _runBridge(
  String binPath,
  Directory project, {
  required String? flag,
  required String payload,
  Map<String, String> extraEnvironment = const {},
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', binPath, 'bridge', ?flag],
    workingDirectory: project.path,
    environment: {'INJECTABLE_UPDATE_CHECK_INTERVAL_SECONDS': '315360000000', ...extraEnvironment},
  );

  process.stdin.write(payload);
  await process.stdin.close();

  final stderrOutput = await process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;
  if (exitCode != 0) fail('injectable bridge exited $exitCode:\n$stderrOutput');
  return exitCode;
}

/// Reverses [seal] using primitives independent of it, exactly as
/// `capture_seal_test.dart` does, so this test proves the row a real
/// spawned `injectable bridge` process wrote is genuinely decryptable by
/// [recipient], not only that a row was written.
Future<List<int>> _open(Uint8List blob, SimpleKeyPair recipient) async {
  const ephemeralPublicKeyLength = 32;
  const nonceLength = 12;
  const macLength = 16;

  final ephemeralPublicKeyBytes = blob.sublist(0, ephemeralPublicKeyLength);
  final nonce = blob.sublist(ephemeralPublicKeyLength, ephemeralPublicKeyLength + nonceLength);
  final mac = blob.sublist(ephemeralPublicKeyLength + nonceLength, ephemeralPublicKeyLength + nonceLength + macLength);
  final cipherText = blob.sublist(ephemeralPublicKeyLength + nonceLength + macLength);

  final keyExchange = X25519();
  final sharedSecret = await keyExchange.sharedSecretKey(
    keyPair: recipient,
    remotePublicKey: SimplePublicKey(ephemeralPublicKeyBytes, type: KeyPairType.x25519),
  );

  final derivedKey = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: sharedSecret, nonce: ephemeralPublicKeyBytes, info: utf8.encode('dpw-capture-seal-v1'));

  return Chacha20.poly1305Aead().decrypt(
    SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
    secretKey: derivedKey,
  );
}
