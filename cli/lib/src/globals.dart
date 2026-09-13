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

library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'auth/session_store.dart';
import 'base/common.dart';
import 'base/context.dart';
import 'base/logger.dart';
import 'git_identity.dart';
import 'rules/sync.dart';

/// The context the current zone carries.
AppContext get context => AppContext.current;

Logger? _loggerInstance;

/// Everything this run prints.
Logger get logger => context.get<Logger>() ?? (_loggerInstance ??= StdoutLogger());

/// Where this run's rules directory is, found once and read from the context after that.
///
/// Wrapped rather than looked up through the raw [Directory] type, so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class RulesSource {
  /// Wraps [directory], the answer [rulesSource] should give for this run.
  const RulesSource(this.directory);

  /// The rules directory this run reads from, or null when none was found.
  final Directory? directory;
}

/// The rules directory this run syncs from, or null when none was found.
Directory? get rulesSource => (context.get<RulesSource>() ?? RulesSource(findRulesSource())).directory;

/// The project this run works on.
///
/// Wrapped rather than looked up through the raw [Directory] type, so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register, and never has to mutate the real
/// [Directory.current] to point a command at a temporary project: doing that
/// is process-wide state, and races against any other test reading it at the
/// same time.
class ProjectRoot {
  /// Wraps [directory], the answer [projectRoot] should give for this run.
  const ProjectRoot(this.directory);

  /// The project this run works on.
  final Directory directory;
}

/// The project this run works on, [Directory.current] unless overridden.
Directory get projectRoot => (context.get<ProjectRoot>() ?? ProjectRoot(Directory.current)).directory;

/// This project's id, [gitProjectId] of [projectRoot] unless overridden.
///
/// Wrapped rather than looked up through the raw [String] type, so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class GitProjectId {
  /// Wraps [value], the answer [projectId] should give for this run.
  const GitProjectId(this.value);

  /// The id this project's git remote gives it.
  final String value;
}

/// This project's id: `host/owner/repo`, read from its git remote.
Future<String> get projectId async {
  if (context.get<GitProjectId>() case final GitProjectId overridden) return overridden.value;
  return gitProjectId(projectRoot);
}

/// Where the decisions database this run reads and writes lives.
///
/// Wrapped rather than looked up through a raw [String], so a test overriding
/// it never risks colliding with an unrelated one a future override might
/// register.
class DecisionsDatabase {
  /// Wraps [path], the answer [decisionsDatabasePath] should give for this run.
  const DecisionsDatabase(this.path);

  /// The file this run's decisions database lives at.
  final String path;
}

/// The path to the decisions database this run reads and writes.
///
/// One database for every project, at a fixed place under the user's home,
/// so a decision made in one project stays queryable alongside every other
/// project's, keyed apart by the project id each row carries.
String get decisionsDatabasePath =>
    (context.get<DecisionsDatabase>() ?? DecisionsDatabase(_defaultDecisionsDatabasePath)).path;

String get _defaultDecisionsDatabasePath =>
    _injectableDataPath(envVariable: 'INJECTABLE_DECISIONS_DATABASE', filename: 'decisions.sqlite3');

/// Where the captures database this run reads and writes lives.
///
/// Wrapped rather than looked up through a raw [String], so a test overriding
/// it never risks colliding with an unrelated one a future override might
/// register.
class CapturesDatabase {
  /// Wraps [path], the answer [capturesDatabasePath] should give for this run.
  const CapturesDatabase(this.path);

  /// The file this run's captures database lives at.
  final String path;
}

/// The path to the local queue of captured exchanges not yet synced to
/// `dpw-backend`.
///
/// One database for every project, at a fixed place under the user's home,
/// on the same model as [decisionsDatabasePath]: a capture written here
/// stays scoped to the project and account it carries, never to the
/// directory it happened to run in.
String get capturesDatabasePath =>
    (context.get<CapturesDatabase>() ?? CapturesDatabase(_defaultCapturesDatabasePath)).path;

String get _defaultCapturesDatabasePath =>
    _injectableDataPath(envVariable: 'INJECTABLE_CAPTURES_DATABASE', filename: 'captures.sqlite3');

/// Wraps the answer [capturePublicKey] should give for this run, so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class CapturePublicKey {
  /// Wraps [bytes], the answer [capturePublicKey] should give for this run.
  const CapturePublicKey(this.bytes);

  /// The public key this run seals captures under, or null when there is
  /// none to seal under yet.
  final Uint8List? bytes;
}

