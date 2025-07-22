import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PurchaseOrderPage extends StatefulWidget {
  @override
  _PurchaseOrderPageState createState() => _PurchaseOrderPageState();
}

class _PurchaseOrderPageState extends State<PurchaseOrderPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _poNumberController = TextEditingController();
  final TextEditingController _deliveryDateController = TextEditingController();
  final TextEditingController _termsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _taxController = TextEditingController(text: '0');
  final TextEditingController _discountController = TextEditingController(text: '0');

  DateTime _selectedDate = DateTime.now().add(Duration(days: 7));
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _selectedItems = [];
  double _subtotal = 0.0;
  double _tax = 0.0;
  double _total = 0.0;
  String? _selectedVendorId;
  List<Map<String, dynamic>> _vendors = [];
  bool _taxInPercentage = false;
  bool _discountInPercentage = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _poNumberController.text = 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    // Add listeners to tax and discount controllers
    _taxController.addListener(_calculateTotals);
    _discountController.addListener(_calculateTotals);

    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      // Fetch vendors
      final vendorsSnapshot = await FirebaseDatabase.instance.ref('vendors').get();
      if (vendorsSnapshot.exists) {
        final vendorsData = vendorsSnapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _vendors = vendorsData.entries.map((entry) {
            return {
              'id': entry.key,
              'name': entry.value['name'] ?? 'Unknown Vendor',
            };
          }).toList();
        });
      }

      // Fetch items
      final itemsSnapshot = await FirebaseDatabase.instance.ref('items').get();
      if (itemsSnapshot.exists) {
        final itemsData = itemsSnapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _items = itemsData.entries.map((entry) {
            final item = entry.value;
            return {
              'id': entry.key,
              'name': item['itemName'] ?? 'No Name',
              'unit': item['unit'] ?? 'unit',
              'price': (item['salePrice'] ?? 0).toDouble(),
              'category': item['category'] ?? 'Uncategorized',
              'weightPerBag': item['weightPerBag']?.toDouble() ?? 0.0,
              'isBOW': item['isBOW'] ?? false,
              'image': item['image'] ?? '', // Add this line to get the image URL

            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      setState(() {
        _items = [];
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _deliveryDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _addItem(Map<String, dynamic> item) {
    setState(() {
      _selectedItems.add({
        ...item,
        'quantity': 1,
        'total': item['price'],
      });
      _calculateTotals();
    });
  }

  void _updateQuantity(int index, int quantity) {
    if (quantity > 0) {
      setState(() {
        _selectedItems[index]['quantity'] = quantity;
        _selectedItems[index]['total'] = quantity * _selectedItems[index]['price'];
        _calculateTotals();
      });
    }
  }

  void _removeItem(int index) {
    setState(() {
      _selectedItems.removeAt(index);
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    // Calculate subtotal
    _subtotal = _selectedItems.fold(0.0, (sum, item) => sum + item['total']);

    // Parse tax and discount values
    final taxValue = double.tryParse(_taxController.text) ?? 0;
    final discountValue = double.tryParse(_discountController.text) ?? 0;

    // Calculate tax based on mode
    _tax = _taxInPercentage ? (_subtotal * taxValue / 100) : taxValue;

    // Calculate discount based on mode
    final discount = _discountInPercentage
        ? (_subtotal * discountValue / 100)
        : discountValue;

    // Calculate final total
    _total = _subtotal + _tax - discount;
  }

  Future<void> _savePurchaseOrder() async {
    if (_formKey.currentState!.validate() && _selectedItems.isNotEmpty) {
      setState(() => _isSaving = true);
      try {
        final databaseRef = FirebaseDatabase.instance.ref();
        final poRef = databaseRef.child('purchases').push();

        final purchaseData = {
          'poNumber': _poNumberController.text,
          'vendorId': _selectedVendorId,
          'vendorName': _vendors.firstWhere(
                (v) => v['id'] == _selectedVendorId,
            orElse: () => {'name': 'Unknown'},
          )['name'],
          'deliveryDate': _deliveryDateController.text,
          'terms': _termsController.text,
          'notes': _notesController.text,
          'subtotal': _subtotal,
          'tax': _tax,
          'taxMode': _taxInPercentage ? 'percentage' : 'fixed',
          'taxValue': double.tryParse(_taxController.text) ?? 0,
          'discount': _discountInPercentage
              ? (_subtotal * (double.tryParse(_discountController.text) ?? 0) / 100)
              : (double.tryParse(_discountController.text) ?? 0),
          'discountMode': _discountInPercentage ? 'percentage' : 'fixed',
          'discountValue': double.tryParse(_discountController.text) ?? 0,
          'total': _total,
          'status': 'pending',
          'createdAt': ServerValue.timestamp,
          'items': _selectedItems.map((item) {
            return {
              'itemId': item['id'],
              'name': item['name'],
              'quantity': item['quantity'],
              'price': item['price'],
              'total': item['total'],
              'unit': item['unit'],
            };
          }).toList(),
        };

        await poRef.set(purchaseData);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase order saved successfully!')),
        );

        _clearForm();

      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving purchase order: $e')),
        );
      } finally {
        setState(() => _isSaving = false);
      }
    } else if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please add at least one item')),
      );
    }
  }

  void _clearForm() {
    setState(() {
      _selectedItems.clear();
      _subtotal = 0.0;
      _tax = 0.0;
      _total = 0.0;
      _taxController.text = '0';
      _discountController.text = '0';
      _taxInPercentage = false;
      _discountInPercentage = false;
      _termsController.clear();
      _notesController.clear();
      _deliveryDateController.clear();
      _selectedDate = DateTime.now().add(Duration(days: 7));
      _poNumberController.text = 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Create Purchase Order',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Material(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.print_outlined, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderSection(),
              const SizedBox(height: 24),
              _buildVendorSection(),
              const SizedBox(height: 24),
              _buildItemsSection(),
              const SizedBox(height: 24),
              if (_selectedItems.isNotEmpty) _buildSelectedItemsSection(),
              const SizedBox(height: 24),
              if (_selectedItems.isNotEmpty) _buildTotalsSection(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSaveButton(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.orange[50]!, Colors.amber[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.orange[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  'Purchase Order Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _poNumberController,
                    label: 'PO Number',
                    icon: Icons.tag,
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _deliveryDateController,
                    label: 'Delivery Date',
                    icon: Icons.calendar_today,
                    readOnly: true,
                    onTap: () => _selectDate(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business, color: Colors.blue[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  'Vendor Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedVendorId,
              decoration: InputDecoration(
                labelText: 'Select Vendor',
                prefixIcon: Icon(Icons.search, color: Colors.blue[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              items: _vendors.map((vendor) {
                return DropdownMenuItem<String>(
                  value: vendor['id'],
                  child: Text(vendor['name']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedVendorId = value;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a vendor';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _termsController,
              label: 'Payment Terms',
              icon: Icons.payment,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _notesController,
              label: 'Notes',
              icon: Icons.note,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSection() {
    TextEditingController _searchController = TextEditingController();
    List<Map<String, dynamic>> _filteredItems = [..._items];

    void _filterItems(String query) {
      setState(() {
        _filteredItems = _items.where((item) {
          final name = item['name'].toString().toLowerCase();
          final searchLower = query.toLowerCase();
          return name.contains(searchLower);
        }).toList();
      });
    }

    Future<void> _showAllItemsDialog(BuildContext context) async {
      TextEditingController dialogSearchController = TextEditingController();
      List<Map<String, dynamic>> dialogFilteredItems = [..._items];

      void filterDialogItems(String query) {
        setState(() {
          dialogFilteredItems = _items.where((item) {
            final name = item['name'].toString().toLowerCase();
            final searchLower = query.toLowerCase();
            return name.contains(searchLower);
          }).toList();
        });
      }

      return showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text('Select Items'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: dialogSearchController,
                      decoration: InputDecoration(
                        labelText: 'Search items',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: filterDialogItems,
                    ),
                    SizedBox(height: 16),
                    Container(
                      height: MediaQuery.of(context).size.height * 0.5,
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: ListView.builder(
                        itemCount: dialogFilteredItems.length,
                        itemBuilder: (context, index) {
                          final item = dialogFilteredItems[index];
                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: _buildItemImage(item['image']),
                              title: Text(item['name']),
                              subtitle: Text('${item['price']} PKR/${item['unit']}'),
                              trailing: IconButton(
                                icon: Icon(Icons.add, color: Colors.green),
                                onPressed: () {
                                  _addItem(item);
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.green[700], size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search items',
                prefixIcon: Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: Icon(Icons.list),
                  onPressed: () => _showAllItemsDialog(context),
                  tooltip: 'View all items',
                ),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterItems,
            ),
            const SizedBox(height: 16),
            if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Loading items...',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _filteredItems.isEmpty
                    ? Center(
                  child: Text(
                    'No items found',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
                    : ListView.builder(
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    return ListTile(
                      leading: _buildItemImage(item['image']),
                      title: Text(item['name']),
                      subtitle: Text('${item['price']} PKR/${item['unit']}'),
                      trailing: IconButton(
                        icon: Icon(Icons.add, color: Colors.orange[300]),
                        onPressed: () => _addItem(item),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemImage(String? imageData) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
      ),
      child: (imageData != null && imageData.isNotEmpty)
          ? ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildImageFromBase64(imageData),
      )
          : Icon(Icons.image, color: Colors.grey),
    );
  }

  Widget _buildImageFromBase64(String base64String) {
    try {
      // Check if the string is a URL or Base64
      if (base64String.startsWith('http') || base64String.startsWith('https')) {
        return Image.network(
          base64String,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.broken_image, color: Colors.grey),
        );
      } else {
        // Handle Base64 image
        return Image.memory(
          base64Decode(base64String),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.broken_image, color: Colors.grey),
        );
      }
    } catch (e) {
      print('Error loading image: $e');
      return Icon(Icons.broken_image, color: Colors.grey);
    }
  }

  Widget _buildSelectedItemsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: Colors.purple[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  'Order Items',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._selectedItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Item ${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[700],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _removeItem(index),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red[50],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildItemImage(item['image']),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoRow('Name:', item['name']),
                              _buildInfoRow('Price:', '${item['price']} PKR/${item['unit']}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: TextEditingController(text: item['quantity'].toString()),
                            label: 'Quantity',
                            keyboardType: TextInputType.number,
                            onChanged: (value) => _updateQuantity(index, int.tryParse(value) ?? 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: TextEditingController(text: item['price'].toStringAsFixed(2)),
                            label: 'Price',
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: TextEditingController(text: item['total'].toStringAsFixed(2)),
                            label: 'Total',
                            readOnly: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.indigo[50]!, Colors.blue[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined, color: Colors.indigo[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTotalRow('Subtotal:', _subtotal.toStringAsFixed(2)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    controller: _taxController,
                    label: _taxInPercentage ? 'Tax (%)' : 'Tax (PKR)',
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      setState(() {
                        _calculateTotals();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Text('PKR'),
                      Switch(
                        value: _taxInPercentage,
                        onChanged: (value) {
                          setState(() {
                            _taxInPercentage = value;
                            _calculateTotals();
                          });
                        },
                        activeColor: Colors.orange,
                      ),
                      Text('%'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    controller: _discountController,
                    label: _discountInPercentage ? 'Discount (%)' : 'Discount (PKR)',
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      setState(() {
                        _calculateTotals();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Text('PKR'),
                      Switch(
                        value: _discountInPercentage,
                        onChanged: (value) {
                          setState(() {
                            _discountInPercentage = value;
                            _calculateTotals();
                          });
                        },
                        activeColor: Colors.orange,
                      ),
                      Text('%'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTotalRow('Tax:', _tax.toStringAsFixed(2)),
            const SizedBox(height: 8),
            _buildTotalRow(
              'Discount:',
              (_discountInPercentage
                  ? (_subtotal * (double.tryParse(_discountController.text) ?? 0) / 100)
                  : (double.tryParse(_discountController.text) ?? 0)
              ).toStringAsFixed(2),
              color: Colors.red[600],
            ),
            const Divider(thickness: 2, height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.indigo[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildTotalRow(
                'GRAND TOTAL:',
                _total.toStringAsFixed(2),
                isBold: true,
                fontSize: 18,
                color: Colors.indigo[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _savePurchaseOrder,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange[300],
        padding: const EdgeInsets.symmetric(vertical: 16,horizontal: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: _isSaving
          ? CircularProgressIndicator(color: Colors.white)
          : Text(
        'Submit Purchase Order',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    bool readOnly = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    Function(String)? onChanged,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600]) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.teal, width: 2),
        ),
        filled: true,
        fillColor: readOnly ? Colors.grey[100] : Colors.grey[50],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {
    bool isBold = false,
    double fontSize = 14,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: fontSize,
            color: color,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: fontSize,
            color: color ?? Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.teal[700],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Remove listeners when disposing
    _taxController.removeListener(_calculateTotals);
    _discountController.removeListener(_calculateTotals);

    _poNumberController.dispose();
    _deliveryDateController.dispose();
    _termsController.dispose();
    _notesController.dispose();
    _taxController.dispose();
    _discountController.dispose();
    super.dispose();
  }
}