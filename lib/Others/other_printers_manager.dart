import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_platform_interface.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

class OtherPrinterManager {
  OtherPrinterManager._privateConstructor();

  static OtherPrinterManager? _instance;

  static OtherPrinterManager get instance {
    _instance ??= OtherPrinterManager._privateConstructor();
    return _instance!;
  }

  final StreamController<List<DeviceModel>> _devicesstream =
      StreamController<List<DeviceModel>>.broadcast();
  final StreamController<Map<String, dynamic>> _callerIdStream =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<ScanningEvent> _scanningStream =
      StreamController<ScanningEvent>.broadcast();

  Stream<List<DeviceModel>> get devicesStream => _devicesstream.stream;

  Stream<Map<String, dynamic>> get callerIdStream => _callerIdStream.stream;

  Stream<ScanningEvent> get scanningStream => _scanningStream.stream;

  final List<DeviceModel> _devices = [];
  final Set<String> _sentDeviceKeys = {};

  StreamSubscription? _usbSubscription;
  StreamSubscription? _bleSubscription;
  StreamSubscription? _callerIdSubscription;
  final blueClassic = FlutterBlueClassic(usesFineLocation: true);

  // Track active connections
  final Map<String, BluetoothConnection> _activeBluetoothConnections = {};

  static const String _deviceChannelName =
      'flutter_thermal_printer/device_events';
  static const String _callerIdChannelName =
      'flutter_thermal_printer/callerid_events';

  final EventChannel _deviceEventChannel = EventChannel(_deviceChannelName);
  final EventChannel _callerIdEventChannel = EventChannel(_callerIdChannelName);

  bool get isIos => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  // Convenience getters for current state
  bool get isBleScanning => _scanningState[ConnectionType.BLE] ?? false;

  bool get isNetworkScanning => _scanningState[ConnectionType.NETWORK] ?? false;

  bool get isUsbScanning => _scanningState[ConnectionType.USB] ?? false;

  bool get isAnyScanning => _scanningState.values.any((scanning) => scanning);

  // Current scanning state
  final Map<ConnectionType, bool> _scanningState = {
    ConnectionType.BLE: false,
    ConnectionType.NETWORK: false,
    ConnectionType.USB: false,
  };
  final int _port = 9100;
  Timer? _bleScanTimeout;

  Future<bool> startListening(DeviceModel device) async {
    _callerIdSubscription?.cancel();
    _callerIdSubscription =
        _callerIdEventChannel.receiveBroadcastStream().listen((event) {
      final map = Map<String, dynamic>.from(event);
      log("Received Caller ID: ${map['caller']} at ${map['datetime']}");
      _callerIdStream.add(map);
    });

    return FlutterThermalPrinterPlatform.instance.startListening(
      device.vendorId!,
      device.productId!,
    );
  }

  Future<bool> stopListening() async {
    await _callerIdSubscription?.cancel();
    _callerIdSubscription = null;
    return FlutterThermalPrinterPlatform.instance.stopListening();
  }

  // Stop scanning for BLE devices
  Future<void> stopScan({
    bool stopBle = true,
    bool stopUsb = true,
    bool stopNetwork = true,
  }) async {
    try {
      if (stopBle) {
        await _bleSubscription?.cancel();
        _bleSubscription = null;
        _bleScanTimeout?.cancel();
        _bleScanTimeout = null;
        blueClassic.stopScan();
        _updateScanningState(ConnectionType.BLE, false);
        debugPrint('stopScan BLE');
      }
      if (stopUsb) {
        await _usbSubscription?.cancel();
        _updateScanningState(ConnectionType.USB, false);
      }
      if (stopNetwork) {
        _updateScanningState(ConnectionType.NETWORK, false);
      }
    } catch (e) {
      log('Failed to stop scanning for devices $e');
    }
  }

  Future<bool> connect(DeviceModel device) async {
    if (device.connectionType == ConnectionType.USB) {
      return await FlutterThermalPrinterPlatform.instance.connect(device);
    } else {
      try {
        return await bluetoothConnect(device.address!);
      } catch (e) {
        debugPrint('connect $e');
        return false;
      }
    }
  }

