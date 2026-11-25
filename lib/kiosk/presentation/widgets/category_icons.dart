import 'package:flutter/material.dart';

/// An icon for a menu category, chosen for **this** menu.
///
/// Owner, 2026-11-22: *"think about icons that could fit our local content"* —
/// the reference tills are a burger, a pizza slice and a milkshake, which say
/// nothing about a card built on ndolé, eru, koki and poisson braisé. These are
/// picked for a Cameroonian menu: a grill for the braisés, a rice bowl for the
/// accompagnements, a bowl of soup for the pepper soup, a fish for the
/// poissons, and a dinner plate for the plats themselves.
///
/// ## ⚠ Why a local map and not a column
///
/// The right home for this is the dashboard — the same way `ingredients.icon`
/// carries an emoji an operator picked (migration 62). A category today has an
/// id, two names and a sort order, and **adding a field to the bundle changes
/// the canonical bytes and re-pins every borne**, which is a scheduled
/// operation and not something to do inside a design pass. So this maps the
/// NAME, accent- and case-insensitively, and anything unrecognised falls back
/// to a plate rather than to nothing. When an operator can choose the icon,
/// this map becomes the default rather than the answer.
Widget categoryIcon(String name, {required double size, required Color color}) {
  final String n = _fold(name);
  for (final MapEntry<List<String>, IconData?> entry in _byKeyword.entries) {
    if (entry.key.any(n.contains)) {
      final IconData? glyph = entry.value;
      return glyph == null
          ? KioskBottleIcon(size: size, color: color)
          : Icon(glyph, size: size, color: color);
    }
  }
  return Icon(Icons.dinner_dining, size: size, color: color);
}

/// Order matters: the first keyword that appears in the name wins, so the more
/// specific families are listed before the general ones. "Jus de foléré" must
/// reach the drinks entry before anything else claims it.
// A null glyph uses the custom bottle silhouette.
const Map<List<String>, IconData?> _byKeyword = <List<String>, IconData?>{
  <String>['tout', 'all', 'menu complet']: Icons.apps,
  <String>['boisson', 'drink', 'jus', 'eau', 'soda', 'bissap']: null,
  <String>['grillade', 'braise', 'braises', 'brochette', 'barbecue', 'soya']:
      Icons.outdoor_grill,
  <String>['soupe', 'soup', 'bouillon', 'pepper']: Icons.soup_kitchen,
  <String>['poisson', 'fish', 'mer', 'crevette', 'seafood']: Icons.set_meal,
  <String>['accompagnement', 'side', 'riz', 'bâton', 'baton', 'plantain']:
      Icons.rice_bowl,
  <String>['dessert', 'sucre', 'glace', 'patisserie', 'gateau']: Icons.icecream,
  <String>['petit dejeuner', 'dejeuner', 'beignet', 'pain', 'breakfast']:
      Icons.bakery_dining,
  <String>['snack', 'entree', 'apero', 'amuse']: Icons.tapas,
  <String>['volaille', 'poulet', 'chicken']: Icons.kebab_dining,
  <String>['plat', 'dish', 'repas', 'resistance', 'main']: Icons.dinner_dining,
};

/// A single capped beverage bottle for the drinks category.
class KioskBottleIcon extends StatelessWidget {
  const KioskBottleIcon({required this.size, required this.color, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _BottlePainter(color));
}

class _BottlePainter extends CustomPainter {
  const _BottlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final Paint ink = Paint()..color = color;
    final Path bottle = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(10, 6)
      ..lineTo(14, 6)
      ..lineTo(14, 8)
      ..quadraticBezierTo(14, 9, 16, 10)
      ..quadraticBezierTo(17, 11, 17, 12)
      ..lineTo(17, 20)
      ..quadraticBezierTo(17, 22, 15, 22)
      ..lineTo(9, 22)
      ..quadraticBezierTo(7, 22, 7, 20)
      ..lineTo(7, 12)
      ..quadraticBezierTo(7, 11, 8, 10)
      ..quadraticBezierTo(10, 9, 10, 8)
      ..close()
      ..addRect(const Rect.fromLTRB(9, 14, 15, 17));
    canvas.drawPath(bottle, ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(9, 2, 15, 5),
        const Radius.circular(1),
      ),
      ink,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BottlePainter oldDelegate) => color != oldDelegate.color;
}

/// Lower-cases and strips the accents a French menu is full of, so "Entrées",
/// "ENTREES" and "entrees" are one word. Deliberately the same shape as the
/// menu search's own folding — a category that the search can find but the
/// icon map cannot is a bug waiting to be reported as "no icon on that one".
String _fold(String input) {
  const Map<String, String> accents = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ç': 'c',
    'œ': 'oe',
  };
  final StringBuffer out = StringBuffer();
  for (final String ch in input.toLowerCase().split('')) {
    out.write(accents[ch] ?? ch);
  }
  return out.toString();
}
