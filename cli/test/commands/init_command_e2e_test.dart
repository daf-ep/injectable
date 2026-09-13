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

import 'package:cli/src/rules/store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_git_repo.dart';
import '../support/fake_session.dart';

void main() {
  test('running init syncs the shared rules store and .mcp.json for real, in a real git repo', () async {
    final project = Directory.systemTemp.createTempSync('injectable_e2e_');
    final rulesStoreRoot = Directory.systemTemp.createTempSync('injectable_e2e_rules_store_');
    addTearDown(() => project.deleteSync(recursive: true));
    addTearDown(() => rulesStoreRoot.deleteSync(recursive: true));
    await initFakeGitRepo(project, remote: 'git@github.com:injectable-tests/init-e2e.git');

    final binPath = p.join(Directory.current.path, 'bin', 'injectable.dart');

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', binPath, 'init'],
      workingDirectory: project.path,
      environment: {
        'INJECTABLE_RULES_DIR': rulesStoreRoot.path,
        'INJECTABLE_UPDATE_CHECK_INTERVAL_SECONDS': '315360000000',
        'INJECTABLE_CREDENTIALS_PATH': writeFakeSession(rulesStoreRoot),
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('this project is github.com/injectable-tests/init-e2e'));
    expect(readRule(storeRoot: rulesStoreRoot, name: 'rules', type: 'rules'), isNotNull);
    expect(File(p.join(project.path, '.claude', 'injectable', 'push.md')).existsSync(), isTrue);
    expect(File(p.join(project.path, '.gitignore')).readAsStringSync(), contains('.claude/context'));
    expect(File(p.join(project.path, '.claude', 'settings.json')).existsSync(), isFalse);

    final settings =
        jsonDecode(File(p.join(project.path, '.claude', 'settings.local.json')).readAsStringSync())
            as Map<String, dynamic>;
    expect(
      (settings['env'] as Map<String, dynamic>)['ANTHROPIC_BASE_URL'],
      'http://localhost:8080/p/github.com/injectable-tests/init-e2e/injectable-tests',
    );

    final mcpConfig = jsonDecode(File(p.join(project.path, '.mcp.json')).readAsStringSync()) as Map<String, dynamic>;
    final servers = mcpConfig['mcpServers'] as Map<String, dynamic>;
    expect(servers['injectable-decisions'], {
      'command': 'injectable',
      'args': ['mcp'],
    });
  });

  test('refuses to run outside a git repository', () async {
    final project = Directory.systemTemp.createTempSync('injectable_e2e_no_git_');
    addTearDown(() => project.deleteSync(recursive: true));

    final binPath = p.join(Directory.current.path, 'bin', 'injectable.dart');

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', binPath, 'init'],
      workingDirectory: project.path,
      environment: {'INJECTABLE_CREDENTIALS_PATH': writeFakeSession(project)},
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('not a git repository'));
  });

  test('refuses a remote hosted anywhere but GitHub or GitLab', () async {
    final project = Directory.systemTemp.createTempSync('injectable_e2e_wrong_host_');
    addTearDown(() => project.deleteSync(recursive: true));
    await initFakeGitRepo(project, remote: 'git@bitbucket.org:someone/somewhere.git');

    final binPath = p.join(Directory.current.path, 'bin', 'injectable.dart');

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', binPath, 'init'],
      workingDirectory: project.path,
      environment: {'INJECTABLE_CREDENTIALS_PATH': writeFakeSession(project)},
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('only GitHub and GitLab'));
  });

  test('refuses to run at all without a stored session', () async {
    final project = Directory.systemTemp.createTempSync('injectable_e2e_no_session_');
    addTearDown(() => project.deleteSync(recursive: true));
    await initFakeGitRepo(project, remote: 'git@github.com:injectable-tests/init-e2e-no-session.git');

    final binPath = p.join(Directory.current.path, 'bin', 'injectable.dart');

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', binPath, 'init'],
      workingDirectory: project.path,
      environment: {'INJECTABLE_CREDENTIALS_PATH': p.join(project.path, 'no-credentials-here')},
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('not logged in'));
  });
}