/// The public key captures are sealed under before ever touching disk, or
/// null when `dpw-backend` has not published one yet.
///
/// There is no compiled-in default: a key nobody can point back to a real
/// `dpw-backend` deployment would look provisioned when it is not, and
/// whoever holds its matching private half is still an open decision (see
/// `philosophy.md`). Capture stays a no-op everywhere until
/// `INJECTABLE_CAPTURE_PUBLIC_KEY` (base64) actually names one.
Uint8List? get capturePublicKey =>
    (context.get<CapturePublicKey>() ?? CapturePublicKey(_defaultCapturePublicKey)).bytes;

Uint8List? get _defaultCapturePublicKey {
  final encoded = Platform.environment['INJECTABLE_CAPTURE_PUBLIC_KEY'];
  if (encoded == null || encoded.isEmpty) return null;
  return base64Decode(encoded);
}

/// Where the shared rules store this run reads and writes lives.
///
/// Wrapped rather than looked up through the raw [Directory] type, so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class RulesStoreRoot {
  /// Wraps [directory], the answer [rulesStoreRoot] should give for this run.
  const RulesStoreRoot(this.directory);

  /// The directory this run's rules store lives at.
  final Directory directory;
}

/// The directory the rules store this run reads and writes lives at.
///
/// One store for every project on the machine, at a fixed place under the
/// user's home, so `injectable init` writes the corpus once and every project's
/// `injectable mcp` reads that same copy instead of one duplicated per project.
Directory get rulesStoreRoot =>
    (context.get<RulesStoreRoot>() ?? RulesStoreRoot(Directory(_defaultRulesStoreRootPath))).directory;

String get _defaultRulesStoreRootPath => _injectableDataPath(envVariable: 'INJECTABLE_RULES_DIR', filename: 'rules');

/// How long a remote update check, once made, holds off the next one.
///
/// Wrapped rather than looked up through a raw [Duration], so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class RemoteUpdateCheckInterval {
  /// Wraps [duration], the answer [remoteUpdateCheckInterval] should give
  /// for this run.
  const RemoteUpdateCheckInterval(this.duration);

  /// The interval this run holds a check off for.
  final Duration duration;
}

/// How long this run holds a remote update check off for, a day unless
/// overridden.
Duration get remoteUpdateCheckInterval =>
    (context.get<RemoteUpdateCheckInterval>() ?? RemoteUpdateCheckInterval(_defaultRemoteUpdateCheckInterval)).duration;

Duration get _defaultRemoteUpdateCheckInterval =>
    _durationFromEnv(envVariable: 'INJECTABLE_UPDATE_CHECK_INTERVAL_SECONDS', defaultValue: const Duration(days: 1));

/// Where this run's stored injectable session lives.
///
/// Wrapped rather than looked up through a raw [String], so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class CredentialsPath {
  /// Wraps [path], the answer [credentialsPath] should give for this run.
  const CredentialsPath(this.path);

  /// The file this run's stored session lives at.
  final String path;
}

/// The path `injectable login` writes to and every other command reads from.
String get credentialsPath => (context.get<CredentialsPath>() ?? CredentialsPath(_defaultCredentialsPath)).path;

String get _defaultCredentialsPath =>
    _injectableDataPath(envVariable: 'INJECTABLE_CREDENTIALS_PATH', filename: 'credentials');

/// The session this run is authenticated under.
///
/// Wrapped rather than looked up through a raw nullable [StoredSession], so
/// a test overriding it never risks colliding with an unrelated one a
/// future override might register, and so [InjectableCommand.run] reads the store
/// at most once per run instead of hitting disk again for every command
/// that needs it.
class StoredCredentials {
  /// Wraps [session], the answer [storedSession] should give for this run.
  const StoredCredentials(this.session);

  /// The session this run found on disk, or null when there is none.
  final StoredSession? session;
}

/// The session this run is authenticated under, or null when `injectable login`
/// was never run on this machine, or `injectable logout` cleared it.
StoredSession? get storedSession =>
    (context.get<StoredCredentials>() ?? StoredCredentials(SessionStore(credentialsPath).read())).session;

/// Where injectable's backend API lives.
///
/// Wrapped rather than looked up through a raw [String], so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class BackendBaseUrl {
  /// Wraps [url], the answer [backendBaseUrl] should give for this run.
  const BackendBaseUrl(this.url);

  /// Where this run's backend calls go.
  final String url;
}

