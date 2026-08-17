/// The kiosk is read by a **standing customer at arm's length** — a tablet at
/// roughly 60–70 cm, not a phone at 30 cm. Every size here is that one fact.
///
/// The phone app's scale is not a starting point to nudge: at 60 cm a 16sp
/// label subtends about half the visual angle it does in the hand, and a 48dp
/// target is tapped by a thumb that is no longer resting against the device.
/// Sizes are therefore stated outright rather than derived from
/// `Theme.textTheme`, so nobody "tidies" the kiosk back down to phone metrics.
abstract final class KioskScale {
  /// Minimum touch target. The phone app uses 48dp (CLAUDE.md §13.3); a
  /// standing customer misses that, and a miss on a kiosk is a customer
  /// looking for staff.
  static const double minTarget = 72;

  /// The 8pt grid the rest of the product is on (§13.1), used at kiosk sizes.
  static const double gap = 8;
  static const double gapMd = 16;
  static const double gapLg = 24;
  static const double gapXl = 40;
  static const double gapXxl = 64;

  static const double bodySize = 22;
  static const double labelSize = 18;
  static const double titleSize = 28;
  static const double headlineSize = 40;
  static const double displaySize = 64;

  /// The counter number is the one thing a customer reads from several metres
  /// away while standing up again, and the one thing staff read across a
  /// counter. It is deliberately larger than anything else the product renders.
  static const double counterNumberSize = 120;

  static const double radius = 20;
  static const double radiusLg = 32;

  /// Dish photography carries this surface, so cards are generous.
  static const double dishCardWidth = 320;

  /// The customer app's dish-card proportion, 180 × 208, kept exactly.
  ///
  /// The kiosk card is wider — a standing customer reads it from a metre away,
  /// not from their hand — but the SHAPE is the app's, so the same dish reads
  /// as the same product on both surfaces (owner, 2026-08-17: *"the POS kiosk
  /// should follow the current design of the app menu view"*).
  ///
  /// ⚠ The photo is **half the card by construction** in `KioskDishCard`, as
  /// two equal `Expanded`s — not a fixed image height. That rule comes from the
  /// app card, where every attempt to guess a photo height was wrong: a fixed
  /// 120 overflowed one text variant by 7 px and letting the photo take the
  /// slack measured 54 % of the card. There is deliberately no
  /// `dishCardImageHeight` constant any more, because having one is what let
  /// the two sides drift.
  static const double dishCardAspectRatio = 180 / 208;
  static const double dishCardHeight = dishCardWidth / dishCardAspectRatio;
}
