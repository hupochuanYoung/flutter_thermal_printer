import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_platform_interface.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:flutter_thermal_printer/utils/bluetooth_performance_config.dart';

class OtherPrinterManager {
  OtherPrinterManager._privateConstructor();

  static OtherPrinterManager? _instance;

  static OtherPrinterManager get instance {
    _instance ??= OtherPrinterManager._privateConstructor();
    return _instance!;
  }

  // 性能配置参数
  static const int _defaultChunkSize = 2048;
  static const int _defaultDelayMs = 2;
  static const int _defaultLargeDataThreshold = 4096;
  static const int _defaultExtremeDataThreshold = 8192;

  // 可配置的性能参数
  int _bluetoothChunkSize = _defaultChunkSize;
  int _bluetoothDelayMs = _defaultDelayMs;
  int _largeDataThreshold = _defaultLargeDataThreshold;
  int _extremeDataThreshold = _defaultExtremeDataThreshold;

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
  final Map<String, DateTime> _lastConnectionCheck = {};
  final Map<String, int> _connectionFailureCount =
      {}; // Track connection failures per device
  final Map<String, int> _timeoutFailureCount =
      {}; // Track timeout failures per device
  final int _port = 9100;

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
        blueClassic.stopScan();
        _updateScanningState(ConnectionType.BLE, false);
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
        // bondDevice if not bonded
        await bondDevice(device.address!);
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
      await blueClassic.bondDevice(address);
      return true;
    } catch (e) {
      debugPrint('bondDevice $e');
      return false;
    }
  }

  Future<bool> bluetoothConnect(String address) async {
    const int maxRetryAttempts = 3;
    const Duration baseTimeout = Duration(seconds: 10);

    for (int attempt = 1; attempt <= maxRetryAttempts; attempt++) {
      try {
        log('Bluetooth connection attempt $attempt/$maxRetryAttempts for $address');

        // Clean up any existing connection first
        if (_activeBluetoothConnections.containsKey(address)) {
          try {
            await _activeBluetoothConnections[address]?.close();
          } catch (e) {
            debugPrint('Failed to close existing connection: $e');
          }
          _activeBluetoothConnections.remove(address);
        }

        // Add delay between retry attempts (exponential backoff)
        if (attempt > 1) {
          final delayDuration = Duration(milliseconds: 1000 * attempt);
          log('Waiting ${delayDuration.inMilliseconds}ms before retry...');
          await Future.delayed(delayDuration);
        }

        // 建立连接，使用超时控制
        BluetoothConnection? bt =
            await blueClassic.connect(address).timeout(baseTimeout);
        if (bt == null) {
          log('Failed to establish Bluetooth connection - returned null');
          continue;
        }

        // 减少连接后的等待时间，仅保留必要的稳定时间
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify the connection is actually established
        if (!bt.isConnected) {
          log('Bluetooth connection not established for $address');
          continue;
        }

        _activeBluetoothConnections[address] = bt;
        log('Successfully connected to $address on attempt $attempt');
        // Reset failure count on successful connection
        _connectionFailureCount.remove(address);
        return true;
      } catch (e) {
        log('Bluetooth connect attempt $attempt failed: $e');
        _activeBluetoothConnections.remove(address);

        if (attempt == maxRetryAttempts) {
          log('All connection attempts failed for $address');
          // Increment failure count and apply adaptive configuration
          _connectionFailureCount[address] =
              (_connectionFailureCount[address] ?? 0) + 1;
          final failureCount = _connectionFailureCount[address]!;
          log('Connection failure count for $address: $failureCount');

          // Apply adaptive performance configuration
          final adaptiveConfig =
              BluetoothPerformanceConfig.adaptive(failureCount);
          configureBluetoothPerformance(adaptiveConfig);
          log('Applied adaptive configuration: ${adaptiveConfig.mode.name} for $address');

          return false;
        }

        // Don't retry for certain types of errors
        if (e.toString().contains('device is not paired') ||
            e.toString().contains('device not found')) {
          log('Non-retryable error: $e');
          return false;
        }
      }
    }

    return false;
  }

  Future<bool> isConnected(DeviceModel device) async {
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

  Future<bool> disconnect(DeviceModel device) async {
    if (device.connectionType == ConnectionType.BLE) {
      try {
        final bt = _activeBluetoothConnections[device.address!];
        if (bt == null) return false;
        bt.dispose();
        _activeBluetoothConnections.remove(device.address!);
        return true;
      } catch (e) {
        log('disconnect $e');
        return false;
      }
    }
    return true;
  }

  // Print data to BLE device
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
          return;
        }
        // 智能连接检查：避免频繁重新连接
        if (!bt.isConnected) {
          bool shouldReconnect = true;
          String address = device.address!;

          // 如果在合理时间内最近检查过，跳过重新连接检查
          if (_lastConnectionCheck.containsKey(address)) {
            final lastCheck = _lastConnectionCheck[address]!;
            final timeSinceLastCheck = DateTime.now().difference(lastCheck);
            if (timeSinceLastCheck.inSeconds < 15) {
              // Increased from 10 to 15 seconds
              // 如果最近15秒内检查过连接，尝试直接发送而不重新连接
              // 这在打印任务连续时特别有用
              try {
                log('Attempting direct send without reconnection...');
                bt.output.add(Uint8List.fromList(bytes));
                await bt.output.allSent
                    .timeout(Duration(seconds: 5)); // Add timeout
                log('Direct send successful');
                return;
              } catch (e) {
                log('Direct send failed, will reconnect: $e');
                // 如果直接发送失败，则进行重新连接
                shouldReconnect = true;
              }
            }
          }

          if (shouldReconnect) {
            log('Attempting reconnection for $address...');
            bool isConnected = await bluetoothConnect(address);
            if (!isConnected) {
              log('Reconnection failed for $address');
              return;
            }
            _lastConnectionCheck[address] = DateTime.now();
            log('Successfully reconnected to $address');
          }
        } else {
          // 更新最后检查时间
          _lastConnectionCheck[device.address!] = DateTime.now();
        }

        // 检查设备是否有超时历史，如果是则使用保守配置
        final deviceAddress = device.address!;
        final timeoutCount = _timeoutFailureCount[deviceAddress] ?? 0;
        if (timeoutCount >= 2) {
          log('Device $deviceAddress has $timeoutCount timeout failures, using conservative configuration');
          // 临时切换到保守配置
          configureBluetoothPerformance(
              BluetoothPerformanceConfig.conservative);
        }

        // 优化的蓝牙发送策略：使用可配置的阈值
        if (longData || bytes.length > _largeDataThreshold) {
          log('Sending large data (${bytes.length} bytes) in chunks');
          await _sendDataInChunksWithDeviceContext(bt, bytes, deviceAddress);
        } else {
          log('Sending data (${bytes.length} bytes)');
          bt.output.add(Uint8List.fromList(bytes));
          await bt.output.allSent.timeout(Duration(seconds: 10)); // Add timeout
        }
        return;
      } catch (e) {
        log('Failed to print data to device $e');
      }
    }
  }

  // 优化的分片发送策略：使用可配置的参数
  // 带设备上下文的分片发送方法，记录失败次数
  Future<void> _sendDataInChunksWithDeviceContext(
      BluetoothConnection bt, List<int> bytes, String deviceAddress) async {
    try {
      await _sendDataInChunksOptimized(bt, bytes);
      // 成功发送，重置超时失败计数
      if (_timeoutFailureCount[deviceAddress] != null) {
        _timeoutFailureCount[deviceAddress] = 0;
        log('Reset timeout failure count for device $deviceAddress');
      }
    } catch (e) {
      // 如果是超时错误，增加失败计数
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('Future not completed')) {
        _timeoutFailureCount[deviceAddress] =
            (_timeoutFailureCount[deviceAddress] ?? 0) + 1;
        log('Incremented timeout failure count for device $deviceAddress: ${_timeoutFailureCount[deviceAddress]}');
      }
      rethrow;
    }
  }

  Future<void> _sendDataInChunksOptimized(
      BluetoothConnection bt, List<int> bytes) async {
    const int maxRetryAttempts = 2;
    const int chunkTimeoutSeconds = 8; // 增加分片超时时间

    final int totalChunks = (bytes.length / _bluetoothChunkSize).ceil();
    log('Starting chunked send: ${bytes.length} bytes in $totalChunks chunks');

    for (int i = 0; i < bytes.length; i += _bluetoothChunkSize) {
      int end = (i + _bluetoothChunkSize < bytes.length)
          ? i + _bluetoothChunkSize
          : bytes.length;
      List<int> chunk = bytes.sublist(i, end);
      final int chunkNumber = (i ~/ _bluetoothChunkSize) + 1;

      log('Sending chunk $chunkNumber/$totalChunks (${chunk.length} bytes)');

      bool chunkSent = false;
      Exception? lastError;

      // 尝试发送分片，最多重试maxRetryAttempts次
      for (int attempt = 1;
          attempt <= maxRetryAttempts && !chunkSent;
          attempt++) {
        try {
          bt.output.add(Uint8List.fromList(chunk));
          await bt.output.allSent
              .timeout(Duration(seconds: chunkTimeoutSeconds));

          log('Chunk $chunkNumber/$totalChunks sent successfully');
          chunkSent = true;

          // 只在极端大数据时添加延迟
          if (end < bytes.length && bytes.length > _extremeDataThreshold) {
            await Future.delayed(Duration(milliseconds: _bluetoothDelayMs));
          }

          // 等待一小段时间让打印机处理数据
          if (bytes.length > 4096 && chunkNumber % 10 == 0) {
            await Future.delayed(Duration(milliseconds: 10));
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          log('Chunk $chunkNumber/$totalChunks attempt $attempt failed: $e');

          // Check if it's a timeout error
          if (e.toString().contains('TimeoutException') ||
              e.toString().contains('Future not completed')) {
            log('Detected timeout error on chunk $chunkNumber');
          }

          if (attempt < maxRetryAttempts) {
            // 等待一段时间再重试，超时错误等待更长时间
            final delayMs = e.toString().contains('TimeoutException')
                ? 1000 * attempt
                : 200 * attempt;
            await Future.delayed(Duration(milliseconds: delayMs));
            log('Retrying chunk $chunkNumber/$totalChunks after ${delayMs}ms...');
          }
        }
      }

      // 如果分片发送失败，尝试恢复策略
      if (!chunkSent) {
        await _handleFailedChunk(bt, chunkNumber, totalChunks, lastError);
      }
    }

    log('Chunked send completed: ${bytes.length} bytes');
  }

  // 处理失败的分片
  Future<void> _handleFailedChunk(BluetoothConnection bt, int chunkNumber,
      int totalChunks, Exception? error) async {
    log('Handling failed chunk $chunkNumber/$totalChunks');

    try {
      // 记录超时失败次数（如果有地址信息的话）
      if (error.toString().contains('TimeoutException')) {
        // 尝试从蓝牙连接获取地址，这里需要传入设备地址
        log('Timeout failure detected on chunk $chunkNumber');
      }

      // 尝试检查连接状态
      if (!bt.isConnected) {
        log('Connection lost during chunked send, cannot recover');
        throw Exception('Bluetooth connection lost during chunk sending');
      }

      // 对于超时错误，等待更长时间让打印机处理缓冲区
      if (error?.toString().contains('TimeoutException') == true) {
        await Future.delayed(Duration(milliseconds: 1500));
        log('Extended wait for timeout recovery');
      } else {
        await Future.delayed(Duration(milliseconds: 500));
      }

      log('Continuing with next chunk despite failure');
    } catch (e) {
      log('Failed to handle chunk failure: $e');
      rethrow;
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
      if (Platform.isAndroid) {
        final bondedDevices = await _getBLEBondedDevices();
        _devices.addAll(bondedDevices);
      }

      _sortDevices();

      // Listen to scan results
      _bleSubscription = blueClassic.scanResults.listen((result) {
        BluetoothDevice bluetoothDevice = result;
        DeviceModel printer = DeviceModel(
          address: bluetoothDevice.address,
          name: bluetoothDevice.name,
          connectionType: ConnectionType.BLE,
          rssi: bluetoothDevice.rssi,
          isConnected:
              _activeBluetoothConnections.containsKey(bluetoothDevice.address),
        );
        _updateOrAddPrinter(printer);
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<List<DeviceModel>> _getBLEBondedDevices() async {
    List<BluetoothDevice>? bondedDevices = await blueClassic.bondedDevices;
    if (bondedDevices == null) return [];
    List<DeviceModel> printers = [];
    for (var device in bondedDevices) {
      printers.add(DeviceModel(
        address: device.address,
        name: device.name,
        rssi: device.rssi,
        connectionType: ConnectionType.BLE,
        isConnected: _activeBluetoothConnections.containsKey(device.address),
      ));
    }

    return printers;
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

  // 性能配置方法
  /// 配置蓝牙打印性能参数
  void configureBluetoothPerformance(BluetoothPerformanceConfig config) {
    _bluetoothChunkSize = config.chunkSize;
    _bluetoothDelayMs = config.delayMs;
    _largeDataThreshold = config.largeDataThreshold;
    _extremeDataThreshold = config.extremeDataThreshold;

    log('Bluetooth performance configured: ${config.mode.name} - '
        'chunkSize: ${config.chunkSize}, delay: ${config.delayMs}ms');
  }

  /// 重置为默认的平衡模式配置
  void resetBluetoothPerformanceToDefault() {
    configureBluetoothPerformance(BluetoothPerformanceConfig.balanced);
  }

  /// 获取当前性能配置信息
  Map<String, dynamic> getBluetoothPerformanceInfo() {
    return {
      'chunkSize': _bluetoothChunkSize,
      'delayMs': _bluetoothDelayMs,
      'largeDataThreshold': _largeDataThreshold,
      'extremeDataThreshold': _extremeDataThreshold,
      'smartReconnectionEnabled': true, // 始终启用
      'timeoutFailureCounts': Map.from(_timeoutFailureCount),
      'connectionFailureCounts': Map.from(_connectionFailureCount),
    };
  }

  /// 重置特定设备的超时失败计数
  void resetDeviceTimeoutFailures(String deviceAddress) {
    _timeoutFailureCount.remove(deviceAddress);
    log('Reset timeout failure count for device $deviceAddress');
  }

  /// 重置所有设备的超时失败计数
  void resetAllTimeoutFailures() {
    _timeoutFailureCount.clear();
    log('Reset all timeout failure counts');
  }

  void dispose() {
    _devicesstream.close();
    _callerIdStream.close();
    _scanningStream.close();
    _bleSubscription?.cancel();
    _usbSubscription?.cancel();
    _callerIdSubscription?.cancel();
  }
}