  Future<bool> bondDevice(String address) async {
    try {
      List<BluetoothDevice>? bondedDevices = await blueClassic.bondedDevices;
      for (var device in bondedDevices!) {
        if (device.address == address) {
          return true;
        }
      }
      return await blueClassic.bondDevice(address);
    } catch (e) {
      debugPrint('bondDevice $e');
      return false;
    }
  }

  Future<bool> bluetoothConnect(String address) async {
    try {
      // Clean up any existing connection first
      if (_activeBluetoothConnections.containsKey(address)) {
        if (_activeBluetoothConnections[address]?.isConnected ?? false) {
          return true;
        }
        try {
          _activeBluetoothConnections[address]?.dispose();
        } catch (e) {
          debugPrint('Failed to close existing connection: $e');
        }
        _activeBluetoothConnections.remove(address);
      }
      // 建立连接，增加超时时间
      BluetoothConnection? bt = await blueClassic.connect(address);
      if (bt == null) return false;
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify the connection is actually established
      if (!bt.isConnected) {
        debugPrint('Bluetooth connection not established for $address');
        bt.dispose();
        return false;
      }

      _activeBluetoothConnections[address] = bt;
      return bt.isConnected;
    } catch (e) {
      debugPrint('bluetoothConnect $e');
      _activeBluetoothConnections.remove(address);
      return false;
    }
  }

  Future<bool> isConnected(DeviceModel device) async {
    if (device.connectionType == ConnectionType.USB) {
      return await FlutterThermalPrinterPlatform.instance.isConnected(device);
    } else if (device.connectionType == ConnectionType.BLE) {
      try {
        if (_activeBluetoothConnections.containsKey(device.address!)) {
          return _activeBluetoothConnections[device.address!]!.isConnected;
        }
        _activeBluetoothConnections.remove(device.address);
        return false;
      } catch (e) {
        _activeBluetoothConnections.remove(device.address);
        return false;
      }
    } else {
      // ping ip
      // 对于其他连接类型（如NETWORK），直接返回设备状态
      final isValid = await _pingConnection(device.address!);
      if (isValid) {
        return true;
      } else {
        return false;
      }
    }
  }

  Future<bool> disconnect(DeviceModel device) async {
    if (device.connectionType == ConnectionType.BLE) {
      BluetoothConnection? bt;
      try {
        bt = _activeBluetoothConnections[device.address!];
        if (bt != null) {
          bt.dispose();
        }
      } catch (e) {
        log('disconnect $e');
      } finally {
        // 确保无论是否有错误都要清理连接
        if (bt != null) {
          try {
            bt.dispose();
          } catch (e) {
            log('Error disposing connection in finally block: $e');
          }
        }
        _activeBluetoothConnections.remove(device.address);
      }
    }
    return true;
  }

  // 统一处理BLE连接状态更新和清理
  void _updateBleConnectionStatus(String address, bool isConnected) {
    try {
      if (!isConnected) {
        // 断开连接时清理资源
        final bt = _activeBluetoothConnections[address];
        if (bt != null) {
          bt.dispose();
        }
        _activeBluetoothConnections.remove(address);
        log('Cleaned up BLE connection for $address');
      }

      // 更新设备列表中的连接状态（只对BLE设备）
      final index = _devices.indexWhere((device) =>
          device.address == address &&
          device.connectionType == ConnectionType.BLE);
      if (index != -1) {
        _devices[index].isConnected = isConnected;
        _sortDevices(); // 触发UI更新
      }
    } catch (e) {
      log('Error updating BLE connection status for $address: $e');
    }
  }

