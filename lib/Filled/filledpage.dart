  import 'dart:convert';
  import 'dart:io';
  import 'package:file_picker/file_picker.dart';
  import 'package:firebase_database/firebase_database.dart';
  import 'package:flutter/foundation.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:image_picker/image_picker.dart';
  import 'package:intl/intl.dart';
  import 'package:path_provider/path_provider.dart';
  import 'package:printing/printing.dart';
  import 'package:provider/provider.dart';
  import 'package:pdf/pdf.dart';
  import 'package:pdf/widgets.dart' as pw;
  import 'package:waheed_foods/Filled/quotationpage.dart';
  import '../Models/itemModel.dart';
  import '../Provider/customerprovider.dart';
  import '../Provider/filled provider.dart';
  import '../Provider/lanprovider.dart';
  import 'package:flutter/rendering.dart';
  import 'dart:ui' as ui;
  import 'package:share_plus/share_plus.dart';
  import 'dart:html' as html;
  import '../bankmanagement/banknames.dart';
  
  
  
  class filledpage extends StatefulWidget {
    final Map<String, dynamic>? filled; // Optional filled data for editingss
  
    filledpage({this.filled});
  
    @override
    _filledpageState createState() => _filledpageState();
  }
  
  class _filledpageState extends State<filledpage> {
    final DatabaseReference _db = FirebaseDatabase.instance.ref();
    List<Item> _items = [];
    String? _selectedItemName;
    String? _selectedItemId;
    double _selectedItemRate = 0.0;
    String? _selectedCustomerName; // This should hold the name of the selected customer
    String? _selectedCustomerId;
    double _discount = 0.0; // Discount amount or percentage
    String _paymentType = 'instant';
    String? _instantPaymentMethod;
    TextEditingController _discountController = TextEditingController();
    List<Map<String, dynamic>> _filledRows = [];
    String? _filledId; // For editing existing filled
    // late bool _isReadOnly;
    bool _isReadOnly = false; // Initialize with default value
    bool _isButtonPressed = false;
    final TextEditingController _customerController = TextEditingController();
    final TextEditingController _rateController = TextEditingController();
    final TextEditingController _dateController = TextEditingController();
    double _remainingBalance = 0.0; // Add this variable to store the remaining balance
    TextEditingController _paymentController = TextEditingController();
    TextEditingController _referenceController = TextEditingController();
    bool _isSaved = false;
    Map<String, dynamic>? _currentFilled;
    List<Map<String, dynamic>> _cachedBanks = [];
    // In your _filledpageState class
    double _mazdoori = 0.0;
    TextEditingController _mazdooriController = TextEditingController();
    String? _selectedBankId;
    String? _selectedBankName;
    TextEditingController _chequeNumberController = TextEditingController();
    DateTime? _selectedChequeDate;
    Map<String, Map<String, double>> _customerItemPrices = {};
  
  
    void _fetchCustomerPrices(String customerId) async {
      final DatabaseReference pricesRef = FirebaseDatabase.instance.ref().child('items');
      final DatabaseEvent snapshot = await pricesRef.once();
  
      if (snapshot.snapshot.exists) {
        final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<dynamic, dynamic>;
        Map<String, Map<String, double>> prices = {};
  
        itemsMap.forEach((itemId, itemData) {
          final item = itemData as Map<dynamic, dynamic>;
          if (item['customerBasePrices'] != null) {
            final customerPrices = item['customerBasePrices'] as Map<dynamic, dynamic>;
            if (customerPrices.containsKey(customerId)) {
              final price = double.tryParse(customerPrices[customerId].toString()) ?? 0.0;
              if (!prices.containsKey(itemId)) {
                prices[itemId] = {};
              }
              prices[itemId]![customerId] = price;
            }
          }
        });
  
        setState(() {
          _customerItemPrices = prices;
        });
      }
    }

    Future<void> _fetchRemainingBalance() async {
      if (_selectedCustomerId != null) {
        try {
          final balance = await _getRemainingBalance(_selectedCustomerId!);
          setState(() {
            _remainingBalance = balance;
          });
        } catch (e) {
          setState(() {
            _remainingBalance = 0.0; // Set a default value in case of error
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch remaining balance: $e')),
          );
        }
      }
    }



    Future<void> _selectDate(BuildContext context) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _dateController.text.isNotEmpty
            ? DateTime.parse(_dateController.text)
            : DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2101),
      );
      if (picked != null) {
        setState(() {
          _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
        });
      }
    }
  
    void _addNewRow() {
      setState(() {
        _filledRows.add({
          'total': 0.0,
          'rate': 0.0,
          'qty': 0.0,
          'description': '',
          'itemName': '', // Add this field to store the item name
          'itemNameController': TextEditingController(), // Add this line
          'rateController': TextEditingController(),
          'qtyController': TextEditingController(),
          'descriptionController': TextEditingController(),
        });
        _calculateInitialTotals(); // Add this line

      });
    }
  
    void _updateRow(int index, String field, dynamic value) {
      setState(() {
        _filledRows[index][field] = value;
        // Recalculate totals based on rate and qty
        if (field == 'rate' || field == 'qty')  {
          double rate = _filledRows[index]['rate'] ?? 0.0;
          double qty = _filledRows[index]['qty'] ?? 0.0;
          _filledRows[index]['total'] = rate * qty;
        }
        _calculateInitialTotals(); // Add this to ensure all totals are updated

      });
    }
  
    void _deleteRow(int index) {
      setState(() {
        final deletedRow = _filledRows[index];
        // Dispose all controllers for the deleted row
        deletedRow['itemNameController']?.dispose();
        deletedRow['rateController']?.dispose();
        deletedRow['qtyController']?.dispose();
        deletedRow['descriptionController']?.dispose();
        _filledRows.removeAt(index);
      });
    }
  
    double _calculateSubtotal() {
      return _filledRows.fold(0.0, (sum, row) => sum + (row['total'] ?? 0.0));
    }
  

    double _calculateGrandTotal() {
      double subtotal = _calculateSubtotal();
      // Apply discount (subtract from subtotal)
      double afterDiscount = subtotal - _discount;
      // Add labor charges
      return afterDiscount + _mazdoori;
    }
  
    Future<Uint8List> _generatePDFBytes(String filledNumber) async {
      final pdf = pw.Document();
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      // final selectedCustomer = customerProvider.customers.firstWhere((customer) => customer.id == _selectedCustomerId);
      // Add null checks for customer selection
      final filledProvider = Provider.of<FilledProvider>(context, listen: false);
      // Get invoice data
      final filled = widget.filled ?? _currentFilled;
      if (filled == null) {
        throw Exception("No invoice data available");
      }
      // Get payment details
      double paidAmount = 0.0;
      try {
        final payments = await filledProvider.getFilledPayments(filled['filledNumber']);
        paidAmount = payments.fold(0.0, (sum, payment) => sum + (_parseToDouble(payment['amount']) ?? 0.0));
      } catch (e) {
        print("Error fetching payments: $e");
      }
  
      double grandTotal = _calculateGrandTotal();
      double remainingAmount = grandTotal - paidAmount;
  
      if (_selectedCustomerId == null) {
        throw Exception("No customer selected");
      }
      final selectedCustomer = customerProvider.customers.firstWhere(
              (customer) => customer.id == _selectedCustomerId,
          orElse: () => Customer( // Add orElse to handle missing customer
              id: 'unknown',
              name: 'Unknown Customer',
              phone: '',
              address: ''
          )
      );
      DateTime filledDate;
      if (widget.filled != null) {
        filledDate = DateTime.parse(widget.filled!['createdAt']);
      } else {
        if (_dateController.text.isNotEmpty) {
          DateTime selectedDate = DateTime.parse(_dateController.text);
          DateTime now = DateTime.now();
          filledDate = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            now.hour,
            now.minute,
            now.second,
          );
        } else {
          filledDate = DateTime.now();
        }
      }
  
      final String formattedDate = '${filledDate.day}/${filledDate.month}/${filledDate.year}';
      final String formattedTime = '${filledDate.hour}:${filledDate.minute.toString().padLeft(2, '0')}';
      // Get the remaining balance from the ledger

      double remainingBalance = await _getRemainingBalance(_selectedCustomerId!, excludeCurrentInvoice: true);

      // Calculate the new balance (previous balance + current invoice amount)
      double newBalance = remainingBalance + grandTotal;
  
      // Load the image asset for the logo
      final ByteData bytes = await rootBundle.load('assets/images/logo.png');
      final buffer = bytes.buffer.asUint8List();
      final image = pw.MemoryImage(buffer);

      // Load the image asset for the logo
      final ByteData linebytes = await rootBundle.load('assets/images/line.png');
      final linebuffer = linebytes.buffer.asUint8List();
      final lineimage = pw.MemoryImage(linebuffer);
  
      // Load the footer logo if different
      final ByteData footerBytes = await rootBundle.load('assets/images/devlogo.png');
      final footerBuffer = footerBytes.buffer.asUint8List();
      final footerLogo = pw.MemoryImage(footerBuffer);
  
      // Pre-generate images for all descriptions
      List<pw.MemoryImage> descriptionImages = [];
      for (var row in _filledRows) {
        final image = await _createTextImage(row['description']);
        descriptionImages.add(image);
      }
  
      // Pre-generate images for all item namess
      List<pw.MemoryImage> itemnameImages = [];
      for (var row in _filledRows) {
        final image = await _createTextImage(row['itemName']);
        itemnameImages.add(image);
      }
  
      // // Generate customer details as an image
      // final customerDetailsImage = await _createTextImage(
      //   'Customer Name: ${selectedCustomer.name}\n'
      //       'Customer Address: ${selectedCustomer.address}',
      // );
  
      // Add a page with A5 size
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5, // Set page size to A5
          margin: const pw.EdgeInsets.all(10), // Add margins for better spacing
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Company Logo and filled Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Image(image, width: 80, height: 80),

                    /// Centered column using Expanded and Align
                    pw.Expanded(
                      child: pw.Align(
                        alignment: pw.Alignment.center,
                        child: pw.Column(
                          children: [
                            pw.Text(
                              'Waheed Foods',
                              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.Text(
                              'Pure & Fine Gram Flour Manufactures',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.Text(
                              'Contact: 0321-2672000, 03006232539',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // You can re-enable this column if needed
                    // pw.Column(
                    //   children: [
                    //     pw.Text('Invoice', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    //     pw.Text('M. Zeeshan', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    //     pw.Text('0300-6400717', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    //   ],
                    // ),
                  ],
                ),
                pw.Divider(),
  
                // Customer Information
                // pw.Image(customerDetailsImage, width: 250, dpi: 1000), // Adjust width
                pw.Text('Customer Name: ${selectedCustomer.name}', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Customer Address: ${selectedCustomer.address}', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Customer Number: ${selectedCustomer.phone}', style: const pw.TextStyle(fontSize: 11)),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Previous Balance: ${remainingBalance.toStringAsFixed(2)}rs', style:  pw.TextStyle(fontSize: 12,fontWeight: pw.FontWeight.bold)),
                    // pw.Text(remainingBalance.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
                pw.Text('Date: $formattedDate', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Time: $formattedTime', style: const pw.TextStyle(fontSize: 10)),
  
                pw.Text('Reference: ${_referenceController.text}', style: const pw.TextStyle(fontSize: 12)),
  
                pw.SizedBox(height: 10),
  
                // Filled Table with Urdu text converted to images
                pw.Table.fromTextArray(
                  headers: [
                    pw.Text('Item Name', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Description', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Qty(Pcs)', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Rate', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Total', style: const pw.TextStyle(fontSize: 10)),
                  ],
                  data: _filledRows.asMap().map((index, row) {
                    return MapEntry(
                      index,
                      [
                        // pw.Image(itemnameImages[index], dpi: 1000),
                        // pw.Image(descriptionImages[index], dpi: 1000),
                        pw.Text(row['itemName'] ?? '', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(row['description']??'',style: const pw.TextStyle(fontSize: 10)),
                        pw.Text((row['qty'] ?? 0).toString(), style: const pw.TextStyle(fontSize: 10)),
                        pw.Text((row['rate'] ?? 0.0).toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10)),
                        pw.Text((row['total'] ?? 0.0).toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10)),
                      ],
                    );
                  }).values.toList(),
                ),
                pw.SizedBox(height: 10),
  
                // pw.Row(
                //   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                //   children: [
                //     pw.Text('Sub Total:', style: const pw.TextStyle(fontSize: 12)),
                //     pw.Text(_calculateSubtotal().toStringAsFixed(2), style: const pw.TextStyle(fontSize: 12)),
                //   ],
                // ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Discount:', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text(_discount.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Mazdoori:', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text(_mazdoori.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Invoice Amount:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text(grandTotal.toStringAsFixed(2), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ],
                ),

                // // ✅ New Balance (Total of Invoice + Previous Balance)
                // pw.Row(
                //   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                //   children: [
                //     pw.Text('Total (Invoice + Previous Balance):', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                //     pw.Text(newBalance.toStringAsFixed(2), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                //   ],
                // ),//s
                // Add paid amount row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Paid Amount:', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text(paidAmount.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
  
                // Add remaining amount row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Remaining Amount:', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text(remainingAmount.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 60),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text('......................', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
  
                // Footer Sectiondasd
                pw.Spacer(), // Push footer to the bottom of the page
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Image(footerLogo, width: 30, height: 20), // Footer logo
                    pw.Image(lineimage,width: 150,height: 50),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'Developed By: Umair Arshad',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'Contact: 0307-6455926',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
      return pdf.save();
    }
  
    Future<void> _generateAndPrintPDF() async {
      String filledNumber;
      if (widget.filled != null) {
        filledNumber = widget.filled!['filledNumber'];
      } else {
        final filledProvider = Provider.of<FilledProvider>(context, listen: false);
        filledNumber = (await filledProvider.getNextFilledNumber()).toString();
      }
  
      try {
        final bytes = await _generatePDFBytes(filledNumber);
        await Printing.layoutPdf(onLayout: (format) => bytes);
      } catch (e) {
        print("Error printing: $e");
      }
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
          const Offset(0, 0),
          const Offset(500 * scaleFactor, 50 * scaleFactor),
        ),
      );
  
      // Define text style with scaling
      final textStyle = const TextStyle(
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
      textPainter.paint(canvas, const Offset(0, 0));
  
      // Create an image from the canvas
      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
  
      // Convert the image to PNG
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();
  
      // Return the image as a MemoryImage
      return pw.MemoryImage(buffer);
    }

    Future<double> _getRemainingBalance(String customerId, {bool excludeCurrentInvoice = false}) async {
      try {
        // double invoiceBalance = 0.0;
        double filledBalance = 0.0;

        final filledLedgerRef = _db.child('filledledger').child(customerId);
        final filledSnapshot = await filledLedgerRef.orderByChild('createdAt').limitToLast(1).once();
        if (filledSnapshot.snapshot.exists) {
          final Map<dynamic, dynamic>? filledData = filledSnapshot.snapshot.value as Map<dynamic, dynamic>?;
          if (filledData != null) {
            final lastEntryKey = filledData.keys.first;
            final lastEntry = filledData[lastEntryKey] as Map<dynamic, dynamic>?;
            if (lastEntry != null) {
              final dynamic balanceValue = lastEntry['remainingBalance'];
              filledBalance = (balanceValue is int)
                  ? balanceValue.toDouble()
                  : (balanceValue as double? ?? 0.0);
            }
          }
        }

        // return invoiceBalance + filledBalance;
        return filledBalance;
      } catch (e) {
        print("Error fetching remaining balance: $e");
        return 0.0;
      }
    }

    Future<List<Item>> fetchItems() async {
      final DatabaseReference itemsRef = FirebaseDatabase.instance.ref().child('items');
      final DatabaseEvent snapshot = await itemsRef.once();
  
      if (snapshot.snapshot.exists) {
        final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<dynamic, dynamic>;
        return itemsMap.entries.map((entry) {
          return Item.fromMap(entry.value as Map<dynamic, dynamic>, entry.key as String);
        }).toList();
      } else {
        return [];
      }
    }
  
    Future<void> _fetchItems() async {
      final items = await fetchItems();
      setState(() {
        _items = items;
      });
    }
  
    Future<void> _updateQtyOnHand(List<Map<String, dynamic>> validItems) async {
      try {
        for (var item in validItems) {
          final itemName = item['itemName'];
          if (itemName == null || itemName.isEmpty) continue;
  
          final dbItem = _items.firstWhere(
                (i) => i.itemName == itemName,
            orElse: () => Item(id: '', itemName: '', costPrice: 0.0, qtyOnHand: 0.0,salePrice: 0.0),
          );
  
          if (dbItem.id.isNotEmpty) {
            final String itemId = dbItem.id;
            final double currentQty = dbItem.qtyOnHand ?? 0.0;
            final double newQty = item['qty'] ?? 0.0;
            final double initialQty = item['initialQty'] ?? 0.0;
  
            // Calculate the difference between the new quantity and the initial quantity
            double delta = initialQty - newQty;
  
            // Update the qtyOnHand in the database
            double updatedQty = currentQty + delta;
  
            await _db.child('items/$itemId').update({'qtyOnHand': updatedQty});
          }
        }
      } catch (e) {
        print("Error updating qtyOnHand: $e");
      }
    }
  
    Future<void> _savePDF(String filledNumber) async {
      try {
        final bytes = await _generatePDFBytes(filledNumber);
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/filled_$filledNumber.pdf');
        await file.writeAsBytes(bytes);
  
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved to ${file.path}'),
          ),
        );
      } catch (e) {
        print("Error saving PDF: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save PDF: ${e.toString()}')),
        );
      }
    }
  
    Future<void> _sharePDFViaWhatsApp(String filledNumber) async {
      try {
        final bytes = await _generatePDFBytes(filledNumber);
  
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'filled_$filledNumber.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);
  
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF download started')),
        );
      } catch (e) {
        print('Error sharing PDF: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: ${e.toString()}')),
        );
      }
    }
  
    Future<void> _showDeletePaymentConfirmationDialog(
        BuildContext context,
        String filledId,
        String paymentKey,
        String paymentMethod,
        double paymentAmount,
        )
    async {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
  
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(languageProvider.isEnglish ? 'Delete Payment' : 'ادائیگی ڈیلیٹ کریں'),
            content: Text(languageProvider.isEnglish
                ? 'Are you sure you want to delete this payment?'
                : 'کیا آپ واقعی اس ادائیگی کو ڈیلیٹ کرنا چاہتے ہیں؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(languageProvider.isEnglish ? 'Cancel' : 'رد کریں'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await Provider.of<FilledProvider>(context, listen: false).deletePaymentEntry(
                      context: context, // Pass the context here
                      filledId: filledId,
                      paymentKey: paymentKey,
                      paymentMethod: paymentMethod,
                      paymentAmount: paymentAmount,
                    );
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment deleted successfully.')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete payment: ${e.toString()}')),
                    );
                  }
                },
                child: Text(languageProvider.isEnglish ? 'Delete' : 'ڈیلیٹ کریں'),
              ),
            ],
          );
        },
      );
    }
  
    Future<void> _showFullScreenImage(Uint8List imageBytes) async {
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    }
  
    double _parseToDouble(dynamic value) {
      if (value is int) {
        return value.toDouble();
      } else if (value is double) {
        return value;
      } else if (value is String) {
        return double.tryParse(value) ?? 0.0;
      } else {
        return 0.0;
      }
    }
  
    DateTime _parsePaymentDate(dynamic date) {
      if (date is String) {
        // If the date is a string, try parsing it directly
        return DateTime.tryParse(date) ?? DateTime.now();
      } else if (date is int) {
        // If the date is a timestamp (in milliseconds), convert it to DateTime
        return DateTime.fromMillisecondsSinceEpoch(date);
      } else if (date is DateTime) {
        // If the date is already a DateTime object, return it directly
        return date;
      } else {
        // Fallback to the current date if the format is unknown
        return DateTime.now();
      }
    }
  
    Future<void> _showPaymentDetails(Map<String, dynamic> filled) async {
      final filledProvider = Provider.of<FilledProvider>(context, listen: false);
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
  
      try {
        final payments = await filledProvider.getFilledPayments(filled['filledNumber']);
  
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(languageProvider.isEnglish ? 'Payment History' : 'ادائیگی کی تاریخ'),
            content: Container(
              width: double.maxFinite,
              child: payments.isEmpty
                  ? Text(languageProvider.isEnglish
                  ? 'No payments found'
                  : 'کوئی ادائیگی نہیں ملی')
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: payments.length,
                itemBuilder: (context, index) {
                  final payment = payments[index];
                  Uint8List? imageBytes;
                  if (payment['image'] != null) {
                    imageBytes = base64Decode(payment['image']);
                  }
  
                  // Determine payment method display text
                  String paymentMethodText;
                  if (payment['method'] == 'Bank') {
                    paymentMethodText = '${payment['bankName'] ?? 'Bank'}';
                  }
                  else if (payment['method'] == 'Cheque') {
                    paymentMethodText = 'Cheque (${payment['status'] ?? 'pending'})';
                  }
                  else {
                    paymentMethodText = payment['method'];
                  }
  
                  return Card(
                    child: ListTile(
                      title: Text(
                        '$paymentMethodText: Rs ${payment['amount']}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('yyyy-MM-dd – HH:mm')
                              .format(payment['date'])),
                          if (payment['description'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(payment['description']),
                            ),
                          if (payment['method'] == 'Cheque')
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Cheque #${payment['chequeNumber']} - ${payment['status']}',
                                style: TextStyle(
                                  color: payment['status'] == 'cleared'
                                      ? Colors.green
                                      : payment['status'] == 'bounced'
                                      ? Colors.red
                                      : Colors.orange,
                                ),
                              ),
                            ),
                          if (imageBytes != null)
                            Column(
                              children: [
                                GestureDetector(
                                  onTap: () => _showFullScreenImage(imageBytes!),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Hero(
                                      tag: 'paymentImage$index',
                                      child: Image.memory(
                                        imageBytes,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _showFullScreenImage(imageBytes!),
                                  child: Text(
                                    Provider.of<LanguageProvider>(context, listen: false)
                                        .isEnglish
                                        ? 'View Full Image'
                                        : 'مکمل تصویر دیکھیں',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      trailing: payment['method'] != 'Cheque' || payment['status'] != 'cleared'
                          ? null
                          : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _showDeletePaymentConfirmationDialog(
                              context,
                              filled['filledNumber'],
                              payment['key'],
                              payment['method'],
                              payment['amount'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => _printPaymentHistoryPDF(payments, context),
                child: Text(languageProvider.isEnglish ? 'Print Payment History' : 'ادائیگی کی تاریخ پرنٹ کریں'),
              ),
              TextButton(
                child: Text(languageProvider.isEnglish ? 'Close' : 'بند کریں'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading payments: ${e.toString()}')),
        );
      }
    }
  
    Future<void> _printPaymentHistoryPDF(List<Map<String, dynamic>> payments, BuildContext context) async {
      final pdf = pw.Document();
      // Load the image asset for the logo
      final ByteData bytes = await rootBundle.load('assets/images/logo.png');
      final buffer = bytes.buffer.asUint8List();
      final image = pw.MemoryImage(buffer);
  
      // Load the footer logo if different
      final ByteData footerBytes = await rootBundle.load('assets/images/devlogo.png');
      final footerBuffer = footerBytes.buffer.asUint8List();
      final footerLogo = pw.MemoryImage(footerBuffer);
      // Generate all description images asynchronously
      final List<List<dynamic>> tableData = await Future.wait(
        payments.map((payment) async {
          final paymentAmount = _parseToDouble(payment['amount']);
          final paymentDate = _parsePaymentDate(payment['date']);
          final description = payment['description'] ?? 'N/A';
          // DateFormat('yyyy-MM-dd – HH:mm').format(paymentDate);
  
          // Generate image from description text
          final descriptionImage = await _createTexttoImage(description);
  
          return [
            payment['method'],
            'Rs ${paymentAmount.toStringAsFixed(2)}',
            DateFormat('yyyy-MM-dd – HH:mm').format(paymentDate),
            pw.Image(descriptionImage), // Use the generated image
          ];
        }),
      );
  
      // Add a multi-page layout to handle multiple payments
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => [
            // Header section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Image(image, width: 80, height: 80), // Adjust logo size
                pw.Text('Payment History',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ],
            ),
  
            // Table with payment history
            pw.Table.fromTextArray(
              headers: ['Method', 'Amount', 'Date', 'Description'],
              // data: tableData,
              data: payments.map((payment) {
                return [
                  payment['method'] == 'Bank'
                      ? 'Bank: ${payment['bankName'] ?? 'Bank'}'
                      : payment['method'],
                  'Rs ${_parseToDouble(payment['amount']).toStringAsFixed(2)}',
                  DateFormat('yyyy-MM-dd – HH:mm').format(_parsePaymentDate(payment['date'])),
                  payment['description'] ?? 'N/A',
                ];
              }).toList(),
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 14, // Increased header font size
              ),
              cellStyle: const pw.TextStyle(
                fontSize: 12, // Increased cell font size from 10 to 12
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
            ),
  
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Spacer(),
            // Footer section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Image(footerLogo, width: 20, height: 20), // Footer logo
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Dev Valley Software House',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Contact: 0303-4889663',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
            ),
          ],
        ),
      );
  
      // Print the PDF
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    }
  
    Future<Uint8List?> _pickImage(BuildContext context) async {
      Uint8List? imageBytes;
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
  
      if (kIsWeb) {
        // For web, use file_picker
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
  
        if (result != null && result.files.isNotEmpty) {
          imageBytes = result.files.first.bytes;
        }
      } else {
        // For mobile, show source selection dialog
        final ImagePicker _picker = ImagePicker();
  
        // Show dialog to choose camera or gallery
        final ImageSource? source = await showDialog<ImageSource>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(languageProvider.isEnglish ? 'Select Source' : 'ذریعہ منتخب کریں'),
            actions: [
              TextButton(
                child: Text(languageProvider.isEnglish ? 'Camera' : 'کیمرہ'),
                onPressed: () => Navigator.pop(context, ImageSource.camera),
              ),
              TextButton(
                child: Text(languageProvider.isEnglish ? 'Gallery' : 'گیلری'),
                onPressed: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
  
        if (source == null) return null; // User canceled
  
        XFile? pickedFile = await _picker.pickImage(source: source);
        if (pickedFile != null) {
          final file = File(pickedFile.path);
          imageBytes = await file.readAsBytes();
        }
      }
  
      return imageBytes;
    }
  
    Future<Map<String, dynamic>?> _selectBank(BuildContext context) async {
      if (_cachedBanks.isEmpty) {
        final bankSnapshot = await FirebaseDatabase.instance.ref('banks').once();
        if (bankSnapshot.snapshot.value == null) return null;
  
        final banks = bankSnapshot.snapshot.value as Map<dynamic, dynamic>;
        _cachedBanks = banks.entries.map((e) => {
          'id': e.key,
          'name': e.value['name'],
          'balance': e.value['balance']
        }).toList();
      }
  
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      Map<String, dynamic>? selectedBank;
  
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Select Bank' : 'بینک منتخب کریں'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _cachedBanks.length,
              itemBuilder: (context, index) {
                final bankData = _cachedBanks[index];
                final bankName = bankData['name'];
  
                // Find matching bank from pakistaniBanks list
                Bank? matchedBank = pakistaniBanks.firstWhere(
                      (b) => b.name.toLowerCase() == bankName.toLowerCase(),
                  orElse: () => Bank(
                      name: bankName,
                      iconPath: 'assets/default_bank.png'
                  ),
                );
  
                return Card(
                  margin: EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Image.asset(
                      matchedBank.iconPath,
                      width: 40,
                      height: 40,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.account_balance, size: 40);
                      },
                    ),
                    title: Text(
                      bankName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    // subtitle: Text(
                    //   '${languageProvider.isEnglish ? "Balance" : "بیلنس"}: ${bankData['balance']} Rs',
                    // ),
                    onTap: () {
                      selectedBank = {
                        'id': bankData['id'],
                        'name': bankName,
                        'balance': bankData['balance']
                      };
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
            ),
          ],
        ),
      );
  
      return selectedBank;
    }
  
    Future<void> _showFilledPaymentDialog(
        Map<String, dynamic> filled,
        FilledProvider filledProvider,
        LanguageProvider languageProvider,
        )
    async {
      String? selectedPaymentMethod;
      _paymentController.clear();
      bool _isPaymentButtonPressed = false;
      String? _description;
      Uint8List? _imageBytes;
      DateTime _selectedPaymentDate = DateTime.now();
  
      // Add these controllers and variables for cheque payments
      TextEditingController _chequeNumberController = TextEditingController();
      DateTime? _selectedChequeDate;
      String? _selectedChequeBankId;
      String? _selectedChequeBankName;
  
      await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(languageProvider.isEnglish ? 'Pay Filled' : 'انوائس کی رقم ادا کریں'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Payment date selection
                      ListTile(
                        title: Text(languageProvider.isEnglish
                            ? 'Payment Date: ${DateFormat('yyyy-MM-dd – HH:mm').format(_selectedPaymentDate)}'
                            : 'ادائیگی کی تاریخ: ${DateFormat('yyyy-MM-dd – HH:mm').format(_selectedPaymentDate)}'),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: _selectedPaymentDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (pickedDate != null) {
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(_selectedPaymentDate),
                            );
                            if (pickedTime != null) {
                              setState(() {
                                _selectedPaymentDate = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                              });
                            }
                          }
                        },
                      ),
  
                      // Payment method dropdown
                      DropdownButtonFormField<String>(
                        value: selectedPaymentMethod,
                        items: [
                          DropdownMenuItem(
                            value: 'Cash',
                            child: Text(languageProvider.isEnglish ? 'Cash' : 'نقدی'),
                          ),
                          DropdownMenuItem(
                            value: 'Online',
                            child: Text(languageProvider.isEnglish ? 'Online' : 'آن لائن'),
                          ),
                          // DropdownMenuItem(
                          //   value: 'Check',
                          //   child: Text(languageProvider.isEnglish ? 'Check' : 'چیک'),
                          // ),
                          DropdownMenuItem(
                            value: 'Cheque', // Changed from 'Check'
                            child: Text(languageProvider.isEnglish ? 'Cheque' : 'چیک'),
                          ),
                          DropdownMenuItem(
                            value: 'Bank',
                            child: Text(languageProvider.isEnglish ? 'Bank' : 'بینک'),
                          ),
                          DropdownMenuItem(
                            value: 'Slip',
                            child: Text(languageProvider.isEnglish ? 'Slip' : 'پرچی'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedPaymentMethod = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish ? 'Select Payment Method' : 'ادائیگی کا طریقہ منتخب کریں',
                          border: const OutlineInputBorder(),
                        ),
                      ),
  
                      // Cheque payment fields (only shown when Check is selected)
                      if (selectedPaymentMethod == 'Cheque') ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _chequeNumberController,
                          decoration: InputDecoration(
                            labelText: languageProvider.isEnglish ? 'Cheque Number' : 'چیک نمبر',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          title: Text(
                            _selectedChequeDate == null
                                ? (languageProvider.isEnglish
                                ? 'Select Cheque Date'
                                : 'چیک کی تاریخ منتخب کریں')
                                : DateFormat('yyyy-MM-dd').format(_selectedChequeDate!),
                          ),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (pickedDate != null) {
                              setState(() => _selectedChequeDate = pickedDate);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            title: Text(_selectedChequeBankName ??
                                (languageProvider.isEnglish
                                    ? 'Select Bank'
                                    : 'بینک منتخب کریں')),
                            trailing: const Icon(Icons.arrow_drop_down),
                            onTap: () async {
                              final selectedBank = await _selectBank(context);
                              if (selectedBank != null) {
                                setState(() {
                                  _selectedChequeBankId = selectedBank['id'];
                                  _selectedChequeBankName = selectedBank['name'];
                                });
                              }
                            },
                          ),
                        ),
                      ],
  
                      // Bank payment fields (only shown when Bank is selected)
                      if (selectedPaymentMethod == 'Bank') ...[
                        const SizedBox(height: 16),
                        Card(
                          child: ListTile(
                            title: Text(_selectedBankName ??
                                (languageProvider.isEnglish
                                    ? 'Select Bank'
                                    : 'بینک منتخب کریں')),
                            trailing: const Icon(Icons.arrow_drop_down),
                            onTap: () async {
                              final selectedBank = await _selectBank(context);
                              if (selectedBank != null) {
                                setState(() {
                                  _selectedBankId = selectedBank['id'];
                                  _selectedBankName = selectedBank['name'];
                                });
                              }
                            },
                          ),
                        ),
                      ],
  
                      // Common fields for all payment methods
                      const SizedBox(height: 16),
                      TextField(
                        controller: _paymentController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish ? 'Enter Payment Amount' : 'رقم لکھیں',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => _description = value,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish ? 'Description' : 'تفصیل',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          Uint8List? imageBytes = await _pickImage(context);
                          if (imageBytes != null) {
                            setState(() => _imageBytes = imageBytes);
                          }
                        },
                        child: Text(languageProvider.isEnglish ? 'Pick Image' : 'تصویر اپ لوڈ کریں'),
                      ),
                      if (_imageBytes != null)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          height: 100,
                          width: 100,
                          child: Image.memory(_imageBytes!),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(languageProvider.isEnglish ? 'Cancel' : 'انکار'),
                  ),
                  TextButton(
                    onPressed: _isPaymentButtonPressed
                        ? null
                        : () async {
                      setState(() => _isPaymentButtonPressed = true);
  
                      // Validate inputs
                      if (selectedPaymentMethod == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please select a payment method.'
                              : 'براہ کرم ادائیگی کا طریقہ منتخب کریں۔')),
                        );
                        setState(() => _isPaymentButtonPressed = false);
                        return;
                      }
  
                      final amount = double.tryParse(_paymentController.text);
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please enter a valid payment amount.'
                              : 'براہ کرم ایک درست رقم درج کریں۔')),
                        );
                        setState(() => _isPaymentButtonPressed = false);
                        return;
                      }
  
                      // Validate cheque-specific fields
                      if (selectedPaymentMethod == 'Cheque') {
                        if (_selectedChequeBankId == null || _selectedChequeBankName == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(languageProvider.isEnglish
                                ? 'Please select a bank for the cheque'
                                : 'براہ کرم چیک کے لیے بینک منتخب کریں')),
                          );
                          setState(() => _isPaymentButtonPressed = false);
                          return;
                        }
                        if (_chequeNumberController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(languageProvider.isEnglish
                                ? 'Please enter cheque number'
                                : 'براہ کرم چیک نمبر درج کریں')),
                          );
                          setState(() => _isPaymentButtonPressed = false);
                          return;
                        }
                        if (_selectedChequeDate == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(languageProvider.isEnglish
                                ? 'Please select cheque date'
                                : 'براہ کرم چیک کی تاریخ منتخب کریں')),
                          );
                          setState(() => _isPaymentButtonPressed = false);
                          return;
                        }
                      }
  
                      // Validate bank-specific fields
                      if (selectedPaymentMethod == 'Bank' && (_selectedBankId == null || _selectedBankName == null)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please select a bank'
                              : 'براہ کرم بینک منتخب کریں')),
                        );
                        setState(() => _isPaymentButtonPressed = false);
                        return;
                      }
  
                      try {
                        await filledProvider.payFilledWithSeparateMethod(
                          context,
                          filled['filledNumber'],
                          amount,
                          selectedPaymentMethod!,
                          description: _description,
                          imageBytes: _imageBytes,
                          paymentDate: _selectedPaymentDate,
                          bankId: _selectedBankId,
                          bankName: _selectedBankName,
                          chequeNumber: _chequeNumberController.text,
                          chequeDate: _selectedChequeDate,
                          chequeBankId: _selectedChequeBankId,
                          chequeBankName: _selectedChequeBankName,
                        );
                        Navigator.of(context).pop();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${e.toString()}')),
                        );
                      } finally {
                        setState(() => _isPaymentButtonPressed = false);
                      }
                    },
                    child: Text(languageProvider.isEnglish ? 'Pay' : 'رقم ادا کریں'),
                  ),
                ],
              );
            },
          );
        },
      );
    }
  
    void onPaymentPressed(Map<String, dynamic> filled) {
      // At the start of both methods
      // if (filled == null) return;
      if (filled['filledNumber'] == null || filled['customerId'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot process payment - invalid filled data')),
        );
        return;
      }
      final filledProvider = Provider.of<FilledProvider>(context, listen: false);
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      _showFilledPaymentDialog(filled, filledProvider, languageProvider);
    }
  
    void onViewPayments(Map<String, dynamic> filled) {
      // At the start of both methods
      // if (filled == null) return;
      // Similar null check
      if (filled == null || filled['filledNumber'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot view payments - invalid filled data')),
        );
        return;
      }
      _showPaymentDetails(filled);
    }
  
    Future<pw.MemoryImage> _createTexttoImage(String text) async {
      const double scaleFactor = 1.5;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromPoints(
          const Offset(0, 0),
          const Offset(500 * scaleFactor, 50 * scaleFactor),
        ),
      );
  
      final paint = Paint()..color = Colors.black;
      final textStyle = const TextStyle(
        fontSize: 13 * scaleFactor,
        fontFamily: 'JameelNoori',
        color: Colors.black,
        fontWeight: FontWeight.bold,
      );
  
      final textSpan = TextSpan(text: text, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.left,
        textDirection: ui.TextDirection.ltr,
      );
  
      textPainter.layout();
      textPainter.paint(canvas, const Offset(0, 0));
  
      final picture = recorder.endRecording();
      final img = await picture.toImage(
        (textPainter.width * scaleFactor).toInt(),
        (textPainter.height * scaleFactor).toInt(),
      );
  
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();
  
      return pw.MemoryImage(buffer);
    }
  
  
    @override
    void initState() {
      super.initState();
      _fetchItems();
  
      _currentFilled = widget.filled ?? {
        'filledNumber': null,
        'customerId': '',
        'customerName': '',
        'referenceNumber': '',
        'items': [],
        'subtotal': 0.0,
        'discount': 0.0,
        'grandTotal': 0.0,
        'mazdoori': 0.0,
        'paymentType': 'instant',
        'paymentMethod': null,
        'isFromQuotation': false,
        'createdAt': DateTime.now().toIso8601String(),
      };
      _filledId = _currentFilled!['filledNumber']?.toString() ?? '';
      _isReadOnly = widget.filled != null && widget.filled!['filledNumber'] != null;

      // Initialize date controller
      if (widget.filled != null && widget.filled!['createdAt'] != null) {
        // Parse the existing date
        DateTime filledDate = DateTime.parse(widget.filled!['createdAt']);
        _dateController.text = DateFormat('yyyy-MM-dd').format(filledDate);
      } else {
        // Set to current date for new invoices
        _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }

      // Safe controller initialization
      _mazdooriController.text = (_currentFilled!['mazdoori'] as num?)?.toStringAsFixed(2) ?? '0.00';
      _discountController.text = (_currentFilled!['discount'] as num?)?.toStringAsFixed(2) ?? '0.00';
      _referenceController.text = _currentFilled!['referenceNumber']?.toString() ?? '';
  
      // Payment type handling
      _paymentType = _currentFilled!['paymentType']?.toString() ?? 'instant';
      _instantPaymentMethod = _currentFilled!['paymentMethod']?.toString();
  
      // Initialize customer provider with null checks
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      customerProvider.fetchCustomers().then((_) {
        final customerId = _currentFilled!['customerId']?.toString();
        if (customerId != null && customerId.isNotEmpty) {
          final customer = customerProvider.customers.firstWhere(
                (c) => c.id == customerId,
            orElse: () => Customer(id: '', name: 'N/A', phone: '', address: ''),
          );
          setState(() {
            _selectedCustomerId = customer.id;
            _selectedCustomerName = customer.name;
          });
          _fetchRemainingBalance();
        }
      });
  
      // Initialize rows safely
      _initializeRows();
    }
  
    void _initializeRows() {
      final items = _currentFilled!['items'] as List?;
  
      if (items != null && items.isNotEmpty) {
        _filledRows = items.map((item) {
          final itemMap = item as Map? ?? {};
          return {
            'itemName': itemMap['itemName']?.toString() ?? '',
            'rate': (itemMap['rate'] as num?)?.toDouble() ?? 0.0,
            'qty': (itemMap['qty'] as num?)?.toDouble() ?? 0.0,
            'initialQty': (itemMap['qty'] as num?)?.toDouble() ?? 0.0,
            'description': itemMap['description']?.toString() ?? '',
            'total': (itemMap['total'] as num?)?.toDouble() ?? 0.0,
            'itemNameController': TextEditingController(text: itemMap['itemName']?.toString()),
            'rateController': TextEditingController(text: (itemMap['rate'] as num?)?.toString() ?? '0.0'),
            'qtyController': TextEditingController(text: (itemMap['qty'] as num?)?.toString() ?? '0.0'),
            'descriptionController': TextEditingController(text: itemMap['description']?.toString() ?? ''),
          };
        }).toList();
      } else {
        _filledRows = [{
          'total': 0.0,
          'rate': 0.0,
          'qty': 0.0,
          'description': '',
          'itemName': '',
          'itemNameController': TextEditingController(),
          'rateController': TextEditingController(),
          'qtyController': TextEditingController(),
          'descriptionController': TextEditingController(),
        }];
      }
      _calculateInitialTotals();

    }
  
    @override
    void dispose() {
      for (var row in _filledRows) {
        row['itemNameController']?.dispose(); // Add this
        row['rateController']?.dispose();
        row['qtyController']?.dispose();
        row['descriptionController']?.dispose();
        row['rateController']?.dispose();
      }
      _discountController.dispose(); // Dispose discount controller
      _customerController.dispose();
      _dateController.dispose();
      _mazdooriController.dispose();
      _referenceController.dispose();
      super.dispose();
    }
  

    @override
    Widget build(BuildContext context) {
      final languageProvider = Provider.of<LanguageProvider>(context);
      final screenWidth = MediaQuery.of(context).size.width;
      final isWeb = screenWidth > 768;
      final isTablet = screenWidth > 480 && screenWidth <= 768;
  
      return FutureBuilder(
        future: Provider.of<CustomerProvider>(context, listen: false).fetchCustomers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            return const Center(child: CircularProgressIndicator());
          }
  
          return Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: _buildAppBar(context, languageProvider),
            body: ResponsiveLayout(
              mobile: _buildMobileLayout(context, languageProvider),
              tablet: _buildTabletLayout(context, languageProvider),
              desktop: _buildDesktopLayout(context, languageProvider),
            ),
          );
        },
      );
    }
  
    PreferredSizeWidget _buildAppBar(BuildContext context, LanguageProvider languageProvider) {
      return AppBar(
        elevation: 0,
        title: Text(
          _isReadOnly
              ? (languageProvider.isEnglish ? 'Update Invoice' : 'انوائس کو اپ ڈیٹ کریں')
              : (languageProvider.isEnglish ? 'Create Invoice' : 'انوائس بنائیں'),
          style: const TextStyle(
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
          _buildAppBarAction(
            icon: Icons.print_outlined,
            onPressed: () async {
              try {
                if (_selectedCustomerId == null) {
                  _showSnackBar(
                      context,
                      languageProvider.isEnglish
                          ? 'Please select a customer first'
                          : 'براہ کرم پہلے ایک گاہک منتخب کریں'
                  );
                  return;
                }
                await _generateAndPrintPDF();
              } catch (e) {
                _showSnackBar(
                    context,
                    languageProvider.isEnglish
                        ? 'Printing error: ${e.toString()}'
                        : 'پرنٹنگ کی خرابی: ${e.toString()}'
                );
              }
            },
          ),
          // _buildAppBarAction(
          //   icon: Icons.save_outlined,
          //   onPressed: () async {
          //     final filledNumber = widget.filled?['filledNumber']?.toString() ??
          //         (await Provider.of<FilledProvider>(context, listen: false).getNextFilledNumber()).toString();
          //     await _savePDF(filledNumber);
          //   },
          // ),
          // _buildAppBarAction(
          //   icon: Icons.share_outlined,
          //   onPressed: () async {
          //     final filledNumber = widget.filled?['filledNumber']?.toString() ??
          //         (await Provider.of<FilledProvider>(context, listen: false).getNextFilledNumber()).toString();
          //     await _sharePDFViaWhatsApp(filledNumber);
          //   },
          // ),
        ],
      );
    }
  
    Widget _buildAppBarAction({
      required IconData icon,
      required VoidCallback onPressed,
    })
    {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Material(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }
  
    Widget _buildMobileLayout(BuildContext context, LanguageProvider languageProvider) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderSection(context, languageProvider, isMobile: true),
            const SizedBox(height: 24),
            _buildCustomerSection(context, languageProvider),
            const SizedBox(height: 24),
            _buildItemsSection(context, languageProvider, isMobile: true),
            const SizedBox(height: 24),
            _buildPaymentSection(context, languageProvider),
            const SizedBox(height: 24),
            _buildTotalsSection(context, languageProvider),
            const SizedBox(height: 24),
            _buildSaveButton(context, languageProvider),
          ],
        ),
      );
    }
  
    Widget _buildTabletLayout(BuildContext context, LanguageProvider languageProvider) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderSection(context, languageProvider, isMobile: false),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildCustomerSection(context, languageProvider),
                      const SizedBox(height: 24),
                      _buildItemsSection(context, languageProvider, isMobile: false),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      _buildPaymentSection(context, languageProvider),
                      const SizedBox(height: 24),
                      _buildTotalsSection(context, languageProvider),
                      const SizedBox(height: 24),
                      _buildSaveButton(context, languageProvider),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  
    Widget _buildDesktopLayout(BuildContext context, LanguageProvider languageProvider) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderSection(context, languageProvider, isMobile: false),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          _buildCustomerSection(context, languageProvider),
                          const SizedBox(height: 32),
                          _buildItemsSection(context, languageProvider, isMobile: false),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        children: [
                          _buildPaymentSection(context, languageProvider),
                          const SizedBox(height: 24),
                          _buildTotalsSection(context, languageProvider),
                          const SizedBox(height: 24),
                          _buildSaveButton(context, languageProvider),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
  
    Widget _buildHeaderSection(BuildContext context, LanguageProvider languageProvider, {required bool isMobile}) {
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
                    languageProvider.isEnglish ? 'Invoice Details' : 'انوائس کی تفصیلات',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (isMobile) ...[
                _buildTextField(
                  controller: _referenceController,
                  label: languageProvider.isEnglish ? 'Reference Number' : 'ریفرنس نمبر',
                  icon: Icons.tag,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _dateController,
                  label: languageProvider.isEnglish ? 'Date' : 'تاریخ',
                  icon: Icons.calendar_today,
                  readOnly: true,
                  onTap: () => _selectDate(context),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _referenceController,
                        label: languageProvider.isEnglish ? 'Reference Number' : 'ریفرنس نمبر',
                        icon: Icons.tag,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _dateController,
                        label: languageProvider.isEnglish ? 'Date' : 'تاریخ',
                        icon: Icons.calendar_today,
                        readOnly: true,
                        onTap: () => _selectDate(context),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }
  
    Widget _buildCustomerSection(BuildContext context, LanguageProvider languageProvider) {
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
                  Icon(Icons.person_outline, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 8),
                  Text(
                    languageProvider.isEnglish ? 'Customer Information' : 'کسٹمر کی معلومات',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Consumer<CustomerProvider>(
                builder: (context, customerProvider, _) {
                  if (customerProvider.customers.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
  
                  return Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Autocomplete<Customer>(
                          initialValue: TextEditingValue(text: _selectedCustomerName ?? ''),
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<Customer>.empty();
                            }
                            return customerProvider.customers.where((Customer customer) {
                              return customer.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                            });
                          },
                          displayStringForOption: (Customer customer) => customer.name,
                          fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
                              FocusNode focusNode, VoidCallback onFieldSubmitted) {
                            _customerController.text = _selectedCustomerName ?? '';
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: languageProvider.isEnglish ? 'Choose a customer' : 'ایک کسٹمر منتخب کریں',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                                prefixIcon: Icon(Icons.search, color: Colors.blue[600]),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _selectedCustomerId = null;
                                  _selectedCustomerName = value;
                                });
                              },
                            );
                          },
                          onSelected: (Customer selectedCustomer) {
                            setState(() {
                              _selectedCustomerId = selectedCustomer.id;
                              _selectedCustomerName = selectedCustomer.name;
                              _customerController.text = selectedCustomer.name;
                            });
                            _fetchCustomerPrices(selectedCustomer.id);
                            _fetchRemainingBalance();
                          },
                          optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Customer> onSelected,
                              Iterable<Customer> options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4.0,
                                child: Container(
                                  width: MediaQuery.of(context).size.width * 0.9,
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    itemCount: options.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      final Customer customer = options.elementAt(index);
                                      return ListTile(
                                        title: Text(customer.name),
                                        onTap: () => onSelected(customer),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedCustomerName != null)
                        _buildInfoRow(
                          languageProvider.isEnglish ? 'Selected Customer:' : 'منتخب کسٹمر:',
                          _selectedCustomerName!,
                          icon: Icons.person,
                        ),
                      if (_remainingBalance != null)
                        _buildInfoRow(
                          languageProvider.isEnglish ? 'Remaining Balance:' : 'بقایا رقم:',
                          _remainingBalance!.toStringAsFixed(2),
                          icon: Icons.account_balance_wallet,
                          color: _remainingBalance! > 0 ? Colors.red : Colors.green,
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
  
    Widget _buildItemsSection(BuildContext context, LanguageProvider languageProvider, {required bool isMobile}) {
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
                        languageProvider.isEnglish ? 'Items' : 'آئٹمز',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _addNewRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(languageProvider.isEnglish ? 'Add Item' : 'آئٹم شامل کریں'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_filledRows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        languageProvider.isEnglish ? 'No items added yet' : 'ابھی تک کوئی آئٹم شامل نہیں',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filledRows.length,
                  itemBuilder: (context, index) => _buildItemCard(context, languageProvider, index, isMobile),
                ),
            ],
          ),
        ),
      );
    }
  
    Widget _buildItemCard(BuildContext context, LanguageProvider languageProvider, int index, bool isMobile) {
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
                    '${languageProvider.isEnglish ? 'Item' : 'آئٹم'} ${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _deleteRow(index),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CustomAutocomplete(
              items: _items,
              controller: _filledRows[index]['itemNameController'],
              onSelected: (Item selectedItem) {
                final customerPrice = _selectedCustomerId != null
                    ? (_customerItemPrices[selectedItem.id]?[_selectedCustomerId!] ?? selectedItem.costPrice)
                    : selectedItem.costPrice;
  
                setState(() {
                  _filledRows[index]['itemId'] = selectedItem.id;
                  _filledRows[index]['itemName'] = selectedItem.itemName;
                  _filledRows[index]['rate'] = customerPrice;
                  _filledRows[index]['rateController'].text = customerPrice.toString();
                  _filledRows[index]['itemNameController'].text = selectedItem.itemName;
                });
              },
              selectedCustomerId: _selectedCustomerId,
              customerItemPrices: _customerItemPrices,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _filledRows[index]['descriptionController'],
              label: languageProvider.isEnglish ? 'Description' : 'تفصیل',
              icon: Icons.description,
              maxLines: 2,
              onChanged: (value) => _updateRow(index, 'description', value),
            ),
            const SizedBox(height: 12),
            if (isMobile) ...[
              _buildTextField(
                controller: _filledRows[index]['qtyController'],
                label: languageProvider.isEnglish ? 'Quantity' : 'مقدار',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                onChanged: (value) => _updateRow(index, 'qty', double.tryParse(value) ?? 0.0),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _filledRows[index]['rateController'],
                label: languageProvider.isEnglish ? 'Rate' : 'ریٹ',
                icon: Icons.attach_money,
                keyboardType: TextInputType.number,
                onChanged: (value) => _updateRow(index, 'rate', double.tryParse(value) ?? 0.0),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: TextEditingController(
                  text: (_filledRows[index]['total'] ?? 0.0).toStringAsFixed(2),
                ),
                label: languageProvider.isEnglish ? 'Total' : 'کل',
                icon: Icons.calculate,
                readOnly: true,
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _filledRows[index]['qtyController'],
                      label: languageProvider.isEnglish ? 'Quantity' : 'مقدار',
                      icon: Icons.numbers,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => _updateRow(index, 'qty', double.tryParse(value) ?? 0.0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _filledRows[index]['rateController'],
                      label: languageProvider.isEnglish ? 'Rate' : 'ریٹ',
                      icon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => _updateRow(index, 'rate', double.tryParse(value) ?? 0.0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: TextEditingController(
                        text: (_filledRows[index]['total'] ?? 0.0).toStringAsFixed(2),
                      ),
                      label: languageProvider.isEnglish ? 'Total' : 'کل',
                      icon: Icons.calculate,
                      readOnly: true,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }
  
    Widget _buildPaymentSection(BuildContext context, LanguageProvider languageProvider) {
      final _formKey = GlobalKey<FormState>();
  
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
                  Icon(Icons.payment_outlined, color: Colors.purple[700], size: 24),
                  const SizedBox(width: 8),
                  Text(
                    languageProvider.isEnglish ? 'Payment & Discount' : 'ادائیگی اور رعایت',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _discountController,
                label: languageProvider.isEnglish ? 'Discount Amount' : 'رعایت کی رقم',
                icon: Icons.money_off,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    _discount = double.tryParse(value) ?? 0.0;
                    _calculateInitialTotals(); // Add this
                  });
                  double parsedDiscount = double.tryParse(value) ?? 0.0;
                  if (parsedDiscount > _calculateSubtotal()) {
                    _discount = _calculateSubtotal();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            languageProvider.isEnglish
                                ? 'Discount cannot be greater than subtotal'
                                : 'رعایت کل رقم سے زیادہ نہیں ہو سکتی'
                        ),
                      ),
                    );
                  } else {
                    _discount = parsedDiscount;
                  }

                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _mazdooriController,
                label: languageProvider.isEnglish ? 'Labour Charges' : 'مزدوری کی فیس',
                icon: Icons.construction,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    _mazdoori = double.tryParse(value) ?? 0.0;
                    _calculateInitialTotals(); // Add this

                  });
                },
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      languageProvider.isEnglish ? 'Payment Type:' : 'ادائیگی کی قسم:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              RadioListTile<String>(
                                value: 'instant',
                                groupValue: _paymentType,
                                title: Text(languageProvider.isEnglish ? 'Instant Payment' : 'فوری ادائیگی'),
                                onChanged: (value) {
                                  setState(() {
                                    _paymentType = value!;
                                    _instantPaymentMethod = null;
                                  });
                                },
                              ),
                              RadioListTile<String>(
                                value: 'udhaar',
                                groupValue: _paymentType,
                                title: Text(languageProvider.isEnglish ? 'Udhaar Payment' : 'ادھار ادائیگی'),
                                onChanged: (value) {
                                  setState(() {
                                    _paymentType = value!;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        if (_paymentType == 'instant')
                          Expanded(
                            child: Column(
                              children: [
                                RadioListTile<String>(
                                  value: 'cash',
                                  groupValue: _instantPaymentMethod,
                                  title: Text(languageProvider.isEnglish ? 'Cash Payment' : 'نقد ادائیگی'),
                                  onChanged: (value) {
                                    setState(() {
                                      _instantPaymentMethod = value!;
                                    });
                                  },
                                ),
                                RadioListTile<String>(
                                  value: 'online',
                                  groupValue: _instantPaymentMethod,
                                  title: Text(languageProvider.isEnglish ? 'Online Transfer' : 'آن لائن ٹرانسفر'),
                                  onChanged: (value) {
                                    setState(() {
                                      _instantPaymentMethod = value!;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (_paymentType.isEmpty)
                      Text(
                        languageProvider.isEnglish
                            ? 'Please select a payment type'
                            : 'براہ کرم ادائیگی کی قسم منتخب کریں',
                        style: const TextStyle(color: Colors.red),
                      ),
                    if (_paymentType == 'instant' && (_instantPaymentMethod == null || _instantPaymentMethod!.isEmpty))
                      Text(
                        languageProvider.isEnglish
                            ? 'Please select an instant payment method'
                            : 'براہ کرم فوری ادائیگی کا طریقہ منتخب کریں',
                        style: const TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  

    Widget _buildTotalsSection(BuildContext context, LanguageProvider languageProvider) {
      double subtotal = _calculateSubtotal();
      double grandTotal = _calculateGrandTotal();

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
                    languageProvider.isEnglish ? 'Summary' : 'خلاصہ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTotalRow(
                languageProvider.isEnglish ? 'Subtotal:' : 'سب ٹوٹل:',
                subtotal.toStringAsFixed(2),
              ),
              const SizedBox(height: 8),
              _buildTotalRow(
                languageProvider.isEnglish ? 'Discount:' : 'رعایت:',
                '- ${_discount.toStringAsFixed(2)}',
                color: Colors.red[600],
              ),
              const SizedBox(height: 8),
              _buildTotalRow(
                languageProvider.isEnglish ? 'After Discount:' : 'رعایت کے بعد:',
                (subtotal - _discount).toStringAsFixed(2),
              ),
              const SizedBox(height: 8),
              _buildTotalRow(
                languageProvider.isEnglish ? 'Labour:' : 'مزدوری:',
                '+ ${_mazdoori.toStringAsFixed(2)}',
                color: Colors.green[600],
              ),
              const Divider(thickness: 2, height: 24),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildTotalRow(
                  languageProvider.isEnglish ? 'GRAND TOTAL:' : 'مجموعی کل:',
                  grandTotal.toStringAsFixed(2),
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
  
    Widget _buildSaveButton(BuildContext context, LanguageProvider languageProvider) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
                                        onPressed: _isButtonPressed
                                            ? null
                                            : () async {
                                          setState(() {
                                            _isButtonPressed = true;
                                          });
  
                                          try {
                                            // Validate reference number
                                            if (_referenceController.text.isEmpty) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    languageProvider.isEnglish
                                                        ? 'Please enter a reference number'
                                                        : 'براہ کرم رفرنس نمبر درج کریں',
                                                  ),
                                                ),
                                              );
                                              setState(() => _isButtonPressed = false);
                                              return;
                                            }
  
                                            // Validate customer selection
                                            if (_selectedCustomerId == null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    languageProvider.isEnglish
                                                        ? 'Please select a customer'
                                                        : 'براہ کرم کسٹمر منتخب کریں',
                                                  ),
                                                ),
                                              );
                                              setState(() => _isButtonPressed = false);
                                              return;
                                            }
  
                                            // Validate payment type
                                            if (_paymentType == null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    languageProvider.isEnglish
                                                        ? 'Please select a payment type'
                                                        : 'براہ کرم ادائیگی کی قسم منتخب کریں',
                                                  ),
                                                ),
                                              );
                                              setState(() => _isButtonPressed = false);
                                              return;
                                            }
  
                                            // Validate instant payment method
                                            if (_paymentType == 'instant' && _instantPaymentMethod == null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    languageProvider.isEnglish
                                                        ? 'Please select an instant payment method'
                                                        : 'براہ کرم فوری ادائیگی کا طریقہ منتخب کریں',
                                                  ),
                                                ),
                                              );
                                              setState(() => _isButtonPressed = false);
                                              return;
                                            }
  
                                            // Validate item rates
                                            for (var row in _filledRows) {
                                              if ((row['rate'] ?? 0.0) <= 0) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      languageProvider.isEnglish
                                                          ? 'Rate cannot be zero or less'
                                                          : 'ریٹ صفر یا اس سے کم نہیں ہو سکتا',
                                                    ),
                                                  ),
                                                );
                                                setState(() => _isButtonPressed = false);
                                                return;
                                              }
                                            }
  
                                            // Validate discount amount
                                            final subtotal = _calculateSubtotal();
                                            if (_discount >= subtotal) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    languageProvider.isEnglish
                                                        ? 'Discount amount cannot be greater than or equal to the subtotal'
                                                        : 'ڈسکاؤنٹ کی رقم سب ٹوٹل سے زیادہ یا اس کے برابر نہیں ہو سکتی',
                                                  ),
                                                ),
                                              );
                                              setState(() => _isButtonPressed = false);
                                              return;
                                            }
  
                                            // Check stock
                                            List<Map<String, dynamic>> insufficientItems = [];
                                            for (var row in _filledRows) {
                                              String itemName = row['itemName'] ?? '';
                                              if (itemName.isEmpty) continue;
  
                                              Item? item = _items.firstWhere(
                                                    (i) => i.itemName == itemName,
                                                orElse: () => Item(id: '', itemName: '', costPrice: 0.0, qtyOnHand: 0.0,salePrice: 0.0),
                                              );
  
                                              if (item.id.isEmpty) continue;
  
                                              double currentQty = item.qtyOnHand;
                                              double qty = row['qty'] ?? 0.0;
                                              double initialQty = row['initialQty'] ?? qty;
                                              double delta = widget.filled != null && widget.filled!['filledNumber'] != null
                                                  ? (initialQty - qty)
                                                  : -qty;
                                              double newQty = currentQty + delta;
  
                                              if (newQty < 0) {
                                                insufficientItems.add({'item': item, 'delta': delta});
                                              }
                                            }
  
                                            if (insufficientItems.isNotEmpty) {
                                              bool proceed = await showDialog(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  title: Text(Provider.of<LanguageProvider>(context, listen: false).isEnglish
                                                      ? 'Insufficient Stock'
                                                      : 'اسٹاک ناکافی'),
                                                  content: Text(
                                                    Provider.of<LanguageProvider>(context, listen: false).isEnglish
                                                        ? 'The following items will have negative stock. Do you want to proceed?'
                                                        : 'مندرجہ ذیل اشیاء کا اسٹاک منفی ہو جائے گا۔ کیا آپ آگے بڑھنا چاہتے ہیں؟',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, false),
                                                      child: Text(Provider.of<LanguageProvider>(context, listen: false).isEnglish
                                                          ? 'Cancel'
                                                          : 'منسوخ کریں'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, true),
                                                      child: Text(Provider.of<LanguageProvider>(context, listen: false).isEnglish
                                                          ? 'Proceed'
                                                          : 'آگے بڑھیں'),
                                                    ),
                                                  ],
                                                ),
                                              );
  
                                              if (!proceed) {
                                                setState(() => _isButtonPressed = false);
                                                return;
                                              }
                                            }
  
                                            final grandTotal = _calculateGrandTotal();
                                            final filledProvider = Provider.of<FilledProvider>(context, listen: false);
  
                                            // Generate filled number for new fills
                                            String filledNumber = widget.filled?['filledNumber']?.toString() ??
                                                (await filledProvider.getNextFilledNumber()).toString();
  
                                            // Prepare items
                                            final items = _filledRows.map((row) {
                                              return {
                                                'itemName': row['itemName'] ?? '',
                                                'rate': row['rate'] ?? 0.0,
                                                'qty': row['qty'] ?? 0.0,
                                                'description': row['description'] ?? '',
                                                'total': row['total'] ?? 0.0,
                                              };
                                            }).toList();
  
                                            // Prepare date
                                            final createdAt = _dateController.text.isNotEmpty
                                                ? DateTime(
                                              DateTime.parse(_dateController.text).year,
                                              DateTime.parse(_dateController.text).month,
                                              DateTime.parse(_dateController.text).day,
                                              DateTime.now().hour,
                                              DateTime.now().minute,
                                              DateTime.now().second,
                                            ).toIso8601String()
                                                : DateTime.now().toIso8601String();
  
                                            // Always save as new fill when coming from quotation
                                            if (widget.filled?['isFromQuotation'] ?? false) {
                                              await filledProvider.saveFilled(
                                                filledId: filledNumber,
                                                filledNumber: filledNumber,
                                                customerId: _selectedCustomerId!,
                                                customerName: _selectedCustomerName ?? 'Unknown Customer',
                                                subtotal: subtotal,
                                                discount: _discount,
                                                grandTotal: grandTotal,
                                                mazdoori: _mazdoori,
                                                paymentType: _paymentType,
                                                paymentMethod: _instantPaymentMethod,
                                                referenceNumber: _referenceController.text,
                                                createdAt: createdAt,
                                                items: items,
                                              );
                                            }
                                            // Update existing fill if it has a filledNumber
                                            else if (widget.filled != null && widget.filled!['filledNumber'] != null) {
                                              await filledProvider.updateFilled(
                                                filledId: filledNumber,
                                                filledNumber: filledNumber,
                                                customerId: _selectedCustomerId!,
                                                customerName: _selectedCustomerName ?? 'Unknown Customer',
                                                subtotal: subtotal,
                                                discount: _discount,
                                                grandTotal: grandTotal,
                                                mazdoori: _mazdoori,
                                                paymentType: _paymentType,
                                                referenceNumber: _referenceController.text,
                                                paymentMethod: _instantPaymentMethod,
                                                items: items,
                                                createdAt: createdAt,
                                              );
                                            }
                                            // Otherwise save as new fill
                                            else {
                                              await filledProvider.saveFilled(
                                                filledId: filledNumber,
                                                filledNumber: filledNumber,
                                                customerId: _selectedCustomerId!,
                                                customerName: _selectedCustomerName ?? 'Unknown Customer',
                                                subtotal: subtotal,
                                                discount: _discount,
                                                grandTotal: grandTotal,
                                                mazdoori: _mazdoori,
                                                paymentType: _paymentType,
                                                paymentMethod: _instantPaymentMethod,
                                                referenceNumber: _referenceController.text,
                                                createdAt: createdAt,
                                                items: items,
                                              );
                                            }
  
                                            // Update stock
                                            _updateQtyOnHand(_filledRows);
  
                                            // Update state
                                            setState(() {
                                              _currentFilled = {
                                                'id': filledNumber,
                                                'filledNumber': filledNumber,
                                                'grandTotal': grandTotal,
                                                'customerId': _selectedCustomerId!,
                                                'customerName': _selectedCustomerName ?? 'Unknown Customer',
                                                'referenceNumber': _referenceController.text,
                                                'createdAt': createdAt,
                                                'items': _filledRows,
                                                'paymentType': _paymentType,
                                              };
                                              _isSaved = true;
                                            });
  
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  widget.filled == null || widget.filled!['isFromQuotation'] ?? false
                                                      ? (languageProvider.isEnglish
                                                      ? 'Filled saved successfully'
                                                      : 'انوائس کامیابی سے محفوظ ہوگئی')
                                                      : (languageProvider.isEnglish
                                                      ? 'Filled updated successfully'
                                                      : 'انوائس کامیابی سے تبدیل ہوگئی'),
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            print('Error saving filled: $e');
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  languageProvider.isEnglish
                                                      ? 'Failed to save filled: ${e.toString()}'
                                                      : 'انوائس محفوظ کرنے میں ناکام: ${e.toString()}',
                                                ),
                                              ),
                                            );
                                          } finally {
                                            setState(() => _isButtonPressed = false);
                                          }
                                        },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[300],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                widget.filled == null || widget.filled?['isFromQuotation'] ?? false
                    ? (languageProvider.isEnglish ? 'Save Invoice' : 'انوائس محفوظ کریں')
                    : (languageProvider.isEnglish ? 'Update Invoice' : 'انوائس کو اپ ڈیٹ کریں'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if ((widget.filled != null || _currentFilled != null) && _selectedCustomerId != null)
            Row(
              children: [
                IconButton(
                  icon:  Icon(Icons.payment, color: Colors.green[600]),
                  onPressed: () {
                    if (widget.filled != null) {
                      onPaymentPressed(widget.filled!);
                    } else if (_currentFilled != null) {
                      onPaymentPressed(_currentFilled!);
                    }
                  },
                  tooltip: languageProvider.isEnglish ? 'Make Payment' : 'ادائیگی کریں',
                ),
                IconButton(
                  icon:  Icon(Icons.history, color: Colors.green[600]),
                  onPressed: () {
                    if (widget.filled != null) {
                      onViewPayments(widget.filled!);
                    } else if (_currentFilled != null) {
                      onViewPayments(_currentFilled!);
                    }
                  },
                  tooltip: languageProvider.isEnglish ? 'View Payment History' : 'ادائیگی کی تاریخ دیکھیں',
                ),
              ],
            ),
        ],
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
            borderSide: const BorderSide(color: Colors.teal, width: 2),
          ),
          filled: true,
          fillColor: readOnly ? Colors.grey[100] : Colors.grey[50],
        ),
      );
    }

    void _calculateInitialTotals() {
      // Calculate subtotal and grand total when initializing rows
      for (var row in _filledRows) {
        double rate = row['rate'] ?? 0.0;
        double qty = row['qty'] ?? 0.0;
        row['total'] = rate * qty;
      }

      // Update discount and mazdoori from controllers
      _discount = double.tryParse(_discountController.text) ?? 0.0;
      _mazdoori = double.tryParse(_mazdooriController.text) ?? 0.0;
    }
  
    Widget _buildTotalRow(String label, String value, {
      bool isBold = false,
      double fontSize = 14,
      Color? color,
    })
    {
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
  
    Widget _buildInfoRow(String label, String value, {IconData? icon, Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color ?? Colors.grey[600]),
              const SizedBox(width: 8),
            ],
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
                color: color ?? Colors.teal[700],
              ),
            ),
          ],
        ),
      );
    }
  
    void _showSnackBar(BuildContext context, String message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  
  
  }
  
  class CustomAutocomplete extends StatefulWidget {
    final List<Item> items;
    final Function(Item) onSelected;
    final TextEditingController controller;
    final bool readOnly;
    final String? selectedCustomerId;
    final Map<String, Map<String, double>> customerItemPrices;
  
    const CustomAutocomplete({
      super.key,
      required this.items,
      required this.onSelected,
      required this.controller,
      this.readOnly = false,
      this.selectedCustomerId,
      this.customerItemPrices = const {},
    });
  
    @override
    State<CustomAutocomplete> createState() => _CustomAutocompleteState();
  }
  
  class _CustomAutocompleteState extends State<CustomAutocomplete> {
    List<Item> _filteredItems = [];
    final FocusNode _focusNode = FocusNode();
  
    @override
    void initState() {
      super.initState();
      _filteredItems = widget.items;
      widget.controller.addListener(_onTextChanged);
    }
  
    void _onTextChanged() {
      setState(() {
        _filteredItems = widget.items
            .where((item) => item.itemName
            .toLowerCase()
            .contains(widget.controller.text.toLowerCase()))
            .toList();
      });
    }
  
    @override
    void dispose() {
      widget.controller.removeListener(_onTextChanged);
      _focusNode.dispose();
      super.dispose();
    }
  
    @override
    Widget build(BuildContext context) {
      return Column(
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: !widget.readOnly,
            decoration: const InputDecoration(
              labelText: 'Select Item',
              border: OutlineInputBorder(),
            ),
          ),
          if (_focusNode.hasFocus &&
              _filteredItems.isNotEmpty &&
              !widget.readOnly)
            Container(
              height: 200,
              child: ListView.builder(
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  final customerId = widget.selectedCustomerId;
                  final customerPrice = (customerId != null &&
                      (widget.customerItemPrices[item.id]?.containsKey(customerId) ?? false))
                      ? widget.customerItemPrices[item.id]![customerId]!
                      : item.salePrice;
  
                  final isSpecialPrice = customerPrice != item.salePrice;
  
                  return ListTile(
                    title: Text(item.itemName),
                    subtitle: isSpecialPrice
                        ? Text('Special Price: ${customerPrice.toStringAsFixed(2)}')
                        : null,
                    trailing: Text(
                      customerPrice.toStringAsFixed(2),
                      style: TextStyle(
                        color: isSpecialPrice ? Colors.green : Colors.black,
                        fontWeight: isSpecialPrice
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      widget.onSelected(item.copyWith(costPrice: customerPrice));
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
        ],
      );
    }
  }
