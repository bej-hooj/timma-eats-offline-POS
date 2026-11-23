import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_core/pos_core.dart';

/// One line as the customer built it, plus enough of the snapshot to render it.
///
/// The price fields here are **for reading only**. `PosEngine._price` prices the
/// order from the pinned snapshot when it is placed, and the database prices it
/// again on replay (§23.3, CLAUDE.md §0.2). Nothing computed in this file ever
/// reaches the engine — [toCartLine] deliberately carries ids and quantities
/// and nothing else.
class KioskCartItem {
  const KioskCartItem({
    required this.lineId,
    required this.product,
    required this.quantity,
    this.variant,
    this.options = const <SnapshotOption>[],
    this.removedIngredientIds = const <String>[],
  });

  final String lineId;
  final SnapshotProduct product;
  final int quantity;
  final SnapshotVariant? variant;
  final List<SnapshotOption> options;

  /// What the customer asked to leave out, by ingredient id.
  final List<String> removedIngredientIds;

  /// Minor units, for the customer to read. See the class note.
  ///
  /// This goes through the **same [Money] helpers the engine prices with**
  /// (`PosEngine._price`), not hand-rolled arithmetic. A cart that adds up
  /// differently from the engine shows the customer one number and charges
  /// another, and that divergence would live in whichever of the two nobody
  /// re-read. §3: one money utility per codebase.
  int get unitPrice => Money.unitPrice(
    basePrice: product.basePrice,
    variantDelta: variant?.priceDelta ?? 0,
    options: <OptionCharge>[
      for (final SnapshotOption o in options)
        OptionCharge(priceDelta: o.priceDelta, quantity: 1),
    ],
  );

  int get lineTotal =>
      Money.lineTotal(unitPrice: unitPrice, quantity: quantity);

  KioskCartItem copyWith({int? quantity}) => KioskCartItem(
    lineId: lineId,
    product: product,
    quantity: quantity ?? this.quantity,
    variant: variant,
    options: options,
    // ⚠ Carried, like the options. A `copyWith` that drops a field silently
    // loses it on the next quantity tap — the customer presses "+" in the
    // basket and their "sans piment" is gone, with nothing on screen to say
    // so.
    removedIngredientIds: removedIngredientIds,
  );

  /// Ids and quantities. The client proposes; the snapshot decides.
  PosCartLine toCartLine() => PosCartLine(
    productId: product.productId,
    quantity: quantity,
    variantId: variant?.variantId,
    options: <PosCartOption>[
      for (final SnapshotOption o in options)
        PosCartOption(optionId: o.optionId),
    ],
    removedIngredientIds: removedIngredientIds,
  );
}

class KioskCartState {
  const KioskCartState({this.items = const <KioskCartItem>[]});

  final List<KioskCartItem> items;

  bool get isEmpty => items.isEmpty;
  int get count =>
      items.fold<int>(0, (int sum, KioskCartItem i) => sum + i.quantity);

  /// Minor units, for the customer to read before they commit. Never sent.
  int get subtotal =>
      Money.subtotal(<int>[for (final KioskCartItem i in items) i.lineTotal]);
}

class KioskCartController extends Notifier<KioskCartState> {
  int _seq = 0;

  @override
  KioskCartState build() => const KioskCartState();

  void add({
    required SnapshotProduct product,
    required int quantity,
    SnapshotVariant? variant,
    List<SnapshotOption> options = const <SnapshotOption>[],
  }) {
    state = KioskCartState(
      items: <KioskCartItem>[
        ...state.items,
        KioskCartItem(
          lineId: 'k${_seq++}',
          product: product,
          quantity: quantity,
          variant: variant,
          options: options,
        ),
      ],
    );
  }

  void setQuantity(String lineId, int quantity) {
    if (quantity <= 0) {
      remove(lineId);
      return;
    }
    state = KioskCartState(
      items: <KioskCartItem>[
        for (final KioskCartItem i in state.items)
          if (i.lineId == lineId) i.copyWith(quantity: quantity) else i,
      ],
    );
  }

  void remove(String lineId) {
    state = KioskCartState(
      items: <KioskCartItem>[
        for (final KioskCartItem i in state.items)
          if (i.lineId != lineId) i,
      ],
    );
  }

  /// Called on idle timeout and after a completed sale. An abandoned basket
  /// must never become the next customer's order (plan §K4 rule 6).
  void clear() => state = const KioskCartState();

  List<PosCartLine> toCartLines() => <PosCartLine>[
    for (final KioskCartItem i in state.items) i.toCartLine(),
  ];
}

final NotifierProvider<KioskCartController, KioskCartState> kioskCartProvider =
    NotifierProvider<KioskCartController, KioskCartState>(
      KioskCartController.new,
    );
