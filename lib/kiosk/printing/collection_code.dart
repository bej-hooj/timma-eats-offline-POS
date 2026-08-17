import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pos_core/pos_core.dart';

/// The code printed on the slip and scanned at `ready → completed`.
///
/// **It must be verifiable by the KDS from its own local store, with no
/// lookup** (plan §K6). That single constraint decides the whole design: the
/// slip exists to survive the outage, so a QR that needs a network round trip —
/// or even a hub round trip — breaks collection in exactly the situation it was
/// printed for.
///
/// So the payload is **self-describing and self-authenticating**: it carries the
/// ticket's own identifiers plus a MAC over them, keyed by a per-shift secret
/// both devices already hold from pairing. The KDS recomputes the MAC and
/// compares. No lookup, no clock dependency, no shared counter.
///
/// It is deliberately **not** just the ticket number. A kitchen that accepts
/// "42" scanned off any slip accepts yesterday's 42, the 42 from the branch
/// across town, and a 42 somebody wrote on a napkin — and the one moment this
/// code is used is the moment food is handed over for free.
class CollectionCode {
  const CollectionCode({
    required this.clientId,
    required this.branchId,
    required this.ticketNumber,
    required this.mac,
  });

  /// Builds the code for a placed order.
  factory CollectionCode.forOrder(PosOrder order, {required List<int> secret}) {
    final int ticket = order.ticketNumber ?? 0;
    return CollectionCode(
      clientId: order.clientId,
      branchId: order.branchId,
      ticketNumber: ticket,
      mac: _sign(
        clientId: order.clientId,
        branchId: order.branchId,
        ticketNumber: ticket,
        secret: secret,
      ),
    );
  }

  /// Parses a scanned payload. Returns null on anything malformed — a scanner
  /// reads barcodes off packaging, other restaurants' slips and the back of a
  /// hand, so garbage in is the normal case and must never throw at a cook.
  static CollectionCode? tryParse(String payload) {
    final List<String> parts = payload.split('|');
    if (parts.length != 5 || parts.first != _prefix) {
      return null;
    }
    final int? ticket = int.tryParse(parts[3]);
    if (ticket == null) {
      return null;
    }
    return CollectionCode(
      clientId: parts[1],
      branchId: parts[2],
      ticketNumber: ticket,
      mac: parts[4],
    );
  }

  static const String _prefix = 'TIMMA1';

  final String clientId;
  final String branchId;
  final int ticketNumber;
  final String mac;

  /// What goes in the QR. Pipe-delimited rather than JSON: a QR's capacity is
  /// the constraint that decides how big the printed square is, and JSON's
  /// braces and quotes buy nothing a fixed five-field layout does not.
  String get payload =>
      '$_prefix|$clientId|$branchId|$ticketNumber|$mac';

  /// True when this code was minted by a device holding [secret] **for this
  /// branch**. The branch check is not decoration: two TIMMA branches share a
  /// menu and a ticket-number sequence, so without it a slip from one collects
  /// food at the other.
  bool verifies({required List<int> secret, required String branchId}) {
    if (this.branchId != branchId) {
      return false;
    }
    final String expected = _sign(
      clientId: clientId,
      branchId: this.branchId,
      ticketNumber: ticketNumber,
      secret: secret,
    );
    return _constantTimeEquals(expected, mac);
  }

  static String _sign({
    required String clientId,
    required String branchId,
    required int ticketNumber,
    required List<int> secret,
  }) {
    final Hmac hmac = Hmac(sha256, secret);
    final Digest digest = hmac.convert(
      utf8.encode('$_prefix|$clientId|$branchId|$ticketNumber'),
    );
    // 12 hex characters — 48 bits. Enough that guessing one is hopeless against
    // a queue of a few hundred tickets a day, short enough that the QR stays
    // small on 58 mm paper.
    return digest.toString().substring(0, 12);
  }

  /// Length-independent comparison. The window here is small, but a MAC check
  /// that short-circuits on the first differing character is a habit worth not
  /// forming (§11).
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
