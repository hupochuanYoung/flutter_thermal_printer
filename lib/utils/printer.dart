// ignore_for_file: constant_identifier_names

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class Printer {
  String? address;
  String? name;
  ConnectionType? connectionType;
  bool? isConnected;
  String? vendorId;
  String? productId;

  Printer({
    this.address,
    this.name,
    this.connectionType,
    this.isConnected,
    this.vendorId,
    this.productId,
  });

  Printer.fromJson(Map<String, dynamic> json) {
    address = json['address'];
    name = json['connectionType'] == 'BLUETOOTH_CLASSIC'
        ? json['platformName']
        : json['name'];
    connectionType = _getConnectionTypeFromString(json['connectionType']);
    isConnected = json['isConnected'];
    vendorId = json['vendorId'];
    productId = json['productId'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['address'] = address;
    if (connectionType == ConnectionType.BLUETOOTH_CLASSIC) {
      data['platformName'] = name;
    } else {
      data['name'] = name;
    }
    data['connectionType'] = connectionTypeString;
    data['isConnected'] = isConnected;
    data['vendorId'] = vendorId;
    data['productId'] = productId;
    return data;
  }

  ConnectionType _getConnectionTypeFromString(String? connectionType) {
    switch (connectionType) {
      case 'BLUETOOTH_CLASSIC':
        return ConnectionType.BLUETOOTH_CLASSIC;
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
  BLUETOOTH_CLASSIC,
  USB,
  NETWORK,
}

extension PrinterExtension on Printer {
  String get connectionTypeString {
    switch (connectionType) {
      case ConnectionType.BLUETOOTH_CLASSIC:
        return 'BLE';
      case ConnectionType.USB:
        return 'USB';
      case ConnectionType.NETWORK:
        return 'NETWORK';
      default:
        return '';
    }
  }

  Stream<BluetoothConnectionState> get connectionState {
    if (connectionType != ConnectionType.BLUETOOTH_CLASSIC) {
      throw UnsupportedError('Only BLE printers are supported');
    }
    if (address == null) {
      throw ArgumentError('Addre  ss is required for BLE printers');
    }
    return BluetoothDevice.fromId(address!).connectionState;
  }
}
