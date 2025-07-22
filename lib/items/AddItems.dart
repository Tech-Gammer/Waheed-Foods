import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import '../Provider/lanprovider.dart';

class RegisterItemPage extends StatefulWidget {
  final Map<String, dynamic>? itemData;

  RegisterItemPage({this.itemData});

  @override
  _RegisterItemPageState createState() => _RegisterItemPageState();
}

class _RegisterItemPageState extends State<RegisterItemPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _itemNameController;
  late TextEditingController _costPriceController;
  late TextEditingController _salePriceController;
  late TextEditingController _qtyOnHandController;
  final TextEditingController _vendorsearchController = TextEditingController();
  final TextEditingController _unitSearchController = TextEditingController();
  final TextEditingController _categorySearchController = TextEditingController();
  final TextEditingController _customerSearchController = TextEditingController();
  late TextEditingController _weightPerBagController;

  String? _selectedUnit;
  String? _selectedVendor;
  String? _selectedCategory;

  List<String> _units = ['Kg','Pcs'];
  List<String> _vendors = [];
  List<String> _categories = [];
  List<Map<String, dynamic>> _customers = [];
  bool _isLoadingVendors = false;
  bool _isLoadingCustomers = false;
  List<String> _filteredVendors = [];
  List<String> _filteredCategories = [];
  List<Map<String, dynamic>> _filteredCustomers = [];

  // Customer base prices
  Map<String, double> _customerBasePrices = {};
  List<Map<String, dynamic>> _customerPricesList = [];

  @override
  void initState() {
    super.initState();
    _itemNameController = TextEditingController(text: widget.itemData?['itemName'] ?? '');
    _costPriceController = TextEditingController(text: widget.itemData?['costPrice']?.toString() ?? '');
    _salePriceController = TextEditingController(text: widget.itemData?['salePrice']?.toString() ?? '');
    _qtyOnHandController = TextEditingController(text: widget.itemData?['qtyOnHand']?.toString() ?? '');
     _weightPerBagController = TextEditingController(text: widget.itemData?['weightPerBag']?.toString() ?? '');


    _selectedUnit = widget.itemData?['unit'];
    _selectedVendor = widget.itemData?['vendor'];
    _selectedCategory = widget.itemData?['category'];

    // Initialize customer prices - modified to handle the case when customerBasePrices is null
    if (widget.itemData != null) {
      final prices = widget.itemData!['customerBasePrices'];
      if (prices != null) {
        _customerBasePrices = Map<String, double>.from(prices.map(
              (key, value) => MapEntry(key.toString(), value.toDouble()),
        ));
      }
    }

    // Listeners
    _vendorsearchController.addListener(() => _filterVendors(_vendorsearchController.text));
    _categorySearchController.addListener(() => _filterCategories(_categorySearchController.text));
    _customerSearchController.addListener(() => _filterCustomers(_customerSearchController.text));

    fetchDropdownData();
  }

  Future<void> _fetchCustomers() async {
    setState(() => _isLoadingCustomers = true);

    try {
      final DatabaseReference database = FirebaseDatabase.instance.ref();
      final snapshot = await database.child('customers').get();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> customerData = snapshot.value as Map<dynamic, dynamic>;

        setState(() {
          _customers = customerData.entries.map((entry) => {
            'id': entry.key,
            'name': entry.value['name'] as String,
            'phone': entry.value['phone'] ?? '',
            'email': entry.value['email'] ?? '',
          }).toList();
          _filteredCustomers = List.from(_customers);
        });

        // FIXED: Update prices list AFTER customers are loaded
        _updateCustomerPricesList();
      }
    } catch (e) {
      print('Error fetching customers: $e');
    } finally {
      setState(() => _isLoadingCustomers = false);
    }
  }

  void _filterVendors(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredVendors = List.from(_vendors);
      } else {
        _filteredVendors = _vendors
            .where((vendor) => vendor.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _filterCategories(String query) {
    setState(() {
      _filteredCategories = query.isEmpty
          ? List.from(_categories)
          : _categories.where((category) => category.toLowerCase().contains(query.toLowerCase())).toList();
    });
  }

  void _filterCustomers(String query) {
    setState(() {
      _filteredCustomers = query.isEmpty
          ? List.from(_customers)
          : _customers.where((customer) =>
          customer['name'].toLowerCase().contains(query.toLowerCase())).toList();
    });
  }

  void _updateCustomerPricesList() {
    if (_customerBasePrices.isEmpty) return;

    setState(() {
      _customerPricesList = _customerBasePrices.entries.map((entry) {
        String customerId = entry.key;
        double price = entry.value;

        String customerName = _customers.firstWhere(
              (c) => c['id'] == customerId,
          orElse: () => {'name': 'Unknown Customer'},
        )['name'];

        return {
          'customerId': customerId,
          'customerName': customerName,
          'price': price,
        };
      }).toList();
    });
  }

  Future<void> fetchDropdownData() async {
    final DatabaseReference database = FirebaseDatabase.instance.ref();

    // Fetch units
    database.child('units').onValue.listen((event) {
      final Map? data = event.snapshot.value as Map?;
      if (data != null) {
        setState(() {
          _units = data.values
              .map<String>((value) => (value as Map)['name']?.toString() ?? '')
              .toList();
        });
      }
    });

    // Fetch vendors
    setState(() {
      _isLoadingVendors = true;
    });

    try {
      final snapshot = await database.child('vendors').get();
      if (snapshot.exists) {
        final Map<dynamic, dynamic> vendorData = snapshot.value as Map<dynamic, dynamic>;

        setState(() {
          _vendors = vendorData.entries.map((entry) => entry.value['name'] as String).toList();
          _filteredVendors = List.from(_vendors);
        });
      }
    } catch (e) {
      print('Error fetching vendors: $e');
    } finally {
      setState(() {
        _isLoadingVendors = false;
      });
    }

    // Fetch categories
    database.child('category').onValue.listen((event) {
      final Map? data = event.snapshot.value as Map?;
      if (data != null) {
        setState(() {
          _categories = data.values
              .map<String>((value) => (value as Map)['name']?.toString() ?? '')
              .toList();
          _filteredCategories = List.from(_categories);
        });
      }
    });

    // FIXED: Fetch customers and wait for completion
    await _fetchCustomers();
  }

  void _addCustomerPrice(String customerId, String customerName, double price) {
    setState(() {
      _customerBasePrices[customerId] = price;
      _customerSearchController.clear();
      _filteredCustomers = List.from(_customers);
    });

    // Update the list only if customers are already loaded
    if (_customers.isNotEmpty) {
      _updateCustomerPricesList();
    } else {
      // fallback in case customers not loaded yet
      setState(() {
        _customerPricesList.add({
          'customerId': customerId,
          'customerName': customerName,
          'price': price,
        });
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Price added for $customerName: \$${price.toStringAsFixed(2)}')),
    );
  }

  void _removeCustomerPrice(String customerId) {
    setState(() {
      _customerBasePrices.remove(customerId);
    });

    // FIXED: Update the list immediately after removing
    _updateCustomerPricesList();
  }

  void _showAddCustomerPriceDialog(String customerId, String customerName) {
    TextEditingController priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final languageProvider = Provider.of<LanguageProvider>(context);
        return AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Set Price for $customerName' : '$customerName کے لیے قیمت مقرر کریں'),
          content: TextFormField(
            controller: priceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: languageProvider.isEnglish ? 'Price' : 'قیمت',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
            ),
            TextButton(
              onPressed: () {
                double? price = double.tryParse(priceController.text);
                if (price != null && price > 0) {
                  _addCustomerPrice(customerId, customerName, price);
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(languageProvider.isEnglish ? 'Please enter a valid price' : 'براہ کرم ایک درست قیمت درج کریں')),
                  );
                }
              },
              child: Text(languageProvider.isEnglish ? 'Add' : 'شامل کریں'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> checkIfItemExists(String itemName) async {
    final DatabaseReference database = FirebaseDatabase.instance.ref();
    final snapshot = await database.child('items').get();

    if (snapshot.exists && snapshot.value is Map) {
      Map<dynamic, dynamic> items = snapshot.value as Map<dynamic, dynamic>;

      for (var key in items.keys) {
        if (items[key]['itemName'].toString().toLowerCase() == itemName.toLowerCase()) {
          return true;
        }
      }
    }
    return false;
  }

  void _clearFormFields() {
    setState(() {
      _itemNameController.clear();
      _costPriceController.clear();
      _salePriceController.clear();
      _qtyOnHandController.clear();
      _weightPerBagController.clear();
      _selectedUnit = null;
      _selectedVendor = null;
      _selectedCategory = null;
      _customerBasePrices.clear();
      _customerPricesList.clear();
    });
  }

  void saveOrUpdateItem() async {
    if (_formKey.currentState!.validate()) {
      final itemName = _itemNameController.text;

      if (widget.itemData == null) {
        bool itemExists = await checkIfItemExists(itemName);
        if (itemExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Item with this name already exists!')),
          );
          return;
        }
      }

      final DatabaseReference database = FirebaseDatabase.instance.ref();
      final double weightPerBag = double.tryParse(_weightPerBagController.text) ?? 1;
      final double pricePerBag = double.tryParse(_salePriceController.text) ?? 0.0;
      final double pricePerKg = pricePerBag / weightPerBag;


      final newItem = {
        'itemName': itemName,
        'unit': _selectedUnit,
        'costPrice': double.tryParse(_costPriceController.text) ?? 0.0,
        'salePrice': pricePerBag,
        'pricePerKg': pricePerKg,
        'weightPerBag': weightPerBag,
        'qtyOnHand': int.tryParse(_qtyOnHandController.text) ?? 0,
        'vendor': _selectedVendor,
        'category': _selectedCategory,
        'customerBasePrices': _customerBasePrices, // This ensures customer prices are saved
      };


      if (widget.itemData == null) {
        database.child('items').push().set(newItem).then((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Item registered successfully!')),
          );
          _clearFormFields();
        }).catchError((error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to register item: $error')),
          );
        });
      } else {
        database.child('items/${widget.itemData!['key']}').set(newItem).then((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Item updated successfully!')),
          );
        }).catchError((error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update item: $error')),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.isEnglish ? 'Register Item' : 'آئٹم ایڈ کریں',
          style: TextStyle(color: Colors.white),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  TextFormField(
                    controller: _itemNameController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish ? 'Item Name' : 'آئٹم کا نام',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return languageProvider.isEnglish ? 'Please enter the item name' : 'براہ کرم آئٹم کا نام درج کریں۔';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedUnit,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish ? 'Unit' : 'یونٹ',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    items: _units.map((unit) {
                      return DropdownMenuItem(
                        value: unit,
                        child: Text(unit),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedUnit = value;
                      });
                    },
                    validator: (value) => value == null ?
                    languageProvider.isEnglish ? 'Please select a unit' : 'براہ کرم ایک یونٹ منتخب کریں۔'
                        : null,
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _costPriceController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish ? 'Cost Price' : 'لاگت کی قیمت',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _salePriceController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish ? 'Sale Price' : 'فروخت کی قیمت',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _weightPerBagController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish ? 'Weight per Bag (kg)' : 'فی بیگ وزن (کلوگرام)',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return languageProvider.isEnglish ? 'Enter weight per bag' : 'فی بیگ وزن درج کریں';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),
                  Text(
                    languageProvider.isEnglish
                        ? 'Per KG Price: ${(double.tryParse(_salePriceController.text) ?? 0) / (double.tryParse(_weightPerBagController.text) ?? 1)} PKR'
                        : 'فی کلو قیمت: ${(double.tryParse(_salePriceController.text) ?? 0) / (double.tryParse(_weightPerBagController.text) ?? 1)} روپے',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.orange[300],
                    ),
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _qtyOnHandController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish ? 'Quantity on Hand' : 'موجود مقدار',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    readOnly: widget.itemData != null,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return languageProvider.isEnglish ? 'Please enter the quantity on hand' : 'براہ کرم ہاتھ میں مقدار درج کریں۔';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Vendor Selection
                  if (_isLoadingVendors)
                    const Center(child: CircularProgressIndicator())
                  else if (_vendors.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          languageProvider.isEnglish ? 'Search Vendor' : 'وینڈر تلاش کریں',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _vendorsearchController,
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Type to search vendors...' : 'وینڈرز کو تلاش کرنے کے لیے ٹائپ کریں...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_vendorsearchController.text.isNotEmpty)
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              itemCount: _filteredVendors.length,
                              itemBuilder: (context, index) {
                                final vendor = _filteredVendors[index];
                                return ListTile(
                                  title: Text(vendor),
                                  onTap: () {
                                    setState(() {
                                      _selectedVendor = vendor;
                                      _vendorsearchController.clear();
                                      _filteredVendors = List.from(_vendors);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(
                                          '${languageProvider.isEnglish ? 'Selected Vendor: ' : 'منتخب فروش: '}$vendor')),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 20),
                        if (_selectedVendor != null)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: Row(
                              children: [
                                 Icon(Icons.check_circle, color: Colors.orange[300]),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${languageProvider.isEnglish ? 'Selected Vendor: ' : 'منتخب فروش: '}$_selectedVendor',
                                    style:  TextStyle(
                                      fontSize: 16,
                                      color: Colors.orange[300],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                  SizedBox(height: 20),

                  // Customer Base Prices Section
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            languageProvider.isEnglish ? 'Customer Base Prices' : 'کسٹمر کی بنیادی قیمتیں',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Customer Search
                          if (_isLoadingCustomers)
                            const Center(child: CircularProgressIndicator())
                          else if (_customers.isNotEmpty)
                            Column(
                              children: [
                                TextField(
                                  controller: _customerSearchController,
                                  decoration: InputDecoration(
                                    hintText: languageProvider.isEnglish ? 'Search customers...' : 'کسٹمرز تلاش کریں...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    prefixIcon: const Icon(Icons.search),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (_customerSearchController.text.isNotEmpty)
                                  Container(
                                    height: 150,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListView.builder(
                                      itemCount: _filteredCustomers.length,
                                      itemBuilder: (context, index) {
                                        final customer = _filteredCustomers[index];
                                        final isAlreadyAdded = _customerBasePrices.containsKey(customer['id']);

                                        return ListTile(
                                          title: Text(customer['name']),
                                          subtitle: Text(customer['phone'] ?? ''),
                                          trailing: isAlreadyAdded
                                              ? Icon(Icons.check, color: Colors.green)
                                              : Icon(Icons.add, color: Colors.orange[300]),
                                          onTap: isAlreadyAdded
                                              ? null
                                              : () => _showAddCustomerPriceDialog(
                                              customer['id'],
                                              customer['name']
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),

                          const SizedBox(height: 20),

                          // FIXED: Display added customer prices with better conditions
                          if (_customerPricesList.isNotEmpty) ...[
                            Text(
                              languageProvider.isEnglish ? 'Added Customer Prices:' : 'شامل کردہ کسٹمر کی قیمتیں:',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: _customerPricesList.length,
                              itemBuilder: (context, index) {
                                final customerPrice = _customerPricesList[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text(customerPrice['customerName']),
                                    subtitle: Text('${languageProvider.isEnglish ? 'Price: ' : 'قیمت: '}${customerPrice['price'].toStringAsFixed(2)}rs'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _removeCustomerPrice(customerPrice['customerId']),
                                    ),
                                  ),
                                );//s
                              },
                            ),
                          ] else if (_customerBasePrices.isNotEmpty && _customers.isEmpty)
                          // FIXED: Show loading or fallback message when customers are still loading
                            Center(
                              child: Text(
                                languageProvider.isEnglish ? 'Loading customer information...' : 'کسٹمر کی معلومات لوڈ ہو رہی ہیں...',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: saveOrUpdateItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      languageProvider.isEnglish ? 'Register Item' : 'آئٹم ایڈ کریں',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _costPriceController.dispose();
    _salePriceController.dispose();
    _qtyOnHandController.dispose();
    _weightPerBagController.dispose();
    _vendorsearchController.dispose();
    _unitSearchController.dispose();
    _categorySearchController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

}