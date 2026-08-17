import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'print_queue.dart';

/// A network ESC/POS printer on the restaurant LAN, port 9100.
///
/// **Network, not Bluetooth** (plan §K6): Bluetooth pairing on Android is a
/// support call per device and per OS update, and a thermal printer that must
/// be re-paired during a rush is a printer nobody uses.
///
/// A **fresh connection per job**, deliberately. A long-lived socket to a
/// thermal printer looks healthy for a long time after the printer has been
/// switched off — TCP reports a vanished peer as connected until something is
/// written and the window fills — which is the same lie about liveness the
/// link badge already refuses to tell (§1.7). Connecting per job means the
/// failure surfaces on the job that failed, not three jobs later.
class SocketPrinter implements PrinterTransport {
  SocketPrinter({
    required this.host,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  });

  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<void> send(Uint8List bytes) async {
    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(bytes);
      // `flush` is the only part that reports a write failure. Without it the
      // job is queued in the OS buffer and `close` returns happily on a printer
      // that is off, so every slip would "succeed".
      await socket.flush().timeout(timeout);
    } finally {
      socket.destroy();
    }
  }

  @override
  Future<int?> status() async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(EscPosStatusQuery.realtime);
      await socket.flush().timeout(timeout);
      final List<int> reply = await socket.first.timeout(timeout);
      return reply.isEmpty ? null : reply.first;
    } on Object {
      // A printer that will not answer is not the same as a printer that says
      // "no paper". Null means unknown, and the queue treats unknown as
      // "try the job and let it fail" rather than blocking the till.
      return null;
    } finally {
      socket?.destroy();
    }
  }
}

/// `DLE EOT 4`, kept beside the socket so a caller does not have to reach into
/// the slip's byte vocabulary to ask a printer how it is.
abstract final class EscPosStatusQuery {
  static const List<int> realtime = <int>[0x10, 0x04, 0x04];
}
