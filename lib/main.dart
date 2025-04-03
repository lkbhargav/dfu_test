import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:test_dfu/models/manifest.dart';
import 'package:uuid/uuid.dart';

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
              Padding(
                padding: EdgeInsets.all(10.0),
                child: ElevatedButton(
                  onPressed: () async {
                    update();
                  },
                  child: Text('Update'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void update() async {
    try {
      final managerFactory = mcumgr.FirmwareUpdateManagerFactory();

      final updateManager = await managerFactory.getUpdateManager(deviceId);

      updateManager.setup();

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'bin'],
      );

      if (result == null || result.files.isEmpty) {
        print("ERROR: Has to select atleast one file");
        return;
      }

      final file = result.files.first;

      // file.bytes;
      final flashFileContents = await File(file.path!).readAsBytes();

      var firmwareImages = await getFiles(flashFileContents);

      updateManager.update(firmwareImages);

      updateManager.updateStateStream?.listen((event) {
        if (event == mcumgr.FirmwareUpgradeState.success) {
          print("Update Success");
        } else {
          print(event);
        }
      });

      updateManager.progressStream.listen((event) {
        print("${event.bytesSent} / ${event.imageSize}} bytes sent");
      });

      updateManager.logger.logMessageStream
          .where((log) => log.level.rawValue > 1) // filter out debug messages
          .listen((log) {
            print(log.message);
          });
    } catch (e) {
      print(e);
    }
  }

  Future<List<mcumgr.Image>> getFiles(Uint8List fileContent) async {
    final prefix = 'firmware_${Uuid().v4()}';
    final systemTempDir = await path_provider.getTemporaryDirectory();

    final tempDir = Directory('${systemTempDir.path}/$prefix');
    await tempDir.create();

    final firmwareFileData = fileContent;
    final firmwareFile = File('${tempDir.path}/firmware.zip');
    await firmwareFile.writeAsBytes(firmwareFileData);

    final destinationDir = Directory('${tempDir.path}/firmware');
    await destinationDir.create();
    try {
      await ZipFile.extractToDirectory(
        zipFile: firmwareFile,
        destinationDir: destinationDir,
      );
    } catch (e) {
      throw Exception('Failed to unzip firmware');
    }

    // read manifest.json
    final manifestFile = File('${destinationDir.path}/manifest.json');
    final manifestString = await manifestFile.readAsString();
    Map<String, dynamic> manifestJson = json.decode(manifestString);
    Manifest manifest;

    print(manifestJson);

    try {
      manifest = Manifest.fromJson(manifestJson);
    } catch (e) {
      throw Exception('Failed to parse manifest.json');
    }

    List<mcumgr.Image> firmwareImages = [];
    for (final file in manifest.files) {
      final firmwareFile = File('${destinationDir.path}/${file.file}');
      final firmwareFileData = await firmwareFile.readAsBytes();
      final image = mcumgr.Image(image: file.image, data: firmwareFileData);

      print("OOOO: ${firmwareFileData.length}");

      firmwareImages.add(image);
    }

    // delete tempDir
    await tempDir.delete(recursive: true);

    return firmwareImages;
  }
}
