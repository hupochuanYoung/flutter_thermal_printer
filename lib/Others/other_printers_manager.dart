import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';

// import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_platform_interface.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

class OtherPrinterManager {
  OtherPrinterManager._privateConstructor();

  static OtherPrinterManager? _instance;

  static OtherPrinterManager get instance {
    _instance ??= OtherPrinterManager._privateConstructor();
    return _instance!;
  }

  final StreamController<List<Printer>> _devicesstream =
      StreamController<List<Printer>>.broadcast();

  Stream<List<Printer>> get devicesStream => _devicesstream.stream;
  StreamSubscription? subscription;
  final blueClassic = FlutterBlueClassic(usesFineLocation: true);

  // Track active connections
  final Map<String, BluetoothConnection> _activeBluetoothConnections = {};

  static String channelName = 'flutter_thermal_printer/events';
  EventChannel eventChannel = EventChannel(channelName);

  bool get isIos => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  // Stop scanning for BLE devices
  Future<void> stopScan({bool stopBle = true, bool stopUsb = true}) async {
    try {
      if (stopBle) {
        await subscription?.cancel();
        blueClassic.stopScan();
      }
      if (stopUsb) {
        await _usbSubscription?.cancel();
      }
    } catch (e) {
      log('Failed to stop scanning for devices $e');
    }
  }

  Future<bool> connect(Printer device) async {
    if (device.connectionType == ConnectionType.USB) {
      return await FlutterThermalPrinterPlatform.instance.connect(device);
    } else {
      try {
        return await bluetoothConnect(device.address!);
      } catch (e) {
        return false;
      }
    }
  }

