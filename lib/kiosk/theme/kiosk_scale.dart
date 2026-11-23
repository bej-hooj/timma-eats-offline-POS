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

  /// A category pill: icon, name and count on ONE line (owner, 2026-11-23).
  ///
  /// ⚠ It was 88 — tall enough to stack the three — and every dp of that came
  /// off the dish grid on every screen. Laid out in a row the pill needs no
  /// more than the touch rule already demands, so the strip now costs the
  /// menu nothing beyond [minTarget].
  static const double categoryTileHeight = minTarget;

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
  /// ⚠ Narrowed from 320 on 2026-11-22. On the GM92 (1097 dp wide) a 320 dp
  /// card gave three-and-a-bit columns of very large tiles — the owner's words
  /// were "the cards are too big" — against reference kiosks that put four to
  /// six compact tiles across and let the PHOTOGRAPH do the selling. 232 dp
  /// fits four on the GM92 with the grid's gutters and still clears the 72 dp
  /// touch rule several times over.
  static const double dishCardWidth = 212;

  /// The dish name on a card. **Not** [bodySize]: 22 pt was sized for a 320 dp
  /// tile and wrapped "Pepper soup de bœuf TIMMA" onto three lines in a 232 dp
  /// one. 17 matches the customer app's card title (its `titleMedium` is 18 at
  /// a smaller physical size), which is the whole point — the owner wants one
  /// menu, drawn twice.
  static const double cardTitleSize = 17;

  /// The price on a card: the same size as the name but heavier and in the
  /// brand green, so the eye reads name-then-price without a size jump.
  static const double cardPriceSize = 17;

  /// Sold-out, and any other badge drawn over a photograph. Deliberately the
  /// smallest type on the screen: a barrier has to be legible, not loud, and
  /// at `labelLarge` it covered a third of the picture.
  static const double badgeSize = 13;

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
