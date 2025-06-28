import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'prediction_page.dart';

class BluetoothPage extends StatefulWidget {
  @override
  _BluetoothPageState createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? notifyChar;

  void startScan() {
    scanResults.clear();

    // ✅ Correct: call static method with class name
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));

    // ✅ Correct: use static getter with class name
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    // ✅ Correct: use static method with class name
    await FlutterBluePlus.stopScan();

    await device.connect();
    setState(() {
      connectedDevice = device;
    });

    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      for (var char in service.characteristics) {
        if (char.properties.notify) {
          notifyChar = char;
          await char.setNotifyValue(true);
          char.value.listen((value) {
            String data = utf8.decode(value);
            final match = RegExp(r'R:(\d+),G:(\d+),B:(\d+)').firstMatch(data);
            if (match != null) {
              List<int> rgb = [
                int.parse(match.group(1)!),
                int.parse(match.group(2)!),
                int.parse(match.group(3)!),
              ];
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PredictionPage(rgb: rgb)),
              );
            }
          });
        }
      }
    }
  }

  Future<void> sendTestCommand() async {
    if (notifyChar != null) {
      await notifyChar!.write(utf8.encode("T")); // Send test command to ESP32
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Bluetooth ESP32')),
      body: Column(
        children: [
          ElevatedButton(onPressed: startScan, child: Text("Scan Devices")),
          ...scanResults.map(
            (r) => ListTile(
              title: Text(
                r.device.name.isNotEmpty
                    ? r.device.name
                    : r.device.id.toString(),
              ),
              onTap: () => connectToDevice(r.device),
            ),
          ),
          if (connectedDevice != null)
            Column(
              children: [
                Text("Connected to: ${connectedDevice!.name}"),
                ElevatedButton(
                  onPressed: sendTestCommand,
                  child: Text("Test RGB"),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
