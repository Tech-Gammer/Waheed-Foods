import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:waheed_foods/items/productionpage.dart';
import '../Provider/lanprovider.dart';

class ItemPurchasePage extends StatefulWidget {
  @override
  _ItemPurchasePageState createState() => _ItemPurchasePageState();
}

class _ItemPurchasePageState extends State<ItemPurchasePage> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDateTime;

  // Controllers
  late TextEditingController _quantityController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _itemSearchController;
  late TextEditingController _vendorSearchController;

  bool _isLoadingItems = false;
  bool _isLoadingVendors = false;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _vendors = [];
  Map<String, dynamic>? _selectedItem;
  Map<String, dynamic>? _selectedVendor;

  @override
  void initState() {
    super.initState();
    _selectedDateTime = DateTime.now();
    _quantityController = TextEditingController();
    _purchasePriceController = TextEditingController();
    _itemSearchController = TextEditingController();
    _vendorSearchController = TextEditingController();
    fetchItems();
    fetchVendors();

    // Add listeners to update total when values change
    _quantityController.addListener(() => setState(() {}));
    _purchasePriceController.addListener(() => setState(() {}));
  }

  Future<void> fetchItems() async {
    setState(() => _isLoadingItems = true);
    final database = FirebaseDatabase.instance.ref();
    try {
      final snapshot = await database.child('items').get();
      if (snapshot.exists) {
        final Map<dynamic, dynamic> itemData = snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _items = itemData.entries.map((entry) => {
            'key': entry.key,
            'itemName': entry.value['itemName'],
            'costPrice': (entry.value['costPrice'] as num?)?.toDouble() ?? 0.0,
            'qtyOnHand': (entry.value['qtyOnHand'] as num?)?.toInt() ?? 0,
          }).toList();
        });
      }
    } finally {
      setState(() => _isLoadingItems = false);
    }
  }

  Future<void> fetchVendors() async {
    setState(() => _isLoadingVendors = true);
    final database = FirebaseDatabase.instance.ref();
    try {
      final snapshot = await database.child('vendors').get();
      if (snapshot.exists) {
        final Map<dynamic, dynamic> vendorData = snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _vendors = vendorData.entries.map((entry) => {
            'key': entry.key,
            'name': entry.value['name'], // Use "name" from vendors node
          }).toList();
        });
      }
    } finally {
      setState(() => _isLoadingVendors = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDateTime) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void savePurchase() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    if (_formKey.currentState!.validate()) {
      // Debug prints to check values
      print('=== DEBUG PURCHASE NAVIGATION ===');
      print('_selectedItem: $_selectedItem');
      print('_selectedVendor: $_selectedVendor');
      print('purchasedQty: ${_quantityController.text}');
      print('purchasePrice: ${_purchasePriceController.text}');

      if (_selectedItem == null || _selectedVendor == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Please select an item and vendor'
                  : 'براہ کرم ایک آئٹم اور فروش منتخب کریں')),
        );
        return;
      }

      final database = FirebaseDatabase.instance.ref();
      String itemKey = _selectedItem!['key'];
      String vendorKey = _selectedVendor!['key'];

      // Additional validation
      if (itemKey.isEmpty || vendorKey.isEmpty) {
        print('Error: Empty keys - itemKey: $itemKey, vendorKey: $vendorKey');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid item or vendor selection')),
        );
        return;
      }

      final snapshot = await database.child('items').child(itemKey).get();
      if (!snapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Item not found'
                  : 'آئٹم نہیں ملا')),
        );
        return;
      }

      double purchasedQty = double.tryParse(_quantityController.text) ?? 0.0;
      double purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0.0;
      double total = purchasedQty * purchasePrice;
      double currentQty = (snapshot.value as Map)['qtyOnHand']?.toDouble() ?? 0.0;

      // Validate quantities
      if (purchasedQty <= 0 || purchasePrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter valid quantity and price')),
        );
        return;
      }

      await database.child('items').child(itemKey).update({
        'qtyOnHand': currentQty + purchasedQty,
        'costPrice': purchasePrice,
      });

      final newPurchase = {
        'itemName': _selectedItem!['itemName'],
        'vendorId': vendorKey,
        'vendorName': _selectedVendor!['name'],
        'quantity': purchasedQty,
        'purchasePrice': purchasePrice,
        'total': total,
        'timestamp': _selectedDateTime.toString(),
        'type': 'credit',
      };

      database.child('purchases').push().set(newPurchase).then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Purchase recorded successfully!'
                  : 'خریداری کامیابی سے ریکارڈ ہو گئی!')),
        );

        // ✅ Enhanced Navigation with comprehensive null checks
        print('=== PREPARING NAVIGATION DATA ===');

        // Create a safe copy of selected item data
        final safeSelectedItem = Map<String, dynamic>.from(_selectedItem!);
        final safeSelectedVendor = Map<String, dynamic>.from(_selectedVendor!);

        print('safeSelectedItem: $safeSelectedItem');
        print('safeSelectedVendor: $safeSelectedVendor');

        if (safeSelectedItem.isNotEmpty && purchasedQty > 0) {
          try {
            final inputItemData = {
              // Core item fields with safe access
              'key': safeSelectedItem['key']?.toString() ?? '',
              'itemName': safeSelectedItem['itemName']?.toString() ?? 'Unknown Item',
              'usedQty': purchasedQty,
              'costPrice': purchasePrice,
              'qtyOnHand': (safeSelectedItem['qtyOnHand'] as num?)?.toDouble() ?? 0.0,

              // Purchase-related fields
              'purchasePrice': purchasePrice,
              'quantity': purchasedQty,
              'total': total,
              'vendorId': safeSelectedVendor['key']?.toString() ?? '',
              'vendorName': safeSelectedVendor['name']?.toString() ?? 'Unknown Vendor',

              // DateTime fields
              'timestamp': _selectedDateTime.toString(),
              'dateTime': _selectedDateTime.millisecondsSinceEpoch, // Store as timestamp
              'formattedDateTime': DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime),
              'purchaseDate': DateFormat('yyyy-MM-dd').format(_selectedDateTime),
              'purchaseTime': DateFormat('HH:mm').format(_selectedDateTime),

              // Additional utility fields
              'currentQtyAfterPurchase': currentQty + purchasedQty,
              'unitPrice': purchasePrice,
              'totalAmount': total,
              'currency': 'PKR',
              'type': 'credit',
              'isProduction': true,
              'source': 'purchase',
            };

            print('=== FINAL INPUT ITEM DATA ===');
            print('inputItemData: $inputItemData');

            // Validate required fields before navigation
            if (inputItemData['key'].toString().isEmpty) {
              throw Exception('Item key is empty');
            }
            if (inputItemData['itemName'].toString().isEmpty) {
              throw Exception('Item name is empty');
            }
            final usedQty = inputItemData['usedQty'];
            if (usedQty is! num || usedQty <= 0) {
              throw Exception('Used quantity is invalid');
            }


            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductionPage(
                  inputItem: inputItemData,
                ),
              ),
            );

          } catch (e) {
            print('Error during navigation: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error navigating to production page: $e')),
            );
          }
        } else {
          print('Navigation conditions not met - selectedItem empty or quantity <= 0');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot navigate to production page - invalid data')),
          );
        }

        // Clear form fields
        _quantityController.clear();
        _purchasePriceController.clear();
        _itemSearchController.clear();
        _vendorSearchController.clear();
        setState(() {
          _selectedItem = null;
          _selectedVendor = null;
        });
      }).catchError((error) {
        print('Error saving purchase: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Failed to record purchase: $error'
                  : 'خریداری ریکارڈ کرنے میں ناکامی: $error')),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final quantity = double.tryParse(_quantityController.text) ?? 0.0;
    final price = double.tryParse(_purchasePriceController.text) ?? 0.0;
    final total = quantity * price;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.isEnglish ? 'Purchase Item' : 'آئٹم خریداری',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF3E0), // Light orange
              Color(0xFFFFE0B2), // Lighter orange
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // Search Item Field
                Text(
                  languageProvider.isEnglish ? 'Search Item' : 'آئٹم تلاش کریں',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100), // Dark orange
                  ),
                ),
                const SizedBox(height: 8),
                Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) return const Iterable.empty();
                    return _items.where((item) =>
                        item['itemName'].toLowerCase().contains(textEditingValue.text.toLowerCase()));
                  },
                  displayStringForOption: (item) => item['itemName'],
                  onSelected: (item) {
                    print('=== ITEM SELECTED ===');
                    print('Selected item: $item');
                    setState(() {
                      _selectedItem = Map<String, dynamic>.from(item); // Create a copy
                      _purchasePriceController.text = item['costPrice'].toStringAsFixed(2);
                    });
                    print('_selectedItem after setState: $_selectedItem');
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                    _itemSearchController = controller;
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Search Item' : 'آئٹم تلاش کریں',
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFF8A65)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFF8A65)),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Search Vendor Field
                Text(
                  languageProvider.isEnglish ? 'Search Vendor' : 'وینڈر تلاش کریں',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100), // Dark orange
                  ),
                ),
                const SizedBox(height: 8),
                Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) return const Iterable.empty();
                    return _vendors.where((vendor) =>
                        vendor['name'].toLowerCase().contains(textEditingValue.text.toLowerCase()));
                  },
                  displayStringForOption: (vendor) => vendor['name'],
                  onSelected: (vendor) {
                    print('=== VENDOR SELECTED ===');
                    print('Selected vendor: $vendor');
                    setState(() {
                      _selectedVendor = Map<String, dynamic>.from(vendor); // Create a copy
                    });
                    print('_selectedVendor after setState: $_selectedVendor');
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                    _vendorSearchController = controller;
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Search Vendor' : 'وینڈر تلاش کریں',
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFF8A65)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFF8A65)),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: languageProvider.isEnglish ? 'Quantity' : 'مقدار',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF8A65)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF8A65)),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                  value == null || value.isEmpty ?
                  languageProvider.isEnglish ? 'Please enter the quantity' : 'براہ کرم مقدار درج کریں'
                      : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _purchasePriceController,
                  decoration: InputDecoration(
                    labelText: languageProvider.isEnglish ? 'Purchase Price' : 'خریداری کی قیمت',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF8A65)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF8A65)),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                  value == null || value.isEmpty ?
                  languageProvider.isEnglish ? 'Please enter the purchase price' : 'براہ کرم خریداری کی قیمت درج کریں'
                      : null,
                ),
                const SizedBox(height: 16),

                // Date and Time Picker
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.calendar_today, size: 18, color: Colors.white),
                        label: Text(
                          languageProvider.isEnglish ? 'Select Date' : 'تاریخ منتخب کریں',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: () => _selectDate(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF8A65),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.access_time, size: 18, color: Colors.white),
                        label: Text(
                          languageProvider.isEnglish ? 'Select Time' : 'وقت منتخب کریں',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: () => _selectTime(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF8A65),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  languageProvider.isEnglish
                      ? 'Selected: ${DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime)}'
                      : 'منتخب شدہ: ${DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFE65100), // Dark orange
                  ),
                ),
                SizedBox(height: 16),

                // Total Display
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Color(0xFFFF8A65)),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        languageProvider.isEnglish ? 'Total:' : 'کل:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE65100), // Dark orange
                        ),
                      ),
                      Text(
                        '${total.toStringAsFixed(2)} PKR',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE65100), // Dark orange
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: savePurchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF8A65),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    languageProvider.isEnglish ? 'Record Purchase' : 'خریداری ریکارڈ کریں',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
