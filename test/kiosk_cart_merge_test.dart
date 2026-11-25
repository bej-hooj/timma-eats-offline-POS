import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_cart.dart';

void main() {
  const koki = SnapshotProduct(
    productId: 'koki',
    nameFr: 'Koki',
    nameEn: 'Koki',
    basePrice: 2000,
    type: 'dish',
    available: true,
  );
  const pepper = SnapshotOption(
    optionId: 'pepper',
    nameFr: 'Piment',
    nameEn: 'Chilli',
    priceDelta: 0,
    maxQty: 1,
    available: true,
  );
  const side = SnapshotOption(
    optionId: 'side',
    nameFr: 'Plantain',
    nameEn: 'Plantain',
    priceDelta: 200,
    maxQty: 1,
    available: true,
  );
  const large = SnapshotVariant(
    variantId: 'large',
    nameFr: 'Grande',
    nameEn: 'Large',
    priceDelta: 500,
  );

  test('matching adds reuse the line and multiply the quantity', () {
    final scope = ProviderContainer();
    addTearDown(scope.dispose);
    final cart = scope.read(kioskCartProvider.notifier);
    cart.add(product: koki, quantity: 1);
    final id = scope.read(kioskCartProvider).items.single.lineId;
    for (var i = 0; i < 3; i++) {
      cart.add(product: koki, quantity: 1);
    }
    final basket = scope.read(kioskCartProvider);
    expect(basket.items.single.lineId, id);
    expect(basket.items.single.quantity, 4);
    expect(basket.subtotal, 8000);
  });

  test('variants, pepper and removals distinguish cart lines', () {
    final scope = ProviderContainer();
    addTearDown(scope.dispose);
    final cart = scope.read(kioskCartProvider.notifier);
    cart.add(product: koki, quantity: 1);
    cart.add(product: koki, quantity: 1, variant: large);
    cart.add(product: koki, quantity: 1, options: [pepper, side]);
    cart.add(product: koki, quantity: 1, options: [side, pepper]);
    cart.add(product: koki, quantity: 1, removedIngredientIds: ['onion']);
    cart.add(product: koki, quantity: 2, removedIngredientIds: ['onion']);
    final lines = scope.read(kioskCartProvider).items;
    expect(lines.map((line) => line.quantity), [1, 1, 2, 3]);
    expect(lines.map((line) => line.hasPepper), [false, false, true, false]);
    expect(cart.toCartLines().last.removedIngredientIds, ['onion']);
  });
}
