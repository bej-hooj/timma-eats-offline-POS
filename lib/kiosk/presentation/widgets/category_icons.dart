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
IconData categoryIcon(String name) {
  final String n = _fold(name);
  for (final MapEntry<List<String>, IconData> entry in _byKeyword.entries) {
    for (final String keyword in entry.key) {
      if (n.contains(keyword)) {
        return entry.value;
      }
    }
  }
  return Icons.dinner_dining;
}

/// Order matters: the first keyword that appears in the name wins, so the more
/// specific families are listed before the general ones. "Jus de foléré" must
/// reach the drinks entry before anything else claims it.
const Map<List<String>, IconData> _byKeyword = <List<String>, IconData>{
  <String>['tout', 'all', 'menu complet']: Icons.apps,
  <String>['boisson', 'drink', 'jus', 'jus de', 'eau', 'soda', 'bissap']:
      Icons.local_drink,
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
