import 'dart:convert';
import 'dart:typed_data';

/// The ESC/POS byte vocabulary this product uses, and nothing more.
///
/// Written out rather than pulled from a package: the slip needs perhaps a
/// dozen commands, a thermal printer's failure mode is a customer standing at a
/// counter with no proof of an order, and a dependency that silently changes
/// its idea of "cut" between versions is not worth the saved afternoon. Every
/// constant below is from the Epson ESC/POS command reference that every
/// generic 58/80 mm network printer implements.
abstract final class EscPos {
  static const int esc = 0x1B;
  static const int gs = 0x1D;
  static const int lf = 0x0A;

  /// `ESC @` — reset. Sent first on every job, because the previous job may
  /// have died mid-format and left the printer bold, upside down, or in a
  /// character set nobody chose.
  static const List<int> initialize = <int>[esc, 0x40];

  /// `ESC a n` — 0 left, 1 centre, 2 right.
  static List<int> align(int n) => <int>[esc, 0x61, n];

  /// `ESC E n` — emphasis on/off.
  static List<int> bold(bool on) => <int>[esc, 0x45, on ? 1 : 0];

  /// `GS ! n` — character size. Width and height multipliers 0–7 packed into
  /// one byte, high nibble width, low nibble height.
  static List<int> size({int width = 0, int height = 0}) => <int>[
    gs,
    0x21,
    ((width & 0x07) << 4) | (height & 0x07),
  ];

  /// `GS V 66 n` — partial cut after feeding `n` dots, so the slip is still
  /// attached by a nub and cannot fall behind the machine.
  static const List<int> cut = <int>[gs, 0x56, 66, 0x00];

  static List<int> feed(int lines) => <int>[esc, 0x64, lines];

  /// A QR code, model 2, in the four `GS ( k` calls a printer expects: model,
  /// module size, error correction, store, print.
  ///
  /// Error correction is **M**, not L: a thermal slip lives in an apron pocket
  /// and gets scanned under a counter light. L saves a few modules and loses
  /// the scan.
  static List<int> qr(String data, {int moduleSize = 6}) {
    final List<int> payload = utf8.encode(data);
    final int length = payload.length + 3;
    return <int>[
      // Model 2.
      gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
      // Module size.
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize,
      // Error correction M.
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31,
      // Store the payload.
      gs, 0x28, 0x6B, length & 0xFF, (length >> 8) & 0xFF, 0x31, 0x50, 0x30,
      ...payload,
      // Print it.
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30,
    ];
  }

  /// `DLE EOT 4` — real-time status. Bit 5 of the reply is paper-out, bit 2 is
  /// the drawer/cover. Asked before a job rather than after: a slip that fails
  /// halfway has already taken the customer's place in the queue.
  static const List<int> paperStatus = <int>[0x10, 0x04, 0x04];

  static bool paperOut(int status) => (status & 0x60) != 0;

  /// Text in **CP858**, the code page every generic thermal printer ships with
  /// and the one that has `é`, `è`, `à` and `ç` — a French slip printed as
  /// `Pr?t` is a slip a customer cannot read. Characters outside it degrade to
  /// their unaccented form rather than to a question mark.
  static List<int> text(String value) => <int>[
    for (final int rune in value.runes) _cp858(rune),
  ];

  static int _cp858(int rune) {
    if (rune < 0x80) {
      return rune;
    }
    return _cp858Map[rune] ?? _stripAccent(rune);
  }

  static int _stripAccent(int rune) => switch (rune) {
    0x0152 => 0x4F, // Œ
    0x0153 => 0x6F, // œ
    _ => 0x3F,
  };

  static const Map<int, int> _cp858Map = <int, int>{
    // MoneyFormatter joins its groups with a NON-BREAKING space so "12 500
    // FCFA" cannot wrap on screen. A thermal slip is fixed-width and does not
    // wrap, so the distinction buys nothing here — and left unmapped it fell
    // off the code page, which a test caught as "3?500?FCFA". Plain space.
    0xA0: 0x20,
    0xE7: 0x87, // ç
    0xFC: 0x81, // ü
    0xE9: 0x82, // é
    0xE2: 0x83, // â
    0xE4: 0x84, // ä
    0xE0: 0x85, // à
    0xE8: 0x8A, // è
    0xEB: 0x89, // ë
    0xEA: 0x88, // ê
    0xEF: 0x8B, // ï
    0xEE: 0x8C, // î
    0xF4: 0x93, // ô
    0xF6: 0x94, // ö
    0xFB: 0x96, // û
    0xF9: 0x97, // ù
    // Uppercase accents matter as much as lowercase: the slip's own take-away
    // line starts with "À", and a test caught it printing as "?".
    0xC0: 0xB7, // À
    0xC2: 0xB6, // Â
    0xC4: 0x8E, // Ä
    0xC7: 0x80, // Ç
    0xC8: 0xD4, // È
    0xC9: 0x90, // É
    0xCA: 0xD2, // Ê
    0xCB: 0xD3, // Ë
    0xCE: 0xD7, // Î
    0xCF: 0xD8, // Ï
    0xD4: 0xE2, // Ô
    0xD6: 0x99, // Ö
    0xD9: 0xEB, // Ù
    0xDB: 0xEA, // Û
    0xDC: 0x9A, // Ü
    0xB0: 0xF8, // °
    0x20AC: 0xD5, // €
  };

  static Uint8List build(List<List<int>> parts) =>
      Uint8List.fromList(<int>[for (final List<int> part in parts) ...part]);
}