  // Print data to BLE device
  Future<void> printData(
    DeviceModel device,
    List<int> bytes, {
    bool longData = false,
    bool withoutResponse = false,
  }) async {
    if (device.connectionType == ConnectionType.USB) {
      try {
        await FlutterThermalPrinterPlatform.instance.printText(
          device,
          Uint8List.fromList(bytes),
          path: device.address,
        );
      } catch (e) {
        log("FlutterThermalPrinter: Unable to Print Data $e");
      }
    } else {
      try {
        BluetoothConnection? bt = _activeBluetoothConnections[device.address!];
        if (bt == null) {
          log('Device is not connected');
          // 更新设备连接状态为false
          _updateBleConnectionStatus(device.address!, false);
          return;
        }
        if (!bt.isConnected) {
          // 更新状态并清理无效连接
          _updateBleConnectionStatus(device.address!, false);
          // 尝试重新连接
          bool isConnected = await bluetoothConnect(device.address!);
          if (!isConnected) {
            log('Reconnection failed for ${device.address}');
            return;
          }
          // 获取新的连接对象
          bt = _activeBluetoothConnections[device.address!];
        }

        // 对于蓝牙设备，如果数据较长或明确标记为长数据，进行分片发送
        if (longData || bytes.length > 2048) {
          await _sendDataInChunks(bt!, bytes);
        } else {
          bt!.output.add(Uint8List.fromList(bytes));
          await bt.output.allSent;
        }
        return;
      } catch (e) {
        log('Failed to print data to device $e');
      }
    }
  }

  // 分片发送数据到蓝牙设备
  Future<void> _sendDataInChunks(
      BluetoothConnection bt, List<int> bytes) async {
    const int chunkSize = 1024; // 每片1024字节，平衡速度和稳定性
    const int delayMs = 5; // 减少延迟到5ms，提高流畅性

    for (int i = 0; i < bytes.length; i += chunkSize) {
      int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      List<int> chunk = bytes.sublist(i, end);

      bt.output.add(Uint8List.fromList(chunk));
      await bt.output.allSent;

      // 只在必要时添加延迟
      if (end < bytes.length && bytes.length > 4096) {
        await Future.delayed(const Duration(milliseconds: delayMs));
      }
    }
  }

// Get Devices from BT and USB
  Future<void> getDevices({
    List<ConnectionType> connectionTypes = const [ConnectionType.USB],
    bool androidUsesFineLocation = false,
    int cloudPrinterNum = 1,
  }) async {
    if (connectionTypes.isEmpty) {
      throw Exception('No connection type provided');
    }

    // 在开始扫描前清空所有BLE连接
    _activeBluetoothConnections.clear();
    _devices.clear();
    _sentDeviceKeys.clear();

    if (connectionTypes.contains(ConnectionType.USB)) {
      debugPrint("getUSBDevices");
      await stopScan(stopUsb: true, stopBle: false, stopNetwork: false);
      _updateScanningState(ConnectionType.USB, true);
      await _getUSBDevices();
    }

    if (connectionTypes.contains(ConnectionType.BLE)) {
      debugPrint("getBLEDevices");
      if (Platform.isAndroid) {
        await turnOnBluetooth();
        await stopScan(stopUsb: false, stopBle: true, stopNetwork: false);
        _updateScanningState(ConnectionType.BLE, true);
        await _getBleDevices(androidUsesFineLocation);
      }
    }
    if (connectionTypes.contains(ConnectionType.NETWORK)) {
      debugPrint("getWIFIDevices");
      await stopScan(stopUsb: false, stopBle: false, stopNetwork: true);
      _updateScanningState(ConnectionType.NETWORK, true);
      await _getNetworkDevices(cloudPrinterNum);
    }
  }

  Future<void> _getUSBDevices() async {
    try {
      final devices =
          await FlutterThermalPrinterPlatform.instance.startUsbScan();

      List<DeviceModel> usbPrinters = [];
      for (var map in devices) {
        final printer = DeviceModel(
          vendorId: map['vendorId'].toString(),
          productId: map['productId'].toString(),
          name: map['name'],
          connectionType: ConnectionType.USB,
          address: map['vendorId'].toString(),
          isConnected: map['connected'] ?? false,
          isRemove: map['isRemove'] ?? false,
        );
        printer.isConnected =
            await FlutterThermalPrinterPlatform.instance.isConnected(printer);
        usbPrinters.add(printer);
      }

      _devices.addAll(usbPrinters);
      _usbSubscription?.cancel();
      _usbSubscription =
          _deviceEventChannel.receiveBroadcastStream().listen((event) {
        final map = Map<String, dynamic>.from(event);
        _updateOrAddPrinter(DeviceModel(
          vendorId: map['vendorId'].toString(),
          productId: map['productId'].toString(),
          name: map['name'],
          connectionType: ConnectionType.USB,
          address: map['vendorId'].toString(),
          isConnected: map['connected'] ?? false,
          isRemove: map['isRemove'] ?? false,
        ));
      });

      _sortDevices();
    } catch (e) {
      log("$e [USB Connection]");
    }
  }

