import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class StockReportPage extends StatefulWidget {
  @override
  _StockReportPageState createState() => _StockReportPageState();
}

class _StockReportPageState extends State<StockReportPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> _adjustments = [];

  @override
  void initState() {
    super.initState();
    _fetchAdjustments();
  }

  void _fetchAdjustments() async {
    final snapshot = await _database.child('qtyAdjustments').get();
    if (snapshot.exists) {
      final Map<dynamic, dynamic> adjustmentsData = snapshot.value as Map;
      final List<Map<String, dynamic>> adjustmentsList = [];

      adjustmentsData.forEach((itemKey, adjustments) {
        adjustments.forEach((adjustmentKey, adjustment) {
          adjustmentsList.add({
            'itemName': adjustment['itemName'],
            'oldQty': adjustment['oldQty'],
            'newQty': adjustment['newQty'],
            'date': adjustment['date'],
            'adjustedBy': adjustment['adjustedBy'],
          });
        });
      });

      setState(() {
        _adjustments = adjustmentsList;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Stock Adjustment Report', style: TextStyle(color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: true,//s
      ),
      body: _adjustments.isEmpty
          ? Center(child: Text('No adjustments found.'))
          : ListView.builder(
        itemCount: _adjustments.length,
        itemBuilder: (context, index) {
          final adjustment = _adjustments[index];
          return Card(
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: ListTile(
              title: Text(adjustment['itemName']),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Old Qty: ${adjustment['oldQty']}'),
                  Text('New Qty: ${adjustment['newQty']}'),
                  Text('Date: ${adjustment['date']}'),
                  // Text('Adjusted By: ${adjustment['adjustedBy']}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}