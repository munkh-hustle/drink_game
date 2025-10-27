// lib/data/card_collections.dart
import 'default_cards.dart';
import 'halloween_cards.dart';

class CardCollection {
  final String name;
  final List<String> cards;
  final bool isDefault;
  final String id; // Add unique identifier

  CardCollection({
    required this.name,
    required this.cards,
    this.isDefault = false,
    String? id,
  }) : id = id ?? name; // Use name as ID if not provided

  // Helper method to convert to map for JSON
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'cards': cards, 'isDefault': isDefault};
  }

  // Helper method to create from JSON
  factory CardCollection.fromJson(Map<String, dynamic> json) {
    return CardCollection(
      id: json['id'],
      name: json['name'],
      cards: (json['cards'] as List<dynamic>).cast<String>(),
      isDefault: json['isDefault'] ?? false,
    );
  }
}

final List<CardCollection> defaultCollections = [
  CardCollection(
    name: "Хий эсвэл Уу Vol.1",
    cards: defaultCards,
    isDefault: true,
    id: "default_cards",
  ),
  CardCollection(
    name: "Парти шийтгэл",
    cards: ["Everyone take a shot!"],
    isDefault: true,
    id: "party_punishments",
  ),
  CardCollection(
    name: "Үнэн эсвэл шийтгэл",
    cards: ["Reveal your most embarrassing moment"],
    isDefault: true,
    id: "truth_or_dare",
  ),
  CardCollection(
    name: "Halloween кардс",
    cards: halloweenCards,
    isDefault: true,
    id: "default_cards",
  ),
];