  Future<void> _getBleDevices(bool androidUsesFineLocation) async {
    try {
      _bleSubscription?.cancel();
      _bleSubscription = null;
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
      // if (Platform.isAndroid) {
      //   final bondedDevices = await _getBLEBondedDevices();
      //   _devices.addAll(bondedDevices);
      //   _sortDevices();
      // }

      // Listen to scan results
      _bleSubscription = blueClassic.scanResults.listen((result) {
        BluetoothDevice bluetoothDevice = result;
        debugPrint(
            'find BLE: ${bluetoothDevice.name} ${bluetoothDevice.address} ${bluetoothDevice.bondState}');
        DeviceModel printer = DeviceModel(
          address: bluetoothDevice.address,
          name: bluetoothDevice.name,
          connectionType: ConnectionType.BLE,
          rssi: bluetoothDevice.rssi,
          isConnected:
              _activeBluetoothConnections.containsKey(bluetoothDevice.address),
          bleDeviceType: bluetoothDevice.type.name,
        );
        _updateOrAddPrinter(printer);
      });

      _bleScanTimeout?.cancel();
      _bleScanTimeout = Timer(const Duration(seconds: 10), () async {
        await stopScan(stopUsb: false, stopBle: true, stopNetwork: false);
      });
    } catch (e) {
      _updateScanningState(ConnectionType.BLE, false);
      rethrow;
    }
  }

  Future<List<DeviceModel>> _getBLEBondedDevices() async {
    List<BluetoothDevice>? bondedDevices = await blueClassic.bondedDevices;
    if (bondedDevices == null) return [];
    List<DeviceModel> printers = [];

    for (var device in bondedDevices) {
      // 验证绑定设备是否真的可用（没有被物理移除）
      // bool isDeviceAvailable = await _validateBondedDevice(device.address);
      if (true) {
        printers.add(DeviceModel(
          address: device.address,
          name: device.name,
          rssi: device.rssi,
          connectionType: ConnectionType.BLE,
          isConnected: _activeBluetoothConnections.containsKey(device.address),
          bleDeviceType: device.type.name,
        ));
      } else {
        debugPrint(
            'Bonded device ${device.name} (${device.address}) is no longer available, skipping');
      }
    }

    return printers;
  }

  /// 验证绑定设备是否真的可用（没有被物理移除）
  Future<bool> _validateBondedDevice(String address) async {
    try {
      // 尝试快速连接来验证设备是否可用
      // 使用较短的超时时间，避免长时间等待
      final connection = await blueClassic.connect(address).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('Timeout validating bonded device $address');
          return null;
        },
      );

      if (connection != null) {
        // 如果连接成功，立即断开，我们只是为了验证设备可用性
        try {
          connection.dispose();
        } catch (e) {
          debugPrint('Error disposing validation connection: $e');
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to validate bonded device $address: $e');
      return false;
    }
  }

  Future<void> _getNetworkDevices(int cloudPrinterNum) async {
    String? ip = await _getLocalIP();
    if (ip != null) {
      // subnet
      final subnet = ip.substring(0, ip.lastIndexOf('.'));

      // Process IPs in concurrent batches for faster scanning
      const int batchSize = 25; // Process 25 IPs concurrently per batch
      const int maxConcurrency = 50; // Maximum concurrent operations

      List<Future<void>> allBatches = [];

      for (int startIp = 1; startIp <= 255; startIp += batchSize) {
        if (!_scanningState[ConnectionType.NETWORK]!) break;

        int endIp = (startIp + batchSize - 1).clamp(1, 255);
        allBatches.add(
          _processBatchOfIPs(subnet, startIp, endIp, cloudPrinterNum),
        );

        // Limit concurrent batches to avoid overwhelming the system
        if (allBatches.length >= maxConcurrency ~/ batchSize) {
          await Future.wait(allBatches);
          allBatches.clear();

          // Check if we found enough devices
          final foundDevices = _devices
              .where((d) => d.connectionType == ConnectionType.NETWORK)
              .length;
          if (foundDevices >= cloudPrinterNum) {
            break;
          }
        }
      }

      // Wait for remaining batches
      if (allBatches.isNotEmpty) {
        await Future.wait(allBatches);
      }
      _updateScanningState(ConnectionType.NETWORK, false);

      // remove duplicates by address
      _devices.removeWhere(
        (device) => device.address == null || device.address == '',
      );
      _sortDevices();
    }
  }

