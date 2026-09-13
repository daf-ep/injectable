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

import 'package:cli/src/auth/git_host.dart';
import 'package:cli/src/auth/session_store.dart';
import 'package:cli/src/base/context.dart';
import 'package:cli/src/base/logger.dart';
import 'package:cli/src/commands/init.dart';
import 'package:cli/src/globals.dart';
import 'package:cli/src/rules/store.dart';
import 'package:cli/src/runner/injectable_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_git_repo.dart';

void main() {
  test('logs through the injected logger instead of a real stream', () async {
    final rulesSource = Directory(p.join(Directory.current.path, '..', 'rules'));
    final workspace = Directory.systemTemp.createTempSync('injectable_init_command_');
    final project = Directory(p.join(workspace.path, 'project'))..createSync();
    final rulesStoreRoot = Directory.systemTemp.createTempSync('injectable_init_command_rules_store_');
    addTearDown(() => workspace.deleteSync(recursive: true));
    addTearDown(() => rulesStoreRoot.deleteSync(recursive: true));

    await initFakeGitRepo(project);

    final buffer = BufferLogger();

    final exitCode = await AppContext.current.run<int>(
      body: () => InitCommand().run(),
      overrides: <Type, Generator>{
        Logger: () => buffer,
        RulesSource: () => RulesSource(rulesSource),
        ProjectRoot: () => ProjectRoot(project),
        GitProjectId: () => const GitProjectId('github.com/injectable-tests/init-command-test'),
        RulesStoreRoot: () => RulesStoreRoot(rulesStoreRoot),
        RemoteUpdateCheckInterval: () => const RemoteUpdateCheckInterval(Duration(days: 365 * 100)),
        StoredCredentials: () => const StoredCredentials(
          StoredSession(token: 'test-token', host: GitHost.github, login: 'injectable-tests'),
        ),
      },
    );

    expect(exitCode, 0);
    expect(buffer.hadErrorOutput, isFalse);
    expect(buffer.statusText, contains('this project is github.com/injectable-tests/init-command-test'));
    expect(buffer.statusText, contains('shared rules synced into'));
    expect(buffer.statusText, contains('customization stubs ensured'));
    expect(buffer.statusText, contains('declared the mcp server'));
    expect(buffer.statusText, contains('declared the context hooks'));
    expect(readRule(storeRoot: rulesStoreRoot, name: 'rules', type: 'rules'), isNotNull);
    expect(File(p.join(project.path, '.claude', 'injectable', 'push.md')).existsSync(), isTrue);
    expect(File(p.join(project.path, '.mcp.json')).existsSync(), isTrue);

    expect(File(p.join(project.path, '.gitignore')).readAsStringSync(), contains('.claude/context'));

    expect(File(p.join(project.path, '.claude', 'settings.json')).existsSync(), isFalse);

    final settings =
        jsonDecode(File(p.join(project.path, '.claude', 'settings.local.json')).readAsStringSync())
            as Map<String, dynamic>;
    expect((settings['hooks'] as Map<String, dynamic>).keys, containsAll(['SessionStart', 'UserPromptSubmit', 'Stop']));
    expect(
      (settings['env'] as Map<String, dynamic>)['ANTHROPIC_BASE_URL'],
      'http://localhost:8080/p/github.com/injectable-tests/init-command-test/injectable-tests',
    );
  });

  test('warns instead of declaring a gateway url with no stored session', () async {
    final rulesSource = Directory(p.join(Directory.current.path, '..', 'rules'));
    final workspace = Directory.systemTemp.createTempSync('injectable_init_command_no_session_');
    final project = Directory(p.join(workspace.path, 'project'))..createSync();
    final rulesStoreRoot = Directory.systemTemp.createTempSync('injectable_init_command_no_session_rules_store_');
    addTearDown(() => workspace.deleteSync(recursive: true));
    addTearDown(() => rulesStoreRoot.deleteSync(recursive: true));

    await initFakeGitRepo(project);

    final buffer = BufferLogger();

    // Calls runCommand directly, bypassing the session guard InitCommand.run
    // applies before ever reaching it: that guard already refuses every
    // command but login, logout and bridge without a stored session, so this
    // is the only way to exercise runCommand's own defensive check.
    final result = await AppContext.current.run<InjectableCommandResult>(
      body: () => InitCommand().runCommand(),
      overrides: <Type, Generator>{
        Logger: () => buffer,
        RulesSource: () => RulesSource(rulesSource),
        ProjectRoot: () => ProjectRoot(project),
        GitProjectId: () => const GitProjectId('github.com/injectable-tests/init-command-no-session-test'),
        RulesStoreRoot: () => RulesStoreRoot(rulesStoreRoot),
        StoredCredentials: () => const StoredCredentials(null),
      },
    );

    expect(result.exitStatus, ExitStatus.success);
    expect(buffer.statusText, contains('not logged in, skipped declaring the gateway base url'));
    expect(File(p.join(project.path, '.claude', 'settings.local.json')).existsSync(), isTrue);
    final settings =
        jsonDecode(File(p.join(project.path, '.claude', 'settings.local.json')).readAsStringSync())
            as Map<String, dynamic>;
    expect(settings.containsKey('env'), isFalse);
  });
}
