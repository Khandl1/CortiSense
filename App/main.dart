import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:math';

// Define placeholder UUIDs for your BLE service and characteristic.
// These must match what you define in your ESP32 firmware.
// Flutter_blue_plus expects UUIDs as strings.
const String SERVICE_UUID = 'e0e0f0f0-0000-1000-8000-00805f9b34fb';
const String CHARACTERISTIC_UUID = 'e0e0f0f1-0000-1000-8000-00805f9b34fb';

void main() {
  runApp(const CortisolApp());
}

class CortisolApp extends StatelessWidget {
  const CortisolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cortisol Concentration App',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily:
            'Inter', // Assuming 'Inter' font is available or similar system font
      ),
      home: const CortisolHomePage(),
    );
  }
}

class CortisolHomePage extends StatefulWidget {
  const CortisolHomePage({super.key});

  @override
  State<CortisolHomePage> createState() => _CortisolHomePageState();
}

class _CortisolHomePageState extends State<CortisolHomePage> {
  BluetoothDevice? _device;
  bool _isConnected = false;
  Map<String, int?> _rgbValues = {'r': null, 'g': null, 'b': null};
  double? _cortisolConcentration;
  String _statusMessage = 'Ready to connect.';
  bool _isLoading = false;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _device?.disconnect(); // Disconnect on app close
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    // Check if Bluetooth is on
    if (!(await FlutterBluePlus.isOn)) {
      setState(() {
        _statusMessage = 'Bluetooth is OFF. Please turn it ON.';
      });
      // Optionally, you can listen to state changes if the user turns it on later
      FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
        if (state == BluetoothAdapterState.on) {
          setState(() {
            _statusMessage = 'Bluetooth is ON. Ready to connect.';
          });
        }
      });
    }
  }

  double predictCortisol(int r, int g, int b) {
    // --- DUMMY ML MODEL LOGIC ---

    const double weightR = 0.1;
    const double weightG = 0.05;
    const double weightB = 0.08;
    const double bias = 10.0;
    const double scaleFactor = 1.5;

    double concentration =
        (r * weightR + g * weightG + b * weightB + bias) / scaleFactor;

    // Ensure concentration is non-negative
    concentration = max(0.0, concentration);

    concentration +=
        (Random().nextDouble() - 0.5) * 5; // Adds a small random fluctuation

    return double.parse(
      concentration.toStringAsFixed(2),
    ); // Return with 2 decimal places
  }

  /**
   * Connects to an ESP32 Bluetooth Low Energy (BLE) device.
   */
  Future<void> _connectToESP32() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Searching for ESP32 device...';
      _rgbValues = {'r': null, 'g': null, 'b': null};
      _cortisolConcentration = null;
    });

    try {
      // Check if Bluetooth is supported and enabled
      if (!(await FlutterBluePlus.isSupported)) {
        throw Exception("Bluetooth is not supported on this device.");
      }
      if (!(await FlutterBluePlus.isOn)) {
        throw Exception("Bluetooth is OFF. Please turn it ON.");
      }

      // Start scanning for devices
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen for scan results and find our device
      BluetoothDevice? foundDevice;
      final scanResults = FlutterBluePlus.scanResults
          .firstWhere(
            (results) => results.any(
              (r) =>
                  r.device.platformName.toLowerCase().contains(
                    'esp32',
                  ) || // Look for 'ESP32' in name
                  r.advertisementData.serviceUuids.contains(
                    Guid(SERVICE_UUID),
                  ), // Or check service UUID
            ),
            orElse: () => [], // If no device found within timeout
          )
          .timeout(const Duration(seconds: 10), onTimeout: () => []);

      for (ScanResult result in (await scanResults)) {
        if (result.device.platformName.toLowerCase().contains('esp32') ||
            result.advertisementData.serviceUuids.contains(
              Guid(SERVICE_UUID),
            )) {
          foundDevice = result.device;
          break;
        }
      }

      await FlutterBluePlus.stopScan();

      if (foundDevice == null) {
        throw Exception('No ESP32 device found. Make sure it\'s advertising.');
      }

      setState(() {
        _statusMessage =
            'Found device: ${foundDevice!.platformName}. Connecting...';
      });

      // Connect to the found device
      await foundDevice.connect();
      _connectionStateSubscription = foundDevice.connectionState.listen((
        BluetoothConnectionState state,
      ) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected(foundDevice!);
        }
      });

      setState(() {
        _device = foundDevice;
        _isConnected = true;
        _statusMessage = 'Connected to ${_device!.platformName}.';
      });
    } catch (e) {
      print('Bluetooth connection error: $e');
      setState(() {
        _statusMessage =
            'Connection failed: ${e.toString()}. Please try again.';
        _device = null;
        _isConnected = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /**
   * Handles device disconnection event.
   */
  void _onDisconnected(BluetoothDevice disconnectedDevice) {
    setState(() {
      _statusMessage = '${disconnectedDevice.platformName} disconnected.';
      _isConnected = false;
      _device = null;
      _rgbValues = {'r': null, 'g': null, 'b': null};
      _cortisolConcentration = null;
    });
    _connectionStateSubscription?.cancel();
  }

  /**
   * Reads RGB values from the ESP32 and predicts cortisol concentration.
   */
  Future<void> _testCortisolMeasurement() async {
    if (_device == null || !_isConnected) {
      setState(() {
        _statusMessage = 'Not connected to an ESP32 device.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Requesting RGB values...';
    });

    try {
      // Ensure the device is still connected
      if (!_device!.isConnected) {
        // Correctly using .isConnected getter
        setState(() {
          _statusMessage = 'Device is not connected. Reconnecting...';
        });
        await _device!.connect(); // Try to reconnect
        if (!_device!.isConnected) {
          // Correctly using .isConnected getter again
          throw Exception('Failed to reconnect to device.');
        }
        setState(() {
          _statusMessage = 'Reconnected.';
        });
      }

      // Discover services and characteristics
      List<BluetoothService> services = await _device!.discoverServices();
      BluetoothService? targetService;
      for (var service in services) {
        if (service.uuid == Guid(SERVICE_UUID)) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        throw Exception('Service not found on device.');
      }

      BluetoothCharacteristic? targetCharacteristic;
      for (var characteristic in targetService.characteristics) {
        if (characteristic.uuid == Guid(CHARACTERISTIC_UUID)) {
          targetCharacteristic = characteristic;
          break;
        }
      }

      if (targetCharacteristic == null) {
        throw Exception('Characteristic not found for the specified service.');
      }

      // Read the value from the characteristic
      // Expecting a List<int> with at least 3 bytes (R, G, B)
      List<int> value = await targetCharacteristic.read();

      if (value.length < 3) {
        throw Exception('Received data is too short for RGB values.');
      }

      final int r = value[0]; // First byte for Red
      final int g = value[1]; // Second byte for Green
      final int b = value[2]; // Third byte for Blue

      setState(() {
        _rgbValues = {'r': r, 'g': g, 'b': b};
        _statusMessage = 'Received RGB: R=$r, G=$g, B=$b. Analyzing...';
      });

      // Predict cortisol concentration using the dummy ML model
      final double predictedCortisol = predictCortisol(r, g, b);

      setState(() {
        _cortisolConcentration = predictedCortisol;
        _statusMessage = 'Prediction complete!';
      });
    } catch (e) {
      print('Error reading characteristic or predicting cortisol: $e');
      setState(() {
        _statusMessage = 'Error during test: ${e.toString()}';
        _rgbValues = {'r': null, 'g': null, 'b': null};
        _cortisolConcentration = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Cortisol Concentration App'),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 4,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 3,
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status Section
                Column(
                  children: [
                    Text(
                      'Status:',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _isLoading
                        ? const CircularProgressIndicator(strokeWidth: 3)
                        : Icon(
                          _isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color:
                              _isConnected
                                  ? Colors.green[600]
                                  : Colors.red[600],
                          size: 40,
                        ),
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color:
                            _statusMessage.contains('Connected')
                                ? Colors.green[600]
                                : _statusMessage.contains('failed') ||
                                    _statusMessage.contains('Error')
                                ? Colors.red[600]
                                : Colors.blue[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Action Buttons
                ElevatedButton.icon(
                  onPressed:
                      _isConnected || _isLoading ? null : _connectToESP32,
                  icon:
                      _isLoading && _statusMessage.contains('Searching')
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Icon(Icons.bluetooth),
                  label: Text(
                    _isConnected ? 'Connected to ESP32' : 'Connect to ESP32',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isConnected ? Colors.grey[400] : Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 5,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed:
                      !_isConnected || _isLoading
                          ? null
                          : _testCortisolMeasurement,
                  icon:
                      _isLoading && _statusMessage.contains('Requesting RGB')
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Icon(Icons.analytics),
                  label: Text(
                    _isLoading && _statusMessage.contains('Requesting RGB')
                        ? 'Getting RGB...'
                        : 'Test Cortisol Measurement',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        !_isConnected ? Colors.grey[400] : Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 5,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 32),

                // Measurement Results Section
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Measurement Results',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'RGB Values:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _rgbValues['r'] != null
                                    ? Text(
                                      'R: ${_rgbValues['r']}, G: ${_rgbValues['g']}, B: ${_rgbValues['b']}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                      ),
                                      textAlign: TextAlign.center,
                                    )
                                    : Text(
                                      'N/A',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'Cortisol Concentration:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _cortisolConcentration != null
                                    ? Text(
                                      '${_cortisolConcentration} µg/dL',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.purple[700],
                                      ),
                                      textAlign: TextAlign.center,
                                    )
                                    : Text(
                                      'N/A',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_rgbValues['r'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 2,
                              ),
                              color: Color.fromARGB(
                                255,
                                _rgbValues['r']!,
                                _rgbValues['g']!,
                                _rgbValues['b']!,
                              ),
                            ),
                          ),
                        ),
                    ],
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
