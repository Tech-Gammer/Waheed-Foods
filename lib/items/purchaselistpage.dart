import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:waheed_foods/items/productionlistpage.dart';

import '../Provider/lanprovider.dart';
import 'itemPurchasePage.dart';

class PurchaseListPage extends StatefulWidget {
  @override
  State<PurchaseListPage> createState() => _PurchaseListPageState();
}

class _PurchaseListPageState extends State<PurchaseListPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _filteredPurchases = [];

  @override
  void initState() {
    super.initState();
    fetchPurchases();
  }

  void fetchPurchases() {
    FirebaseDatabase.instance.ref('purchases').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> purchases = data.entries.map((entry) {
          return {
            'key': entry.key,
            ...Map<String, dynamic>.from(entry.value),
          };
        }).toList();

        setState(() {
          _purchases = purchases;
          _filteredPurchases = purchases;
          print(_filteredPurchases);
        });
      }
    });
  }

  void searchPurchases(String query) {
    setState(() {
      _filteredPurchases = _purchases.where((purchase) {
        final itemName = purchase['itemName'].toLowerCase();
        final vendorName = purchase['vendorName'].toLowerCase();
        return itemName.contains(query.toLowerCase()) ||
            vendorName.contains(query.toLowerCase());
      }).toList();
    });
  }

  void editPurchase(Map<String, dynamic> purchase) async {
    final quantityController = TextEditingController(text: purchase['quantity'].toString());
    final priceController = TextEditingController(text: purchase['purchasePrice'].toString());

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Purchase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Price'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await FirebaseDatabase.instance.ref('purchases/${purchase['key']}').update({
                  'quantity': int.tryParse(quantityController.text) ?? purchase['quantity'],
                  'purchasePrice':
                  double.tryParse(priceController.text) ?? purchase['purchasePrice'],
                });
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase updated successfully')),
      );
    }
  }

  void deletePurchase(String key) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Confirm Delete' : 'حذف کی تصدیق کریں'),
          content: Text(languageProvider.isEnglish
              ? 'Are you sure you want to delete this purchase?'
              : 'کیا آپ واقعی اس خریداری کو حذف کرنا چاہتے ہیں؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), // No
              child: Text(languageProvider.isEnglish ? 'No' : 'نہیں'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true), // Yes
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, // Red color for delete action
              ),
              child: Text(languageProvider.isEnglish ? 'Yes' : 'ہاں'),
            ),
          ],
        );
      },
    );

    // If user confirms, delete the purchase
    if (confirmed == true) {
      await FirebaseDatabase.instance.ref('purchases/$key').remove();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Purchase deleted successfully'
              : 'خریداری کامیابی سے حذف ہو گئی'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.isEnglish ? 'Purchase List' : 'خریداری کی فہرست',
        style: const TextStyle(color: Colors.white,fontWeight: FontWeight.bold),
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
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ItemPurchasePage()),
              );
            },
            icon: Icon(Icons.add, color: Colors.white),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProductionListPage()),
              );
            },
            icon: Icon(Icons.list, color: Colors.white),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: searchPurchases,
              decoration:  InputDecoration(
                 labelText: languageProvider.isEnglish ? 'Search by Item or Vendor' : 'آئٹم یا وینڈر کے ذریعہ تلاش کریں۔',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredPurchases.isEmpty
                  ? const Center(child: Text('No purchases found'))
                  : ListView.builder(
                itemCount: _filteredPurchases.length,//s
                itemBuilder: (context, index) {
                  final purchase = _filteredPurchases[index];
                  return Card(
                    child: ListTile(
                      title: Text('${purchase['itemName']} from ${purchase['vendorName']}'),
                      subtitle: Text(
                          'Qty: ${purchase['quantity']}, Price: ${purchase['purchasePrice']}rs'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => editPurchase(purchase),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => deletePurchase(purchase['key']),
                          ),
                        ],
                      ),
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
}