  Future<void> _processBatchOfIPs(
    String subnet,
    int startIp,
    int endIp,
    int maxDevices,
  ) async {
    if (!_scanningState[ConnectionType.NETWORK]!) return;

    List<Future<DeviceModel?>> pingFutures = [];

    for (int i = startIp; i <= endIp; i++) {
      if (!_scanningState[ConnectionType.NETWORK]!) return;

      final deviceIp = '$subnet.$i';
      pingFutures.add(_pingAndCreateDevice(deviceIp, i));
    }

    try {
      final results = await Future.wait(pingFutures);

      for (final device in results) {
        if (device != null && _scanningState[ConnectionType.NETWORK]!) {
          debugPrint('Valid device found ${device.address}');
          _devices.add(device);

          // Check if we've reached the limit
          final networkDeviceCount = _devices
              .where((d) => d.connectionType == ConnectionType.NETWORK)
              .length;
          if (networkDeviceCount >= maxDevices) {
            _updateScanningState(ConnectionType.NETWORK, false);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error in batch processing: $e');
    }
  }

  Future<DeviceModel?> _pingAndCreateDevice(String ip, int deviceNumber) async {
    try {
      final isValid = await _pingConnection(ip);
      if (isValid) {
        return DeviceModel(
          address: ip,
          name: 'Cloud Printer $deviceNumber',
          connectionType: ConnectionType.NETWORK,
          isConnected: false,
        );
      }
      return null;
    } catch (error) {
      debugPrint('Failed to ping $ip ${error.toString()}');
      return null;
    }
  }

  Future<bool> _pingConnection(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        _port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (error) {
      debugPrint('Failed to ping $ip ${error.toString()}');
      return false;
    }
  }

  void _updateOrAddPrinter(DeviceModel printer) {
    final index =
        _devices.indexWhere((device) => device.address == printer.address);
    if (index == -1) {
      _devices.add(printer);
    } else {
      _devices[index] = printer;
    }
    _sortDevices();
  }

  void _sortDevices() {
    // Only keep devices whose name contains any of: 'caller', 'cloud', or 'printer' (case-insensitive)
    _devices.removeWhere((element) {
      final name = element.name?.toLowerCase() ?? '';
      return name.isEmpty ||
          (!name.contains('caller') &&
              !name.contains('cloud') &&
              !name.contains('printer'));
    });
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
    if (_devices.isNotEmpty) {
      debugPrint('_sortDevices: ${_devices.map((e) => e.name).toList()}');
      _devicesstream.add(_devices);
    }
  }

  Future<void> turnOnBluetooth() async {
    bool isSupported = await blueClassic.isSupported;
    if (!isSupported) {
      log("Bluetooth not supported by this device");
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      blueClassic.turnOn();
    }
  }

  Future<String?> _getLocalIP() async {
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();
    return wifiIP;
  }

  Stream<bool> get isBleTurnedOnStream {
    return blueClassic.adapterState.map(
      (event) {
        return event == BluetoothAdapterState.on;
      },
    );
  }

  // Helper methods to update scanning state
  void _updateScanningState(ConnectionType type, bool isScanning) {
    // Only emit if state actually changed
    if (_scanningState[type] != isScanning) {
      _scanningState[type] = isScanning;
      _scanningStream.add(
        ScanningEvent(connectionType: type, isScanning: isScanning),
      );
    }
  }

  void dispose() {
    _devicesstream.close();
    _callerIdStream.close();
    _scanningStream.close();
    _bleSubscription?.cancel();
    _usbSubscription?.cancel();
    _callerIdSubscription?.cancel();
    _bleScanTimeout?.cancel();
    _bleScanTimeout = null;

    // Clean up active Bluetooth connections
    for (var connection in _activeBluetoothConnections.values) {
      try {
        connection.dispose();
      } catch (e) {
        debugPrint('Error disposing Bluetooth connection: $e');
      }
    }
    _activeBluetoothConnections.clear();
  }
}
