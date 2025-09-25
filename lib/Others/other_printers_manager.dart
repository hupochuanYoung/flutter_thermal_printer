import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  StreamSubscription? _bluetoothClassicSubscription;

  static String channelName = 'flutter_thermal_printer/events';
  static String bluetoothClassicChannelName =
      'flutter_thermal_printer/bluetooth_events';
  EventChannel eventChannel = EventChannel(channelName);
  EventChannel bluetoothClassicEventChannel =
      EventChannel(bluetoothClassicChannelName);
  bool get isIos => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  // Stop scanning for BLE devices
  Future<void> stopScan({
    bool stopBle = true,
    bool stopUsb = true,
  }) async {
    try {
      if (stopBle) {
        await _bluetoothClassicSubscription?.cancel();
        await FlutterThermalPrinterPlatform.instance.stopScan();
      }

      if (stopUsb) {
        await _usbSubscription?.cancel();
      }
    } catch (e) {
      log('Failed to stop scanning for devices $e');
    }
  }

  Future<bool> connect(Printer device) async {
    return await FlutterThermalPrinterPlatform.instance.connect(device);
  }

  Future<bool> isConnected(Printer device) async {
    return await FlutterThermalPrinterPlatform.instance.isConnected(device);
  }

  Future<void> disconnect(Printer device) async {
    try {
      await FlutterThermalPrinterPlatform.instance.disconnect(device);
    } catch (e) {
      log('Failed to disconnect device $e');
    }
  }

  // Print data to BLE device
  Future<void> printData(
    Printer printer,
    List<int> bytes, {
    bool longData = false,
    bool withoutResponse = false,
  }) async {
    try {
      await FlutterThermalPrinterPlatform.instance.printText(
        printer,
        Uint8List.fromList(bytes),
        path: printer.address,
      );
    } catch (e) {
      log("FlutterThermalPrinter: Unable to Print Data $e");
    }
    // if (printer.connectionType == ConnectionType.USB) {
    //   try {
    //     await FlutterThermalPrinterPlatform.instance.printText(
    //       printer,
    //       Uint8List.fromList(bytes),
    //       path: printer.address,
    //     );
    //   } catch (e) {
    //     log("FlutterThermalPrinter: Unable to Print Data $e");
    //   }
    // } else {
    //   try {
    //     final device = BluetoothDevice.fromId(printer.address!);
    //     if (!device.isConnected) {
    //       log('Device is not connected');
    //       return;
    //     }

    //     final services = (await device.discoverServices()).skipWhile((value) =>
    //         value.characteristics
    //             .where((element) => element.properties.write)
    //             .isEmpty);

    //     BluetoothCharacteristic? writeCharacteristic;
    //     for (var service in services) {
    //       for (var characteristic in service.characteristics) {
    //         if (characteristic.properties.write) {
    //           writeCharacteristic = characteristic;
    //           break;
    //         }
    //       }
    //     }

    //     if (writeCharacteristic == null) {
    //       log('No write characteristic found');
    //       return;
    //     }

    //     const maxChunkSize = 509;
    //     for (var i = 0; i < bytes.length; i += maxChunkSize) {
    //       final chunk = bytes.sublist(
    //         i,
    //         i + maxChunkSize > bytes.length ? bytes.length : i + maxChunkSize,
    //       );

    //       await writeCharacteristic.write(
    //         Uint8List.fromList(chunk),
    //         withoutResponse: withoutResponse,
    //       );
    //     }

    //     return;
    //   } catch (e) {
    //     log('Failed to print data to device $e');
    //   }
    // }
  }

  final List<Printer> _devices = [];
  StreamSubscription? _usbSubscription;

  // Get Printers from BT and USB
  Future<void> getPrinters({
    List<ConnectionType> connectionTypes = const [
      ConnectionType.BLUETOOTH_CLASSIC,
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

    if (connectionTypes.contains(ConnectionType.BLUETOOTH_CLASSIC)) {
      await _getBluetoothClassicPrinters();
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

  Future<void> _getBluetoothClassicPrinters() async {
    try {
      // 获取已配对的经典蓝牙设备
      final devices = await FlutterThermalPrinterPlatform.instance
          .getBluetoothDevicesList();

      List<Printer> bluetoothClassicPrinters = [];
      for (var map in devices) {
        final printer = Printer(
          address: map['address'],
          name: map['name'],
          connectionType: ConnectionType.BLUETOOTH_CLASSIC,
          isConnected: map['isConnected'] ?? false,
        );
        bluetoothClassicPrinters.add(printer);
      }

      _devices.addAll(bluetoothClassicPrinters);

      // 开始扫描新的经典蓝牙设备
      await FlutterThermalPrinterPlatform.instance.startBluetoothScan();

      // 监听扫描结果
      _bluetoothClassicSubscription?.cancel();
      _bluetoothClassicSubscription =
          bluetoothClassicEventChannel.receiveBroadcastStream().listen((event) {
        final map = Map<String, dynamic>.from(event);
        _updateOrAddPrinter(Printer(
          address: map['address'],
          name: map['name'],
          connectionType: ConnectionType.BLUETOOTH_CLASSIC,
          isConnected: map['isConnected'] ?? false,
        ));
      });

      sortDevices();
    } catch (e) {
      log("$e [Bluetooth Classic Connection]");
    }
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
    await FlutterBluePlus.turnOn();
  }

  Stream<bool> get isBleTurnedOnStream {
    return FlutterBluePlus.adapterState.map(
      (event) {
        return event == BluetoothAdapterState.on;
      },
    );
  }
}
