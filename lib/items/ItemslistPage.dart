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
import 'package:waheed_foods/items/stockreportpage.dart';
import 'dart:ui' as ui;
import 'editphysicalqty.dart';
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

  String? _savedPdfPath;
  Uint8List? _pdfBytes; // for web share
  Map<String, String> customerIdNameMap = {};

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
            'unit': item['unit'],
            'costPrice': item['costPrice'],
            'salePrice': item['salePrice'],
            'qtyOnHand': item['qtyOnHand'],
            'vendor': item['vendor'],
            'category': item['category'],
            'weightPerBag': item['weightPerBag'],
            'customerBasePrices': item['customerBasePrices'], // Add this line
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
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        title: Text("Items List"),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => RegisterItemPage()),
              );
            },
            icon: Icon(Icons.add,color: Colors.white,),
          ),
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _createPDFAndSave, // Generate PDF
          ),
          IconButton(
            icon: Icon(Icons.share, color: Colors.white),
            onPressed: _sharePDF, // Share PDF
          ),

          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => StockReportPage()),
              );
            },
            icon: Icon(Icons.history, color: Colors.white),
          ),

        ],

      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Item',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: _filteredItems.isEmpty
                ? Center(child: Text('No items found'))
                : ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    title: Text(item['itemName']),
                    subtitle: Text("Qty: ${item['qtyOnHand']}, Price: ${item['salePrice']}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.people, color: Colors.purple),
                          onPressed: () => _showCustomerRates(item),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue,),
                          onPressed: () => updateItem(item),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          // onPressed: () => deleteItem(item['key']),
                          onPressed: () => _confirmDelete(item['key']), // Changed to confirmation dialog
                        ),
                  IconButton(
                          icon: Icon(Icons.edit_note, color: Colors.blue),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditQtyPage(itemData: item),
                            ),
                          ),
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
    );
  }//s

  void _showCustomerRates(Map<String, dynamic> item) {
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
