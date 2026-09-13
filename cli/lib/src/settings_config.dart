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

import 'package:path/path.dart' as p;

/// The command injectable registers for each hook event it listens on, keyed by
/// the event name Claude Code fires.
const Map<String, String> hookCommands = {
  'SessionStart': 'injectable bridge --start',
  'UserPromptSubmit': 'injectable bridge --input',
  'Stop': 'injectable bridge --end',
};

/// Declares injectable's hooks in `.claude/settings.local.json` under
/// [projectRoot].
///
/// Only the matcher group carrying one of [hookCommands] is touched, added
/// if missing and replaced if already present: every other group a project
/// declared for itself under the same event, and every other top-level key
/// in the file, is kept exactly as it was. Written to the `.local.json`
/// variant rather than `.claude/settings.json`, because the latter is
/// routinely committed: a project's own history should not reveal that it
/// runs injectable.
void ensureHooksDeclared(Directory projectRoot) {
  final file = _settingsLocalFile(projectRoot);

  final Map<String, dynamic> config = _readConfig(file);
  final hooks = (config['hooks'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  for (final entry in hookCommands.entries) {
    hooks[entry.key] = _withInjectableGroup(hooks[entry.key], command: entry.value);
  }
  config['hooks'] = hooks;

  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(config)}\n');
}

/// Declares `ANTHROPIC_BASE_URL` in `.claude/settings.local.json` under
/// [projectRoot], pointed at the BYOK gateway for [projectId] under
/// [login].
///
/// Only the `ANTHROPIC_BASE_URL` entry under `env` is touched: every other
/// environment variable a project declared for itself, and every other
/// top-level key in the file, is kept exactly as it was. Nothing is
/// written, and this returns false, when [login] is null: without a
/// stored session there is no account to attribute the gateway's captures
/// to, and writing the url anyway would point Claude Code at a path with
/// no account segment.
bool ensureGatewayUrlDeclared(
  Directory projectRoot, {
  required String gatewayBaseUrl,
  required String projectId,
  required String? login,
}) {
  if (login == null) return false;

  final file = _settingsLocalFile(projectRoot);

  final Map<String, dynamic> config = _readConfig(file);
  final env = (config['env'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  env['ANTHROPIC_BASE_URL'] = '$gatewayBaseUrl/p/$projectId/$login';
  config['env'] = env;

  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(config)}\n');
  return true;
}

/// Where injectable writes the local, never-committed Claude Code settings
/// it declares under [projectRoot].
File _settingsLocalFile(Directory projectRoot) => File(p.join(projectRoot.path, '.claude', 'settings.local.json'));

List<dynamic> _withInjectableGroup(dynamic existingGroups, {required String command}) {
  final groups = (existingGroups as List<dynamic>?)?.cast<Map<String, dynamic>>().toList() ?? <Map<String, dynamic>>[];

  groups.removeWhere((group) {
    final entries = (group['hooks'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
    return entries.length == 1 && entries.single['command'] == command;
  });

  groups.add(<String, dynamic>{
    'hooks': [
      <String, dynamic>{'type': 'command', 'command': command, 'timeout': 30},
    ],
  });

  return groups;
}

Map<String, dynamic> _readConfig(File file) {
  if (!file.existsSync()) return <String, dynamic>{};

  final content = file.readAsStringSync().trim();
  if (content.isEmpty) return <String, dynamic>{};

  return jsonDecode(content) as Map<String, dynamic>;
}
