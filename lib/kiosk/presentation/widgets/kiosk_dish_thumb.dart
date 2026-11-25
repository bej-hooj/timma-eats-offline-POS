import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import '../../catalog/dish_photo_cache.dart';
import 'kiosk_shimmer.dart';

/// A dish's photograph, wherever a dish appears.
///
/// **Disk first, network second, brand panel last.** The cached copy is what
/// makes the menu survive the outage it was downloaded for; `Image.memory`
/// renders synchronously from bytes already in hand, so a cached photo paints on
/// the first frame instead of flickering through its fallback.
///
/// Extracted because there were three places a dish is shown — the menu card,
/// the cart row, the composer — and only the card had a picture at all. One
/// implementation means the cart cannot drift from the grid, and a dish that
/// looks a certain way on the menu looks the same in the basket.
class KioskDishThumb extends StatelessWidget {
  const KioskDishThumb({
    required this.photoUrl,
    required this.cache,
    this.size,
    this.radius = 0,
    this.iconSize = 56,
    super.key,
  });

  final String? photoUrl;
  final DishPhotoCache? cache;

  /// A square of this side, or unconstrained (fills its parent) when null —
  /// which is how the menu card uses it, as half of the card by construction.
  final double? size;

  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final Widget image = _image();
    final Widget clipped = radius > 0
        ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: image)
        : image;
    if (size == null) {
      return clipped;
    }
    return SizedBox(width: size, height: size, child: clipped);
  }

  Widget _image() {
    final String? source = photoUrl;
    if (source == null || source.isEmpty) {
      return _fallback();
    }
    final Uint8List? cached = cache?.readSync(source);
    if (cached != null) {
      return Image.memory(
        cached,
        fit: BoxFit.cover,
        // A corrupt cached file is a decoding failure, not a crash.
        errorBuilder: (BuildContext _, Object _, StackTrace? _) => _fallback(),
      );
    }
    // Not cached yet. A URL the cache refuses outright — not https, or not the
    // configured host — must not slip through the network branch, or the rule
    // would hold only until the first cache miss.
    if (cache != null && !cache!.isAllowed(source)) {
      return _fallback();
    }
    return Image.network(
      source,
      fit: BoxFit.cover,
      errorBuilder: (BuildContext _, Object _, StackTrace? _) => _fallback(),
      // ⚠ **The waiting state, which this had none of.** Until the bytes
      // arrived the card drew an empty hole — no panel, no sign of life — and
      // a hole in a menu on a machine facing the street reads as broken rather
      // than as slow (CLAUDE.md §13.2: the loading state is mandatory, and a
      // skeleton rather than a spinner).
      //
      // `wasSynchronouslyLoaded` is the cached case: those bytes are already
      // in hand, so they paint on the first frame with no fade and no shimmer.
      frameBuilder:
          (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
                fit: StackFit.passthrough,
                alignment: Alignment.center,
                children: <Widget>[...previous, ?current],
              ),
              child: frame == null
                  ? KioskShimmer(
                      key: const ValueKey<String>('shimmer'),
                      radius: radius,
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('photo'),
                      child: child,
                    ),
            );
          },
    );
  }

  /// A calm brand panel, never a broken-image glyph: production has dishes with
  /// no photograph and a kiosk facing the street cannot show a grey box.
  Widget _fallback() => ColoredBox(
    color: AppColors.primarySoft,
    child: Center(
      child: Icon(
        Icons.restaurant_menu,
        size: iconSize,
        color: AppColors.primary.withValues(alpha: 0.4),
      ),
    ),
  );
}
