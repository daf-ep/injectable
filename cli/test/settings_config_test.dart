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

import 'package:cli/src/settings_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  late File configFile;

  setUp(() {
    project = Directory.systemTemp.createTempSync('injectable_settings_config_');
    configFile = File(p.join(project.path, '.claude', 'settings.local.json'));
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('creates .claude/settings.local.json declaring every hook when none exists', () {
    ensureHooksDeclared(project);

    final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final hooks = config['hooks'] as Map<String, dynamic>;

    for (final entry in hookCommands.entries) {
      final groups = hooks[entry.key] as List<dynamic>;
      expect(groups, [
        {
          'hooks': [
            {'type': 'command', 'command': entry.value, 'timeout': 30},
          ],
        },
      ]);
    }
  });

  test('keeps a hook group the project already declared for itself, on the same event', () {
    configFile.parent.createSync(recursive: true);
    configFile.writeAsStringSync(
      jsonEncode({
        'hooks': {
          'Stop': [
            {
              'hooks': [
                {'type': 'command', 'command': 'some-other-tool --on-stop'},
              ],
            },
          ],
        },
      }),
    );

    ensureHooksDeclared(project);

    final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final hooks = config['hooks'] as Map<String, dynamic>;
    final stopGroups = (hooks['Stop'] as List<dynamic>).cast<Map<String, dynamic>>();

    expect(stopGroups, hasLength(2));
    expect(
      stopGroups.any(
        (group) => (group['hooks'] as List<dynamic>).cast<Map<String, dynamic>>().any(
          (hook) => hook['command'] == 'some-other-tool --on-stop',
        ),
      ),
      isTrue,
    );
  });

  test('keeps a top-level key that has nothing to do with hooks', () {
    configFile.parent.createSync(recursive: true);
    configFile.writeAsStringSync(jsonEncode({'somethingElse': 'kept as is'}));

    ensureHooksDeclared(project);

    final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

    expect(config['somethingElse'], 'kept as is');
  });

  test('replaces its own stale group rather than duplicating it', () {
    configFile.parent.createSync(recursive: true);
    configFile.writeAsStringSync(
      jsonEncode({
        'hooks': {
          'SessionStart': [
            {
              'hooks': [
                {'type': 'command', 'command': 'injectable bridge --start', 'timeout': 5},
              ],
            },
          ],
        },
      }),
    );

    ensureHooksDeclared(project);

    final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final hooks = config['hooks'] as Map<String, dynamic>;
    final groups = hooks['SessionStart'] as List<dynamic>;

    expect(groups, [
      {
        'hooks': [
          {'type': 'command', 'command': 'injectable bridge --start', 'timeout': 30},
        ],
      },
    ]);
  });

  test('never writes to .claude/settings.json, only its .local.json variant', () {
    ensureHooksDeclared(project);

    expect(File(p.join(project.path, '.claude', 'settings.json')).existsSync(), isFalse);
  });

  group('ensureGatewayUrlDeclared', () {
    test('declares ANTHROPIC_BASE_URL under env, scoped to the project and account', () {
      final wrote = ensureGatewayUrlDeclared(
        project,
        gatewayBaseUrl: 'https://gateway.example.com',
        projectId: 'github.com/injectable-tests/some-repo',
        login: 'octocat',
      );

      expect(wrote, isTrue);
      final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      expect(config, {
        'env': {'ANTHROPIC_BASE_URL': 'https://gateway.example.com/p/github.com/injectable-tests/some-repo/octocat'},
      });
      expect(File(p.join(project.path, '.claude', 'settings.json')).existsSync(), isFalse);
    });

    test('keeps an env entry the project already declared for itself', () {
      configFile.parent.createSync(recursive: true);
      configFile.writeAsStringSync(
        jsonEncode({
          'env': {'SOME_OTHER_VAR': 'kept as is'},
        }),
      );

      ensureGatewayUrlDeclared(
        project,
        gatewayBaseUrl: 'https://gateway.example.com',
        projectId: 'github.com/injectable-tests/some-repo',
        login: 'octocat',
      );

      final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      final env = config['env'] as Map<String, dynamic>;
      expect(env['SOME_OTHER_VAR'], 'kept as is');
      expect(env['ANTHROPIC_BASE_URL'], isNotNull);
    });

    test('keeps a top-level key that has nothing to do with env', () {
      configFile.parent.createSync(recursive: true);
      configFile.writeAsStringSync(jsonEncode({'somethingElse': 'kept as is'}));

      ensureGatewayUrlDeclared(
        project,
        gatewayBaseUrl: 'https://gateway.example.com',
        projectId: 'github.com/injectable-tests/some-repo',
        login: 'octocat',
      );

      final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      expect(config['somethingElse'], 'kept as is');
    });

    test('writes nothing and returns false when there is no stored login', () {
      final wrote = ensureGatewayUrlDeclared(
        project,
        gatewayBaseUrl: 'https://gateway.example.com',
        projectId: 'github.com/injectable-tests/some-repo',
        login: null,
      );

      expect(wrote, isFalse);
      expect(configFile.existsSync(), isFalse);
      expect(File(p.join(project.path, '.claude', 'settings.json')).existsSync(), isFalse);
    });
  });
}
