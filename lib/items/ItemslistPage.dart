import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:ui' as ui;
import '../Provider/lanprovider.dart';
import 'AddItems.dart';

class ItemsListPage extends StatefulWidget {
  @override
  _ItemsListPageState createState() => _ItemsListPageState();
}

class _ItemsListPageState extends State<ItemsListPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filteredItems = [];
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _selectedItem;

  String? _savedPdfPath;
  Uint8List? _pdfBytes;
  Map<String, String> customerIdNameMap = {};
  final Color _primaryColor = Color(0xFFFF8A65);
  final Color _secondaryColor = Color(0xFFFFB74D);
  final Color _backgroundColor = Colors.grey[50]!;
  final Color _cardColor = Colors.white;
  final Color _textColor = Colors.grey[800]!;

  Future<void> _fetchCustomerNames() async {
    final snapshot = await FirebaseDatabase.instance.ref('customers').get();

    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final Map<String, String> nameMap = {};

      data.forEach((key, value) {
        if (value is Map && value.containsKey('name')) {
          nameMap[key] = value['name'].toString();
        }
      });

      setState(() {
        customerIdNameMap = nameMap;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    fetchItems();
    _fetchCustomerNames(); // <-- fetch customer names early
    _searchController.addListener(_searchItems);
  }

  Future<void> fetchItems() async {
    _database.child('items').onValue.listen((event) {
      final Map? data = event.snapshot.value as Map?;
      if (data != null) {
        final fetchedItems = data.entries.map<Map<String, dynamic>>((entry) {
          return {
            'key': entry.key,
            ...Map<String, dynamic>.from(entry.value as Map),
          };
        }).toList();

        setState(() {
          _items = fetchedItems;
          _filteredItems = fetchedItems;
        });
      }
    });
  }

  void _searchItems() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _items.where((item) {
        String itemName = item['itemName']?.toString().toLowerCase() ?? '';
        return itemName.contains(query);
      }).toList();
    });
  }

  Future<pw.MemoryImage> _createTextImage(String text) async {
    // Use default text for empty input
    final String displayText = text.isEmpty ? "N/A" : text;

    // Scale factor to increase resolution
    const double scaleFactor = 1.5;

    // Create a custom painter with the Urdu text
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromPoints(
        Offset(0, 0),
        Offset(500 * scaleFactor, 50 * scaleFactor),
      ),
    );

    // Define text style with scaling
    final textStyle = TextStyle(
      fontSize: 12 * scaleFactor,
      fontFamily: 'JameelNoori', // Ensure this font is registered
      color: Colors.black,
      fontWeight: FontWeight.bold,
    );

    // Create the text span and text painter
    final textSpan = TextSpan(text: displayText, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left, // Adjust as needed for alignment
      textDirection: ui.TextDirection.rtl, // Use RTL for Urdu text
    );

    // Layout the text painter
    textPainter.layout();

    // Validate dimensions
    final double width = textPainter.width * scaleFactor;
    final double height = textPainter.height * scaleFactor;

    if (width <= 0 || height <= 0) {
      throw Exception("Invalid text dimensions: width=$width, height=$height");
    }

    // Paint the text onto the canvas
    textPainter.paint(canvas, Offset(0, 0));

    // Create an image from the canvas
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());

    // Convert the image to PNG
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    // Return the image as a MemoryImage
    return pw.MemoryImage(buffer);
  }


  Future<void> _createPDFAndSave() async {
    final ByteData logoBytes = await rootBundle.load('assets/images/logo.png');
    final image = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final pdf = pw.Document();
    List<pw.MemoryImage> descriptionImages = [];

    for (var row in _filteredItems) {
      final img = await _createTextImage(row['itemName']);
      descriptionImages.add(img);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(image, width: 100, height: 100),
              pw.Text('Items List', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Item Name', 'Qty', 'Price', 'Unit', 'Customer Prices'],
            cellAlignment: pw.Alignment.centerLeft,
            data: _filteredItems.asMap().entries.map((entry) {
              int index = entry.key;
              var item = entry.value;

              // // Build customer prices string
              // String customerPrices = "";
              // if (item['customerBasePrices'] != null) {
              //   final prices = item['customerBasePrices'] as Map;
              //   customerPrices = prices.entries
              //       .map((e) => "${e.key}: ${e.value}")
              //       .join("\n");
              // }
              String customerPrices = "";
              if (item['customerBasePrices'] != null) {
                final prices = item['customerBasePrices'] as Map;
                customerPrices = prices.entries.map((e) {
                  final name = customerIdNameMap[e.key] ?? e.key; // fallback to ID
                  return "$name: ${e.value}";
                }).join("\n");
              }


              return [
                // pw.Image(descriptionImages[index], dpi: 100),
                item['itemName'].toString(),
                item['qtyOnHand'].toString(),
                item['salePrice'].toString(),
                item['unit'].toString(),
                customerPrices,
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    _pdfBytes = bytes;

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF generated for web (use share button)")),
      );
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/items_list.pdf');
      await file.writeAsBytes(bytes);
      setState(() {
        _savedPdfPath = file.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF saved to temporary folder")),
      );
    }
  }

  Future<void> _sharePDF() async {
    if (kIsWeb) {
      if (_pdfBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Generate PDF first")));
        return;
      }
      await Printing.sharePdf(bytes: _pdfBytes!, filename: 'items_list.pdf');
    } else {
      if (_savedPdfPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Generate PDF first")));
        return;
      }
      await Share.shareXFiles([XFile(_savedPdfPath!)], text: 'Items List PDF');
    }
  }

  void updateItem(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterItemPage(
          itemData: {
            'key': item['key'],
            'itemName': item['itemName'],
            'image': item['image'],
            'unit': item['unit'] ?? '', // Handle null for BOM
            'costPrice': item['costPrice'] ?? 0.0, // Handle null for BOM
            'salePrice': item['salePrice'] ?? 0.0,
            'qtyOnHand': item['qtyOnHand'] ?? 0,
            'vendor': item['vendor'] ?? '', // Handle null for BOM
            'category': item['category'] ?? '', // Handle null for BOM
            'weightPerBag': item['weightPerBag'] ?? 1.0,
            'customerBasePrices': item['customerBasePrices'], // May be null for BOM
            'isBOM': item['isBOM'] ?? false, // Add this field
            'components': item['components'], // For BOM items
          },
        ),
      ),
    );
  }

  void _confirmDelete(String key) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish
              ? "Confirm Delete"
              : "حذف کرنے کی تصدیق کریں"),
          content: Text(languageProvider.isEnglish
              ? "Are you sure you want to delete this item?"
              : "کیا آپ واقعی اس آئٹم کو حذف کرنا چاہتے ہیں؟"),
          actions: <Widget>[
            TextButton(
              child: Text(languageProvider.isEnglish ? "Cancel" : "منسوخ کریں",
                  style: TextStyle(color: Colors.teal)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(languageProvider.isEnglish ? "Delete" : "حذف کریں",
                  style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                deleteItem(key); // Proceed with deletion
              },
            ),
          ],
        );
      },
    );
  }

  void deleteItem(String key) {
    _database.child('items/$key').remove().then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item deleted successfully!')),
      );
    }).catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete item: $error')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inventory Information'),
        actions: [
          IconButton(icon: Icon(Icons.picture_as_pdf), onPressed: _createPDFAndSave),
          IconButton(icon: Icon(Icons.share), onPressed: _sharePDF),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _secondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_backgroundColor.withOpacity(0.9), _backgroundColor],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            /// Left Panel - Item List
            Expanded(
              flex: 2,
              child: Card(
                margin: EdgeInsets.all(8),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: 'Search Item',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: _cardColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              title: Text(item['itemName'],
                                  style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
                              subtitle: Text("Price: ${item['salePrice']}",
                                  style: TextStyle(color: _textColor.withOpacity(0.7))),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit, color: _primaryColor),
                                    onPressed: () => updateItem(item),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _confirmDelete(item['key']),
                                  ),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedItem = item;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            /// Center Panel - Item Detail
            Expanded(
              flex: 3,
              child: _selectedItem == null
                  ? Center(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("Select an item to view details",
                        style: TextStyle(color: _textColor)),
                  ),
                ),
              )
                  : Card(
                margin: EdgeInsets.all(8),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Inventory Information",
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: _primaryColor,
                              fontWeight: FontWeight.bold
                          )),
                      if (_selectedItem!['isBOM'] == true)
                        Chip(
                          label: Text("BOM"),
                          backgroundColor: Colors.blue[100],
                        ),
                      IconButton(
                        icon: Icon(Icons.attach_money, color: _secondaryColor),
                        onPressed: () => _showCustomerRates(_selectedItem!),
                      ),
                    ],
                  ),
                  Divider(color: _primaryColor.withOpacity(0.3)),
                  SizedBox(height: 16),
                      _buildDetailRow("Item Name", _selectedItem!['itemName']?.toString() ?? 'N/A'),
                      if (_selectedItem!['isBOM'] != true) ...[
                        _buildDetailRow("Cost Price", _selectedItem!['costPrice']?.toString() ?? 'N/A'),
                        _buildDetailRow("Unit", _selectedItem!['unit']?.toString() ?? 'N/A'),
                        _buildDetailRow("Vendor", _selectedItem!['vendor']?.toString() ?? 'N/A'),
                      ],
                      _buildDetailRow("Sale Price", _selectedItem!['salePrice']?.toString() ?? 'N/A'),
                      _buildDetailRow("Quantity", _selectedItem!['qtyOnHand']?.toString() ?? 'N/A'),
                      _buildDetailRow("Category", _selectedItem!['category']?.toString() ?? 'N/A'),
                      if (_selectedItem!['isBOM'] == true) ...[
                        SizedBox(height: 16),
                        Text("Components:",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _primaryColor)),
                        SizedBox(height: 8),
                        Container(
                          height: 350, // Fixed height for the components list
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _selectedItem!['components'] == null
                              ? Center(child: Text("No components"))
                              : ListView.builder(
                            padding: EdgeInsets.all(8),
                            itemCount: _selectedItem!['components'].length,
                            itemBuilder: (context, index) {
                              final component = _selectedItem!['components'][index];
                              return Card(
                                margin: EdgeInsets.symmetric(vertical: 4),
                                elevation: 2,
                                child: ListTile(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                                  title: Text(component['name'] ?? 'Unnamed component'),
                                  subtitle: Text(
                                      '${component['quantity']} ${component['unit']}'),
                                  trailing: Text(
                                      '${(component['price'] * component['quantity']).toStringAsFixed(2)} PKR'),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                  Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text("Edit", style: TextStyle(color: Colors.white)),
                        onPressed: () => updateItem(_selectedItem!),
                      ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text("Delete", style: TextStyle(color: Colors.white)),
                          onPressed: () => _confirmDelete(_selectedItem!['key']),
                        ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),


            /// Right Panel (Optional) – Image, etc.
        Expanded(
          flex: 2,
          child: Card(
              margin: EdgeInsets.all(8),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Text("Item Image",
                  style: TextStyle(
                      color: _primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18
                  )),
              SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  if (_selectedItem != null && _selectedItem!['image'] != null) {
                    _showImagePreview(context, _selectedItem!['image']);
                  }
                },
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 5,
                        spreadRadius: 2,
                      )
                    ],
                    image: _selectedItem != null && _selectedItem!['image'] != null
                        ? DecorationImage(
                      image: MemoryImage(base64Decode(_selectedItem!['image'])),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: Icon(Icons.image, size: 60, color: _secondaryColor),
                ),
              ),
              SizedBox(height: 20),
              if (_selectedItem != null) ...[
          _buildStatCard("Stock Value",
          "₹${(double.parse(_selectedItem!['qtyOnHand'].toString()) * double.parse(_selectedItem!['salePrice'].toString()))}"),
          SizedBox(height: 10),
          _buildStatCard("Profit Margin", "30%"), // Example value
          ],
          ],
        ),
      ),
    ),



          ],
        ),
      ),

      /// Bottom Panel – Transactions
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 2,
            )
          ],
        ),
        padding: EdgeInsets.all(12),
        height: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text("Recent Transactions",
                    style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16
                    )),
                Spacer(),
                Icon(Icons.history, color: _secondaryColor),
              ],
            ),
            Divider(color: _primaryColor.withOpacity(0.3)),
            Expanded(
              child: Center(
                child: Text(
                  "No recent transactions available",
                  style: TextStyle(color: _textColor.withOpacity(0.6)),
                ),
              ),
            )
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: _primaryColor,
        child: Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RegisterItemPage()),
          ).then((_) => fetchItems());
        },
      ),



    );
  }

  void _showImagePreview(BuildContext context, String imageBase64) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(20),
        child: Stack(
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: kIsWeb
                  ? Image.network('data:image/png;base64,$imageBase64')
                  : Image.memory(base64Decode(imageBase64)),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title,
                style: TextStyle(
                    color: _textColor.withOpacity(0.7),
                    fontSize: 14
                )),
            SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18
                )),
          ],
        ),
      ),
    );
  }


  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.bold
                )),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(value.isNotEmpty ? value : 'N/A',
                style: TextStyle(
                  color: _textColor.withOpacity(0.8),
                )),
          ),
        ],
      ),
    );
  }


  void _showCustomerRates(Map<String, dynamic> item) {


    if (item['isBOM'] == true) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(languageProvider.isEnglish
            ? "BOM items don't have customer prices"
            : "BOM آئٹمز میں کسٹمر قیمتیں نہیں ہوتیں")),
      );
      return;
    }
    // Safely get and convert customerBasePrices
    final rawPrices = item['customerBasePrices'];
    final Map<String, dynamic> customerPrices = {};

    if (rawPrices != null) {
      try {
        // Convert from Map<dynamic, dynamic> to Map<String, dynamic>
        customerPrices.addAll(Map<String, dynamic>.from(rawPrices));
      } catch (e) {
        print('Error converting customer prices: $e');
      }
    }

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${languageProvider.isEnglish ? 'Customer Prices for' : 'کسٹمر کی قیمتیں برائے'} ${item['itemName']}"),
        content: SizedBox(
          width: double.maxFinite,
          child: customerPrices.isEmpty
              ? Text(languageProvider.isEnglish
              ? "No custom prices set"
              : "کوئی مخصوص قیمتیں مقرر نہیں ہیں")
              : ListView.builder(
            shrinkWrap: true,
            itemCount: customerPrices.length,
            itemBuilder: (context, index) {
              final customerId = customerPrices.keys.elementAt(index);
              final price = customerPrices[customerId];
              return FutureBuilder(
                future: _getCustomerName(customerId.toString()), // Ensure customerId is String
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListTile(
                      title: Text("Loading..."),
                    );
                  }
                  return ListTile(
                    title: Text("${snapshot.data ?? "Unknown Customer"}"),
                    trailing: Text("$price"),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(languageProvider.isEnglish ? "Close" : "بند کریں"),
          ),
        ],
      ),
    );
  }

  Future<String?> _getCustomerName(String customerId) async {
    final snapshot = await FirebaseDatabase.instance
        .ref()
        .child('customers/$customerId/name')
        .get();

    return snapshot.exists ? snapshot.value.toString() : null;
  }
}
