import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;

const deviceId = "0CE69D88-E116-A5FB-2F0C-54DF0807B3D1";

const deviceName = "Nocturnal_DFU_Test";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  BluetoothDevice? _peripheral;
  bool _isConnected = false;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OTA test app',
      home: Scaffold(
        appBar: AppBar(title: Text('OTA test app')),
        body: Center(
          child: Column(
            children: [
              Text('OTA app update'),
              ElevatedButton(
                onPressed:
                    !_isConnected
                        ? null
                        : () async {
                          print("Button pressed!");
                          update();
                        },
                child: Text('Update'),
              ),
              ElevatedButton(
                child: Text(!_isConnected ? "Connect" : "Disconnect"),
                onPressed: () async {
                  print("Connect/Disconnect!");
                  if (!_isConnected) {
                    listDevices(); // connects to the provided device
                  } else {
                    disconnect();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void update() async {
    try {
      print("0.1");

      final managerFactory = mcumgr.FirmwareUpdateManagerFactory();

      print("0.2");

      final updateManager = await managerFactory.getUpdateManager(deviceId);

      print("1 $deviceId");

      updateManager.setup();

      print("1.1");

      final data = await rootBundle.load('assets/dfu_green_flash.zip');

      print("1.2");

      final flashFileContents = data.buffer.asUint8List();

      print("2 fetched file contents ${flashFileContents.length}");

      List<mcumgr.Image> firmwareImages = [];

      final image = mcumgr.Image(image: 0, data: flashFileContents);
      firmwareImages.add(image);

      updateManager.update(firmwareImages);

      print("2.1 update started");

      updateManager.updateStateStream?.listen((event) {
        if (event == mcumgr.FirmwareUpgradeState.success) {
          print("Update Success");
        } else {
          print(event);
        }
      });

      print("3 in between streams");

      updateManager.progressStream.listen((event) {
        print("${event.bytesSent} / ${event.imageSize}} bytes sent");
      });

      print("4 in between streams 2");

      updateManager.logger.logMessageStream
          .where((log) => log.level.rawValue > 1) // filter out debug messages
          .listen((log) {
            print(log.message);
          });

      print("5 subscribed to all streams");
    } catch (e) {
      print(e);
    }
  }

  void listDevices() async {
    FlutterBluePlus.setLogLevel(LogLevel.none);
    FlutterBluePlus.setOptions(restoreState: true);

    BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

    // late StreamSubscription<BluetoothAdapterState>
    // _adapterStateStateSubscription;

    try {
      // Check bluetooth adapter state
      _adapterState = await FlutterBluePlus.adapterState.first;

      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
        state,
      ) async {
        if (state == BluetoothAdapterState.on) {
          await FlutterBluePlus.stopScan();

          // Start scanning
          _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
            // print("Scan results: $results, $deviceId");
            for (ScanResult r in results) {
              if (r.device.platformName.isEmpty) continue;
              // print("${r.device.platformName} and $deviceId");
              if (r.device.platformName.contains(deviceName)) {
                connect(r.device);
                return;
              }
            }
          });

          await FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 300),
            androidUsesFineLocation: false,
          );
        }
      });
    } catch (e) {
      print('Error initializing Bluetooth: $e');
    }
  }

  Future<bool> connect(BluetoothDevice peripheral) async {
    try {
      // Cancel scanning
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();

      // Connect to device
      await peripheral.connect(
        timeout: const Duration(seconds: 4),
        autoConnect: false,
      );

      _peripheral = peripheral;

      setState(() {
        _isConnected = true;
      });
    } catch (e) {
      print('Failed to connect: $e');
      // handleDisconnect();
      return false;
    }

    return true;
  }

  Future<void> disconnect() async {
    setState(() {
      _isConnected = false;
    });

    try {
      await _adapterStateSubscription?.cancel();
      await _scanSubscription?.cancel();

      await FlutterBluePlus.stopScan();

      if (_peripheral != null) {
        await _peripheral!.disconnect();
      }
    } catch (e) {
      print("Error cancelling subscriptions: $e");
    }
  }
}