/// Where this run's backend calls go, `http://localhost:8080` unless
/// `INJECTABLE_BACKEND_URL` says otherwise.
String get backendBaseUrl =>
    (context.get<BackendBaseUrl>() ??
            BackendBaseUrl(Platform.environment['INJECTABLE_BACKEND_URL'] ?? 'http://localhost:8080'))
        .url;

/// Where injectable's BYOK gateway lives.
///
/// Wrapped rather than looked up through a raw [String], so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class GatewayBaseUrl {
  /// Wraps [url], the answer [gatewayBaseUrl] should give for this run.
  const GatewayBaseUrl(this.url);

  /// Where this run's gateway calls go.
  final String url;
}

/// Where this run's gateway calls go, [backendBaseUrl] unless
/// `INJECTABLE_GATEWAY_URL` says otherwise.
///
/// The gateway and the backend API are the same deployed `dpw-backend`, so
/// a project with no separate gateway deployment needs nothing beyond the
/// backend url it already sets.
String get gatewayBaseUrl =>
    (context.get<GatewayBaseUrl>() ?? GatewayBaseUrl(Platform.environment['INJECTABLE_GATEWAY_URL'] ?? backendBaseUrl))
        .url;

/// Wraps the answer [githubOAuthClientId] should give for this run, kept
/// apart from [GitLabOAuthClientId] so overriding one host's client id in a
/// test never overrides the other's too.
class GitHubOAuthClientId {
  /// Wraps [value], the answer [githubOAuthClientId] should give for this
  /// run.
  const GitHubOAuthClientId(this.value);

  /// This run's GitHub client id, or null when unset.
  final String? value;
}

/// The OAuth client id `injectable login` presents to GitHub, or null when
/// `INJECTABLE_GITHUB_CLIENT_ID` is not set.
String? get githubOAuthClientId =>
    (context.get<GitHubOAuthClientId>() ?? GitHubOAuthClientId(Platform.environment['INJECTABLE_GITHUB_CLIENT_ID']))
        .value;

/// Wraps the answer [gitlabOAuthClientId] should give for this run, kept
/// apart from [GitHubOAuthClientId] so overriding one host's client id in a
/// test never overrides the other's too.
class GitLabOAuthClientId {
  /// Wraps [value], the answer [gitlabOAuthClientId] should give for this
  /// run.
  const GitLabOAuthClientId(this.value);

  /// This run's GitLab client id, or null when unset.
  final String? value;
}

/// The OAuth client id `injectable login` presents to GitLab, or null when
/// `INJECTABLE_GITLAB_CLIENT_ID` is not set.
String? get gitlabOAuthClientId =>
    (context.get<GitLabOAuthClientId>() ?? GitLabOAuthClientId(Platform.environment['INJECTABLE_GITLAB_CLIENT_ID']))
        .value;

/// Where this run's GitLab instance lives for the sake of `injectable login`,
/// `https://gitlab.com` unless `INJECTABLE_GITLAB_BASE_URL` says otherwise.
///
/// Wrapped rather than looked up through a raw [String], so a test
/// overriding it never risks colliding with an unrelated one a future
/// override might register.
class GitLabOAuthBaseUrl {
  /// Wraps [url], the answer [gitlabOAuthBaseUrl] should give for this run.
  const GitLabOAuthBaseUrl(this.url);

  /// This run's GitLab base url.
  final String url;
}

/// Where this run logs into GitLab through.
String get gitlabOAuthBaseUrl =>
    (context.get<GitLabOAuthBaseUrl>() ??
            GitLabOAuthBaseUrl(Platform.environment['INJECTABLE_GITLAB_BASE_URL'] ?? 'https://gitlab.com'))
        .url;

Duration _durationFromEnv({required String envVariable, required Duration defaultValue}) {
  if (Platform.environment[envVariable] case final String overridden when overridden.isNotEmpty) {
    return Duration(seconds: int.parse(overridden));
  }
  return defaultValue;
}

String _injectableDataPath({required String envVariable, required String filename}) {
  if (Platform.environment[envVariable] case final String overridden when overridden.isNotEmpty) {
    return overridden;
  }

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) throwToolExit('injectable: could not find the home directory to store $filename in');
  return p.join(home, '.local', 'share', 'injectable', filename);
}
