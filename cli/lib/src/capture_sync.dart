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

import 'package:http/http.dart' as http;

import 'capture.dart';

/// How long a single capture's upload may take before this attempt gives up
/// on it, so an unreachable `dpw-backend` never holds up whatever called this.
const uploadTimeout = Duration(seconds: 5);

/// Sends every capture at [databasePath] to [backendBaseUrl], oldest first,
/// removing each one via [deleteCapture] once `POST /v1/context/captures`
/// accepts it.
///
/// [payload] travels base64-encoded inside the JSON body: it is sealed
/// ciphertext (see `capture_seal.dart`), never text `jsonEncode` could carry
/// as is. Stops at the first capture that fails to send rather than trying
/// every remaining one: a `dpw-backend` that just refused or timed out is
/// unlikely to answer the next attempt any differently, and stopping keeps
/// the accumulated captures in their original order for whenever a later
/// call gets through. Never throws: the network, and everything downstream
/// of it, is exactly what this exists to be resilient to.
Future<void> syncCaptures({
  required http.Client httpClient,
  required String backendBaseUrl,
  required String databasePath,
  required String sessionToken,
}) async {
  // pendingCaptures opens (and so creates) the database at databasePath
  // unconditionally: a caller invoked on a machine that has never captured
  // anything yet must not leave one behind just by asking.
  if (!File(databasePath).existsSync()) return;

  for (final capture in pendingCaptures(databasePath: databasePath)) {
    final sent = await _trySend(
      httpClient: httpClient,
      backendBaseUrl: backendBaseUrl,
      sessionToken: sessionToken,
      capture: capture,
    );
    if (!sent) return;

    deleteCapture(databasePath: databasePath, id: capture.id);
  }
}

/// Whether [capture] reached [backendBaseUrl] and was accepted (a 2xx).
/// False for a network failure, a timeout, or a non-2xx status alike: this
/// call site's response to each is identical, so there is nothing else to
/// report a rejected request separately for.
Future<bool> _trySend({
  required http.Client httpClient,
  required String backendBaseUrl,
  required String sessionToken,
  required PendingCapture capture,
}) async {
  try {
    final response = await httpClient
        .post(
          Uri.parse('$backendBaseUrl/v1/context/captures'),
          headers: {'content-type': 'application/json', 'authorization': 'Bearer $sessionToken'},
          body: jsonEncode({'project': capture.projectId, 'payload': base64Encode(capture.payload)}),
        )
        .timeout(uploadTimeout);
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  }
}
