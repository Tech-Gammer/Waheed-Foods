// import 'package:flutter/material.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:intl/intl.dart';
// import 'package:provider/provider.dart';
// import '../Provider/lanprovider.dart';
// import 'dart:typed_data';
// import 'package:pdf/pdf.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:printing/printing.dart';
//
// class ItemPurchasePage extends StatefulWidget {
//   final String? initialVendorId;
//   final String? initialVendorName;
//   final List<Map<String, dynamic>> initialItems;
//   final bool isFromPurchaseOrder;
//   final bool isEditMode;
//   final String? purchaseKey;
//
//   ItemPurchasePage({
//     this.initialVendorId,
//     this.initialVendorName,
//     this.initialItems = const [],
//     this.isFromPurchaseOrder = false,
//     this.isEditMode = false,
//     this.purchaseKey,
//   });
//
//   @override
//   _ItemPurchasePageState createState() => _ItemPurchasePageState();
// }
//
// class _ItemPurchasePageState extends State<ItemPurchasePage> {
//   final _formKey = GlobalKey<FormState>();
//   late DateTime _selectedDateTime;
//
//   // Controllers
//   late TextEditingController _vendorSearchController;
//
//   bool _isLoadingItems = false;
//   bool _isLoadingVendors = false;
//   List<Map<String, dynamic>> _items = [];
//   List<Map<String, dynamic>> _vendors = [];
//   Map<String, dynamic>? _selectedVendor;
//
//   // List to hold multiple purchase items
//   List<PurchaseItem> _purchaseItems = [];
//
//   // BOM related
//   List<Map<String, dynamic>> _bomComponents = [];
//   Map<String, double> _wastageRecords = {};
//
//   @override
//   void initState() {
//     super.initState();
//     _selectedDateTime = DateTime.now();
//     _vendorSearchController = TextEditingController();
//
//     if (widget.initialItems.isNotEmpty) {
//       _purchaseItems = widget.initialItems.map((item) {
//         return PurchaseItem()
//           ..itemNameController.text = item['itemName']?.toString() ?? ''
//           ..quantityController.text = (item['quantity'] as num?)?.toString() ?? '0'
//           ..priceController.text = (item['purchasePrice'] as num?)?.toString() ?? '0';
//       }).toList();
//     } else {
//       _purchaseItems = List.generate(3, (index) => PurchaseItem());
//     }
//
//     if (widget.initialVendorId != null && widget.initialVendorName != null) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (mounted) {
//           setState(() {
//             _selectedVendor = {
//               'key': widget.initialVendorId,
//               'name': widget.initialVendorName,
//             };
//             _vendorSearchController.text = widget.initialVendorName!;
//           });
//         }
//       });
//     }
//     fetchItems();
//     fetchVendors();
//   }
//
//   Future<void> fetchItems() async {
//     if (!mounted) return;
//     setState(() => _isLoadingItems = true);
//     final database = FirebaseDatabase.instance.ref();
//     try {
//       final snapshot = await database.child('items').get();
//       if (snapshot.exists && mounted) {
//         final Map<dynamic, dynamic> itemData = snapshot.value as Map<dynamic, dynamic>;
//         setState(() {
//           _items = itemData.entries.map((entry) => {
//             'key': entry.key,
//             'itemName': entry.value['itemName'] ?? '',
//             'costPrice': (entry.value['costPrice'] as num?)?.toDouble() ?? 0.0,
//             'qtyOnHand': (entry.value['qtyOnHand'] as num?)?.toDouble() ?? 0.0,
//             'isBOM': entry.value['isBOM'] ?? false,
//             'components': entry.value['components'] ?? {},
//           }).toList();
//         });
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Error fetching items: $e')),
//         );
//       }
//     } finally {
//       if (mounted) {
//         setState(() => _isLoadingItems = false);
//       }
//     }
//   }
//
//   Future<Map<String, dynamic>?> fetchBomForItem(String itemName) async {
//     final item = _items.firstWhere(
//           (item) => item['itemName'].toLowerCase() == itemName.toLowerCase(),
//       orElse: () => {},
//     );
//
//     if (item.isNotEmpty && item['isBOM'] == true) {
//       return {
//         'itemName': item['itemName'],
//         'components': item['components'],
//       };
//     }
//     return null;
//   }
//
//   Future<void> recordWastage(String itemName, double quantity, String purchaseId) async {
//     final database = FirebaseDatabase.instance.ref();
//     try {
//       await database.child('wastage').push().set({
//         'itemName': itemName,
//         'quantity': quantity,
//         'date': DateTime.now().toString(),
//         'purchaseId': purchaseId,
//         'type': 'production',
//       });
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Error recording wastage: $e')),
//         );
//       }
//     }
//   }
//
//   Future<Map<String, double>> checkBomComponentsForWastage(
//       String itemName, double purchasedQty)
//   async {
//     final bom = await fetchBomForItem(itemName);
//     Map<String, double> wastage = {};
//
//     if (bom != null && bom['components'] != null) {
//       final components = (bom['components'] as Map<dynamic, dynamic>).cast<String, dynamic>();
//
//       for (var componentEntry in components.entries) {
//         final componentName = componentEntry.key;
//         final componentQty = (componentEntry.value as num).toDouble();
//
//         // Calculate total component quantity needed
//         final totalComponentQty = componentQty * purchasedQty;
//
//         // Check current inventory
//         final componentItem = _items.firstWhere(
//               (item) => item['itemName'].toLowerCase() == componentName.toLowerCase(),
//           orElse: () => {},
//         );
//
//         if (componentItem.isNotEmpty) {
//           final currentQty = componentItem['qtyOnHand']?.toDouble() ?? 0.0;
//           if (currentQty < totalComponentQty) {
//             // Calculate wastage (negative quantity)
//             final wastageQty = totalComponentQty - currentQty;
//             wastage[componentName] = wastageQty;
//           }
//         }
//       }
//     }
//
//     return wastage;
//   }
//
//   Future<void> savePurchase() async {
//     if (!mounted) return;
//
//     final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
//
//     if (_formKey.currentState!.validate()) {
//       if (_selectedVendor == null) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//               content: Text(languageProvider.isEnglish
//                   ? 'Please select a vendor'
//                   : 'براہ کرم فروش منتخب کریں')),
//         );
//         return;
//       }
//
//       // Get only items that have been filled
//       List<PurchaseItem> validItems = _purchaseItems.where((item) =>
//       item.itemNameController.text.isNotEmpty &&
//           item.quantityController.text.isNotEmpty &&
//           item.priceController.text.isNotEmpty
//       ).toList();
//
//       if (validItems.isEmpty) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//               content: Text(languageProvider.isEnglish
//                   ? 'Please add at least one item'
//                   : 'براہ کرم کم از کم ایک آئٹم شامل کریں')),
//         );
//         return;
//       }
//
//       try {
//         final database = FirebaseDatabase.instance.ref();
//         String vendorKey = _selectedVendor!['key'];
//         _wastageRecords.clear();
//
//         // Process each valid item
//         for (var purchaseItem in validItems) {
//           String itemName = purchaseItem.itemNameController.text;
//           double purchasedQty = double.tryParse(purchaseItem.quantityController.text) ?? 0.0;
//           double purchasePrice = double.tryParse(purchaseItem.priceController.text) ?? 0.0;
//
//           // Check if this is a BOM item and calculate wastage
//           final wastage = await checkBomComponentsForWastage(itemName, purchasedQty);
//           if (wastage.isNotEmpty) {
//             _wastageRecords.addAll(wastage);
//           }
//
//           // Check if this is an existing item
//           var existingItem = _items.firstWhere(
//                 (item) => item['itemName'].toLowerCase() == itemName.toLowerCase(),
//             orElse: () => {},
//           );
//
//           if (existingItem.isNotEmpty) {
//             // Existing item - update quantity and price
//             String itemKey = existingItem['key'];
//             double currentQty = existingItem['qtyOnHand']?.toDouble() ?? 0.0;
//
//             await database.child('items').child(itemKey).update({
//               'qtyOnHand': currentQty + purchasedQty,
//               'costPrice': purchasePrice,
//             });
//           }
//         }
//
//         // Create a single purchase record with all valid items
//         final newPurchase = {
//           'items': validItems.map((item) => {
//             'itemName': item.itemNameController.text,
//             'quantity': double.tryParse(item.quantityController.text) ?? 0.0,
//             'purchasePrice': double.tryParse(item.priceController.text) ?? 0.0,
//             'total': (double.tryParse(item.quantityController.text) ?? 0.0) *
//                 (double.tryParse(item.priceController.text) ?? 0.0),
//           }).toList(),
//           'vendorId': vendorKey,
//           'vendorName': _selectedVendor!['name'],
//           'grandTotal': calculateTotal(),
//           'timestamp': _selectedDateTime.toString(),
//           'type': 'credit',
//           'hasBOM': validItems.any((item) =>
//               _items.any((i) =>
//               i['itemName'].toLowerCase() == item.itemNameController.text.toLowerCase() &&
//                   i['isBOM'] == true
//               )
//           ),
//         };
//
//         // Save the purchase and get the key
//         final purchaseRef = database.child('purchases').push();
//         await purchaseRef.set(newPurchase);
//         final purchaseId = purchaseRef.key;
//
//         // Record any wastage found
//         if (_wastageRecords.isNotEmpty && purchaseId != null) {
//           for (var entry in _wastageRecords.entries) {
//             await recordWastage(entry.key, entry.value, purchaseId);
//           }
//
//           if (mounted) {
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: Text(
//                     languageProvider.isEnglish
//                         ? 'Wastage recorded for components: ${_wastageRecords.keys.join(', ')}'
//                         : 'اجزاء کے لیے ضائع شدہ مقدار درج کی گئی: ${_wastageRecords.keys.join(', ')}'),
//               ),
//             );
//           }
//         }
//
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//                 content: Text(languageProvider.isEnglish
//                     ? 'Purchase recorded successfully!'
//                     : 'خریداری کامیابی سے ریکارڈ ہو گئی!')),
//           );
//
//           // Clear form after successful save
//           _clearForm();
//         }
//       } catch (error) {
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//                 content: Text(languageProvider.isEnglish
//                     ? 'Failed to record purchase: $error'
//                     : 'خریداری ریکارڈ کرنے میں ناکامی: $error')),
//           );
//         }
//       }
//     }
//   }
//
// // ... [keep all other existing methods unchanged] ...
// }
//
// class PurchaseItem {
//   late TextEditingController itemNameController;
//   late TextEditingController quantityController;
//   late TextEditingController priceController;
//   Map<String, dynamic>? selectedItem;
//
//   PurchaseItem() {
//     itemNameController = TextEditingController();
//     quantityController = TextEditingController();
//     priceController = TextEditingController();
//     selectedItem = null;
//   }
//
//   void dispose() {
//     itemNameController.dispose();
//     quantityController.dispose();
//     priceController.dispose();
//   }
// }