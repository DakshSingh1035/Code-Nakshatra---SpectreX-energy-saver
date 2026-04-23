import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const PhantomSaverApp());

class PhantomSaverApp extends StatelessWidget {
  const PhantomSaverApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050505),
        primaryColor: Colors.greenAccent,
      ),
      home: const Dashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  // Glitch fix: Start with an empty list and valid first point
  final List<FlSpot> _points = [];
  double _currentAmps = 0.0;
  bool _isRelayActive = true;
  double _costPerUnit = 7.0;
  double _totalKwhSaved = 0.0;
  bool _isConnected = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => _fetchData());
  }

  Future<void> _fetchData() async {
    try {
      final response = await http
          .get(Uri.parse('http://192.168.4.1/data'))
          .timeout(const Duration(milliseconds: 900));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isConnected = true;
          _currentAmps = (data['current'] as num).toDouble();
          _isRelayActive =
              data['relayStatus'] == 1 || data['relayStatus'] == true;

          // Time-based X axis to keep graph smooth
          double now = DateTime.now().millisecondsSinceEpoch.toDouble();

          // Safety: Only add if value is realistic (prevents glitch lines)
          if (_currentAmps >= 0 && _currentAmps < 50) {
            _points.add(FlSpot(now, _currentAmps));
          }

          if (_points.length > 30) _points.removeAt(0);

          if (!_isRelayActive) {
            // Logic: 230V * 0.05A (assumed phantom) * 1sec / 3.6M (to kWh)
            _totalKwhSaved += (230 * 0.05 * 1) / 3600000;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "PHANTOM SAVER",
          style: GoogleFonts.orbitron(letterSpacing: 2, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? Colors.greenAccent : Colors.redAccent,
              boxShadow: [
                BoxShadow(
                  color: _isConnected ? Colors.green : Colors.red,
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 25),

            // Graph Container with Glitch Protection
            Container(
              height: 250,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(15),
              ),
              child: _points.length < 2
                  ? const Center(
                      child: Text(
                        "Waiting for Data...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 5, // Set realistic Max Y for ACS712
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _points,
                            isCurved: true,
                            color: Colors.greenAccent,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.greenAccent.withOpacity(0.05),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            const SizedBox(height: 25),
            TextField(
              decoration: InputDecoration(
                labelText: "COST PER UNIT (₹)",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) =>
                  setState(() => _costPerUnit = double.tryParse(val) ?? 7.0),
            ),

            const SizedBox(height: 25),
            Row(
              children: [
                _savingsBox(
                  "ENERGY SAVED",
                  "${_totalKwhSaved.toStringAsFixed(6)} kWh",
                ),
                const SizedBox(width: 15),
                _savingsBox(
                  "MONEY SAVED",
                  "₹${(_totalKwhSaved * _costPerUnit).toStringAsFixed(4)}",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: _isRelayActive
            ? Colors.green.withOpacity(0.05)
            : Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isRelayActive ? Colors.greenAccent : Colors.redAccent,
        ),
      ),
      child: Column(
        children: [
          Icon(
            _isRelayActive ? Icons.bolt : Icons.block,
            size: 40,
            color: _isRelayActive ? Colors.greenAccent : Colors.redAccent,
          ),
          const SizedBox(height: 10),
          Text(
            _isRelayActive ? "SYSTEM ACTIVE" : "PHANTOM CUT",
            style: GoogleFonts.blackOpsOne(
              fontSize: 28,
              color: _isRelayActive ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
          Text(
            "Live: ${_currentAmps.toStringAsFixed(2)}A",
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _savingsBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.greenAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