  Future<bool> bluetoothConnect(String address) async {
    try {
      BluetoothConnection? bt = await blueClassic.connect(address);
      if (bt == null) return false;
      _activeBluetoothConnections[address] = bt;
      return bt.isConnected;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isConnected(Printer device) async {
    if (device.connectionType == ConnectionType.USB) {
      return await FlutterThermalPrinterPlatform.instance.isConnected(device);
    } else {
      try {
        if (_activeBluetoothConnections.containsKey(device.address!)) {
          return _activeBluetoothConnections[device.address!]!.isConnected;
        }
        return false;
      } catch (e) {
        return false;
      }
    }
  }

  Future<void> disconnect(Printer device) async {
    if (device.connectionType == ConnectionType.BLE) {
      try {
        final bt = _activeBluetoothConnections[device.address!];
        if (bt == null) return;
        await bt.close();
        _activeBluetoothConnections.remove(device.address!);
      } catch (e) {
        log('disconnect $e');
      }
    }
  }

  // Print data to BLE device
  Future<void> printData(
    Printer printer,
    List<int> bytes, {
    bool longData = false,
    bool withoutResponse = false,
  }) async {
    if (printer.connectionType == ConnectionType.USB) {
      try {
        await FlutterThermalPrinterPlatform.instance.printText(
          printer,
          Uint8List.fromList(bytes),
          path: printer.address,
        );
      } catch (e) {
        log("FlutterThermalPrinter: Unable to Print Data $e");
      }
    } else {
      try {
        BluetoothConnection? device =
            _activeBluetoothConnections[printer.address!];
        if (device == null) {
          log('Device is not connected');
          return;
        }
        if (!device.isConnected) {
          bool isConnected = await bluetoothConnect(device.address);
          if (!isConnected) {
            log('isConnected fail');
            return;
          }
        }
        device.output.add(Uint8List.fromList(bytes));
        await device.output.allSent;
        return;
      } catch (e) {
        log('Failed to print data to device $e');
      }
    }
  }

  StreamSubscription? refresher;

  final List<Printer> _devices = [];
  StreamSubscription? _usbSubscription;

  // Get Printers from BT and USB
  Future<void> getPrinters({
    List<ConnectionType> connectionTypes = const [
      ConnectionType.BLE,
      ConnectionType.USB,
    ],
    bool androidUsesFineLocation = false,
  }) async {
    if (connectionTypes.isEmpty) {
      throw Exception('No connection type provided');
    }

    if (connectionTypes.contains(ConnectionType.USB)) {
      await _getUSBPrinters();
    }

    if (connectionTypes.contains(ConnectionType.BLE)) {
      await _getBLEPrinters(androidUsesFineLocation);
    }
  }

  Future<void> _getUSBPrinters() async {
    try {
      final devices =
          await FlutterThermalPrinterPlatform.instance.startUsbScan();

      List<Printer> usbPrinters = [];
      for (var map in devices) {
        final printer = Printer(
          vendorId: map['vendorId'].toString(),
          productId: map['productId'].toString(),
          name: map['name'],
          connectionType: ConnectionType.USB,
          address: map['vendorId'].toString(),
          isConnected: map['connected'] ?? false,
        );
        printer.isConnected =
            await FlutterThermalPrinterPlatform.instance.isConnected(printer);
        usbPrinters.add(printer);
      }

      _devices.addAll(usbPrinters);
      _usbSubscription?.cancel();
      _usbSubscription = eventChannel.receiveBroadcastStream().listen((event) {
        final map = Map<String, dynamic>.from(event);
        _updateOrAddPrinter(Printer(
          vendorId: map['vendorId'].toString(),
          productId: map['productId'].toString(),
          name: map['name'],
          connectionType: ConnectionType.USB,
          address: map['vendorId'].toString(),
          isConnected: map['connected'] ?? false,
        ));
      });

      sortDevices();
    } catch (e) {
      log("$e [USB Connection]");
    }
  }

  Future<void> _getBLEPrinters(bool androidUsesFineLocation) async {
    try {
      subscription?.cancel();
      subscription = null;
      if (isIos == false) {
        if (await blueClassic.adapterStateNow != BluetoothAdapterState.on) {
          turnOnBluetooth();
        }
      } else {
        BluetoothAdapterState state = await blueClassic.adapterState.first;
        if (state == BluetoothAdapterState.off) {
          log('Bluetooth is off, turning on.');
          return;
        }
      }

      blueClassic.stopScan();
      blueClassic.startScan();

      // Get bonded devices (Android only)
      if (Platform.isAndroid) {
        final bondedDevices = await _getBLEBondedDevices();
        _devices.addAll(bondedDevices);
      }

      sortDevices();

      // Listen to scan results
      subscription = blueClassic.scanResults.listen((result) {
        BluetoothDevice bluetoothDevice = result;
        Printer printer = Printer(
          address: bluetoothDevice.address,
          name: bluetoothDevice.name,
          connectionType: ConnectionType.BLE,
          isConnected:
              _activeBluetoothConnections.containsKey(bluetoothDevice.address),
        );
        _updateOrAddPrinter(printer);
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Printer>> _getBLEBondedDevices() async {
    List<BluetoothDevice>? bondedDevices = await blueClassic.bondedDevices;
    if (bondedDevices == null) return [];
    List<Printer> printers = [];
    for (var device in bondedDevices) {
      printers.add(Printer(
        address: device.address,
        name: device.name,
        rssi: device.rssi,
        connectionType: ConnectionType.BLE,
        isConnected: _activeBluetoothConnections.containsKey(device.address),
      ));
    }

    return printers;
  }

  void _updateOrAddPrinter(Printer printer) {
    final index =
        _devices.indexWhere((device) => device.address == printer.address);
    if (index == -1) {
      _devices.add(printer);
    } else {
      _devices[index] = printer;
    }
    sortDevices();
  }

  void sortDevices() {
    _devices
        .removeWhere((element) => element.name == null || element.name == '');
    // remove items having same vendorId
    Set<String> seen = {};
    _devices.retainWhere((element) {
      String uniqueKey = '${element.vendorId}_${element.address}';
      if (seen.contains(uniqueKey)) {
        return false; // Remove duplicate
      } else {
        seen.add(uniqueKey); // Mark as seen
        return true; // Keep
      }
    });
    _devicesstream.add(_devices);
  }

  Future<void> turnOnBluetooth() async {
    blueClassic.turnOn();
  }

  Stream<bool> get isBleTurnedOnStream {
    return blueClassic.adapterState.map(
      (event) {
        return event == BluetoothAdapterState.on;
      },
    );
  }
}
