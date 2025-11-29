// ignore_for_file: constant_identifier_names

class ScanningEvent {
  final ConnectionType connectionType;
  final bool isScanning;

  ScanningEvent({required this.connectionType, required this.isScanning});

  @override
  String toString() => 'ScanningEvent($connectionType: $isScanning)';
}

enum BleDeviceType { classic, dual, unknown }

class DeviceModel {
  String? address;
  String? name;
  ConnectionType? connectionType;
  bool? isConnected;
  String? vendorId;
  String? productId;
  String? deviceId;
  int? rssi;
  bool? isRemove;
  String? bleDeviceType;

  DeviceModel({
    this.address,
    this.name,
    this.connectionType,
    this.isConnected,
    this.vendorId,
    this.productId,
    this.deviceId,
    this.rssi,
    this.isRemove,
    this.bleDeviceType,
  });

  DeviceModel.fromJson(Map<String, dynamic> json) {
    address = json['address'];
    name = json['connectionType'] == 'BLE' ? json['platformName'] : json['name'];
    connectionType = _getConnectionTypeFromString(json['connectionType']);
    isConnected = json['isConnected'];
    vendorId = json['vendorId'];
    productId = json['productId'];
    deviceId = json['deviceId'];
    rssi = json['rssi'];
    isRemove = json['isRemove'];
    bleDeviceType = json['bleDeviceType'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['address'] = address;
    if (connectionType == ConnectionType.BLE) {
      data['platformName'] = name;
    } else {
      data['name'] = name;
    }
    data['connectionType'] = connectionTypeString;
    data['isConnected'] = isConnected;
    data['vendorId'] = vendorId;
    data['rssi'] = rssi;
    data['productId'] = productId;
    data['deviceId'] = deviceId;
    data['isRemove'] = isRemove;
    data['bleDeviceType'] = bleDeviceType;
    return data;
  }

  ConnectionType _getConnectionTypeFromString(String? connectionType) {
    switch (connectionType) {
      case 'BLE':
        return ConnectionType.BLE;
      case 'USB':
        return ConnectionType.USB;
      case 'NETWORK':
        return ConnectionType.NETWORK;
      default:
        throw ArgumentError('Invalid connection type');
    }
  }
}

enum ConnectionType {
  BLE,
  USB,
  NETWORK,
}

extension DeviceExtension on DeviceModel {
  String get connectionTypeString {
    switch (connectionType) {
      case ConnectionType.BLE:
        return 'BLE';
      case ConnectionType.USB:
        return 'USB';
      case ConnectionType.NETWORK:
        return 'NETWORK';
      default:
        return '';
    }
  }
}
