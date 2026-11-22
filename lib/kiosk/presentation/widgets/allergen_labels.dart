import 'package:flutter/material.dart';

/// Turns an allergen identifier into a word a customer can read.
///
/// ⚠ **The database stores identifiers, never prose.** `allergen_tags` holds
/// `peanuts`, `fish`, `crustaceans` — stable, language-free, and the same
/// value the dashboard, the app and the website all read. Printing the raw tag
/// on a kiosk would show an English word to a French customer and a developer's
/// word to everyone; translating it here is what keeps one fact in one place.
///
/// An unknown tag is shown as-is rather than dropped. A dish whose allergen the
/// kiosk does not recognise must still warn about it — silence is the one
/// outcome that can hurt somebody.
String allergenLabel(String tag, {required bool french}) {
  final Map<String, String> table = french ? _fr : _en;
  return table[tag.toLowerCase()] ?? tag;
}

/// A mark for the allergen, for people who scan rather than read.
///
/// ⚠ Never the only signal: every allergen is drawn with its WORD beside it.
/// Colour and icon alone fail colour-blind customers and anyone glancing, and
/// this is the one list on the borne where being missed has a consequence
/// worse than a wrong order.
IconData allergenIcon(String tag) => switch (tag.toLowerCase()) {
  'peanuts' || 'nuts' || 'sesame' => Icons.spa_outlined,
  'fish' => Icons.set_meal_outlined,
  'crustaceans' || 'molluscs' => Icons.bug_report_outlined,
  'milk' => Icons.local_drink_outlined,
  'eggs' => Icons.egg_outlined,
  'gluten' || 'wheat' => Icons.bakery_dining_outlined,
  'soy' => Icons.grass_outlined,
  _ => Icons.warning_amber_rounded,
};

/// The 14 EU-regulated allergens, plus what this kitchen actually uses.
const Map<String, String> _fr = <String, String>{
  'peanuts': 'Arachides',
  'nuts': 'Fruits à coque',
  'gluten': 'Gluten',
  'wheat': 'Blé',
  'milk': 'Lait',
  'eggs': 'Œufs',
  'fish': 'Poisson',
  'crustaceans': 'Crustacés',
  'molluscs': 'Mollusques',
  'soy': 'Soja',
  'sesame': 'Sésame',
  'mustard': 'Moutarde',
  'celery': 'Céleri',
  'sulphites': 'Sulfites',
  'lupin': 'Lupin',
};

const Map<String, String> _en = <String, String>{
  'peanuts': 'Peanuts',
  'nuts': 'Tree nuts',
  'gluten': 'Gluten',
  'wheat': 'Wheat',
  'milk': 'Milk',
  'eggs': 'Eggs',
  'fish': 'Fish',
  'crustaceans': 'Crustaceans',
  'molluscs': 'Molluscs',
  'soy': 'Soy',
  'sesame': 'Sesame',
  'mustard': 'Mustard',
  'celery': 'Celery',
  'sulphites': 'Sulphites',
  'lupin': 'Lupin',
};

/// A product tag (`products.tags`) as a word. Same rule as the allergens: the
/// database holds an identifier and the screen owns the language.
String? productTagLabel(String tag, {required bool french}) =>
    switch (tag.toLowerCase()) {
      'new' => french ? 'Nouveau' : 'New',
      'promo' => french ? 'Promo' : 'Deal',
      'spicy' => french ? 'Épicé' : 'Spicy',
      'veg' || 'vegetarian' => french ? 'Végétarien' : 'Vegetarian',
      'vegan' => french ? 'Végane' : 'Vegan',
      'popular' || 'bestseller' => french ? 'Populaire' : 'Popular',
      // ⚠ Unknown tags are NOT drawn. A tag is a marketing badge, and an
      // unrecognised one would put a developer's word on a customer's screen —
      // unlike an allergen, nobody is harmed by its absence.
      _ => null,
    };
