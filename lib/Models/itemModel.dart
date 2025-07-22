// class Item {
//   final String id;
//   final String itemName;
//   final double costPrice;
//   final double qtyOnHand;
//
//   Item({
//     required this.id,
//     required this.itemName,
//     required this.costPrice,
//     required this.qtyOnHand,
//   });
//
//   factory Item.fromMap(Map<dynamic, dynamic> data, String id) {
//     return Item(
//       id: id,
//       itemName: data['itemName'] ?? '',
//       costPrice: data['costPrice']?.toDouble() ?? 0.0,
//       qtyOnHand: data['qtyOnHand']?.toDouble() ?? 0.0,
//     );
//   }
// }

class Item {
  final String id;
  final String itemName;
  final double costPrice;
  final double salePrice;
  final double qtyOnHand;
  final String? unit;
  final String? vendor;
  final String? category;
  final Map<String, double>? customerBasePrices;

  Item({
    required this.id,
    required this.itemName,
    required this.costPrice,
    required this.qtyOnHand,
    required this.salePrice,
    this.unit,
    this.vendor,
    this.category,
    this.customerBasePrices,
  });

  factory Item.fromMap(Map<dynamic, dynamic> data, String id) {
    // Convert customerBasePrices from Map<dynamic, dynamic> to Map<String, double>
    Map<String, double>? customerPrices;
    if (data['customerBasePrices'] != null) {
      customerPrices = {};
      (data['customerBasePrices'] as Map<dynamic, dynamic>).forEach((key, value) {
        customerPrices![key.toString()] = value.toDouble();
      });
    }

    return Item(
      id: id,
      itemName: data['itemName'] ?? '',
      costPrice: data['costPrice']?.toDouble() ?? 0.0,
      salePrice: data['salePrice']?.toDouble() ?? 0.0,
      qtyOnHand: data['qtyOnHand']?.toDouble() ?? 0.0,
      unit: data['unit'],
      vendor: data['vendor'],
      category: data['category'],
      customerBasePrices: customerPrices,
    );
  }

  // Add copyWith method
  Item copyWith({
    String? id,
    String? itemName,
    double? costPrice,
    double? salePrice,
    double? qtyOnHand,
    String? unit,
    String? vendor,
    String? category,
    Map<String, double>? customerBasePrices,
  }) {
    return Item(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      costPrice: costPrice ?? this.costPrice,
      salePrice: salePrice ?? this.salePrice,
      qtyOnHand: qtyOnHand ?? this.qtyOnHand,
      unit: unit ?? this.unit,
      vendor: vendor ?? this.vendor,
      category: category ?? this.category,
      customerBasePrices: customerBasePrices ?? this.customerBasePrices,
    );
  }

  // Helper method to get customer-specific price
  double getPriceForCustomer(String? customerId) {
    if (customerId == null || customerBasePrices == null) {
      return salePrice;
    }
    return customerBasePrices![customerId] ?? salePrice;
  }
}