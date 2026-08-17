import 'dart:async';
import 'dart:typed_data';

/// The seam between the queue and a real socket, mirroring `CloudRelayBackend`
/// in `pos_link`: the retry logic is the part that can be wrong, and it should
/// be provable without a printer on the desk.
abstract interface class PrinterTransport {
  /// Sends one job. Throws on any failure the queue should retry.
  Future<void> send(Uint8List bytes);

  /// The real-time status byte (`DLE EOT 4`), or null when the printer did not
  /// answer in time.
  Future<int?> status();
}

enum PrintJobState { queued, printing, printed, failed }

class PrintJob {
  PrintJob({required this.id, required this.bytes});

  final String id;
  final Uint8List bytes;
  PrintJobState state = PrintJobState.queued;
  int attempts = 0;
  String? lastError;
}

/// A print queue with retry, paper-out detection and reprint-last.
///
/// **A lost slip is a lost order** (plan §K6): a customer with no ticket number
/// has no way to collect and no proof they paid. So a failed job is never
/// silently dropped — it stays visible in [failed] until someone deals with it,
/// and [reprintLast] exists because the single most common recovery at a
/// counter is "print that again".
class PrintQueue {
  PrintQueue({
    required this.transport,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
  });

  final PrinterTransport transport;
  final int maxAttempts;
  final Duration retryDelay;

  final List<PrintJob> _pending = <PrintJob>[];
  final List<PrintJob> _failed = <PrintJob>[];
  PrintJob? _lastPrinted;
  bool _draining = false;
  bool _paperOut = false;

  /// Jobs that exhausted their retries. **Not** cleared automatically: the
  /// clear failure state §K6 asks for is one a human dismisses, because the
  /// alternative is a slip nobody knows was never printed.
  List<PrintJob> get failed => List<PrintJob>.unmodifiable(_failed);

  bool get paperOut => _paperOut;
  int get pendingCount => _pending.length;
  PrintJob? get lastPrinted => _lastPrinted;

  Future<PrintJob> enqueue(String id, Uint8List bytes) async {
    final PrintJob job = PrintJob(id: id, bytes: bytes);
    _pending.add(job);
    await drain();
    return job;
  }

  /// Reprints the last successful job. The counter's most common recovery —
  /// the slip jammed, tore, or the customer walked off without it.
  Future<PrintJob?> reprintLast() async {
    final PrintJob? last = _lastPrinted;
    if (last == null) {
      return null;
    }
    return enqueue('${last.id}-reprint', last.bytes);
  }

  /// Retries everything that failed. Called when someone has loaded paper or
  /// switched the printer back on.
  Future<void> retryFailed() async {
    final List<PrintJob> again = List<PrintJob>.of(_failed);
    _failed.clear();
    for (final PrintJob job in again) {
      job
        ..state = PrintJobState.queued
        ..attempts = 0;
      _pending.add(job);
    }
    await drain();
  }

  void dismissFailed() => _failed.clear();

  Future<void> drain() async {
    if (_draining) {
      return;
    }
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final PrintJob job = _pending.first;
        // Status is checked BEFORE the job, not after: a slip that fails
        // halfway has already taken the customer's place in the queue, and the
        // paper-out light is on the far side of the machine from the customer.
        final int? status = await transport.status();
        _paperOut = status != null && _isPaperOut(status);
        if (_paperOut) {
          job.lastError = 'paper_out';
          _fail(job);
          return;
        }

        job.state = PrintJobState.printing;
        job.attempts++;
        try {
          await transport.send(job.bytes);
          job.state = PrintJobState.printed;
          _pending.removeAt(0);
          // A reprint must not become the thing a further reprint copies, or
          // "print that again" drifts one job further back every time.
          if (!job.id.endsWith('-reprint')) {
            _lastPrinted = job;
          }
        } catch (error) {
          job.lastError = '$error';
          if (job.attempts >= maxAttempts) {
            _fail(job);
            return;
          }
          await Future<void>.delayed(retryDelay);
        }
      }
    } finally {
      _draining = false;
    }
  }

  void _fail(PrintJob job) {
    job.state = PrintJobState.failed;
    _pending.remove(job);
    _failed.add(job);
  }

  static bool _isPaperOut(int status) => (status & 0x60) != 0;
}
