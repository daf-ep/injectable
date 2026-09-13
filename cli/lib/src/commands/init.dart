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

import 'dart:io';

import 'package:path/path.dart' as p;

import '../base/common.dart';
import '../gitignore.dart';
import '../globals.dart' as globals;
import '../mcp_config.dart';
import '../rules/store.dart';
import '../rules/sync.dart';
import '../runner/injectable_command.dart';
import '../settings_config.dart';

/// Syncs the shared rules store from this checkout, ensures this project's
/// customization stubs exist, and declares injectable's MCP server in `.mcp.json`.
class InitCommand extends InjectableCommand {
  @override
  final name = 'init';

  @override
  final description = 'Sync the shared rules store from this checkout and declare the mcp server.';

  @override
  Future<InjectableCommandResult> runCommand() async {
    final cwd = globals.projectRoot;
    globals.logger.printStatus('injectable: this project is ${await globals.projectId}');

    final rulesSource = globals.rulesSource;
    if (rulesSource == null) {
      throwToolExit('injectable: no rules directory found next to this tool');
    }

    final storeRoot = globals.rulesStoreRoot;
    replaceGlobalContent(storeRoot: storeRoot, contents: collectRuleContents(rulesSource));
    globals.logger.printStatus('injectable: shared rules synced into ${storeRoot.path}');

    final projectFilesDest = Directory(p.join(cwd.path, '.claude', 'injectable'));
    syncProjectFiles(contents: collectProjectContents(rulesSource), destination: projectFilesDest);
    globals.logger.printStatus('injectable: customization stubs ensured in ${projectFilesDest.path}');

    ensureMcpServerDeclared(cwd);
    globals.logger.printStatus('injectable: declared the mcp server in .mcp.json');

    ensureGitignored(cwd, '.claude/context');
    ensureHooksDeclared(cwd);
    globals.logger.printStatus('injectable: declared the context hooks in .claude/settings.local.json');

    final declaredGatewayUrl = ensureGatewayUrlDeclared(
      cwd,
      gatewayBaseUrl: globals.gatewayBaseUrl,
      projectId: await globals.projectId,
      login: globals.storedSession?.login,
    );
    if (declaredGatewayUrl) {
      globals.logger.printStatus('injectable: declared the gateway base url in .claude/settings.local.json');
    } else {
      globals.logger.printStatus('injectable: not logged in, skipped declaring the gateway base url');
    }

    return const InjectableCommandResult.success();
  }
}
