import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:image/image.dart' as img;
import 'package:screenshot/screenshot.dart';

import 'Others/other_printers_manager.dart';

export 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
export 'package:flutter_thermal_printer/network/network_printer.dart';

class FlutterThermalPrinter {
  FlutterThermalPrinter._();

  static FlutterThermalPrinter? _instance;

  static FlutterThermalPrinter get instance {
    _instance ??= FlutterThermalPrinter._();
    return _instance!;
  }

  Stream<Map<String, dynamic>> get callerIdStream {
    if (Platform.isWindows) {
      return Stream.value({});
    } else {
      return OtherPrinterManager.instance.callerIdStream;
    }
  }

  Stream<ScanningEvent> get scanningStream {
    if (Platform.isWindows) {
      return Stream.value(
          ScanningEvent(connectionType: ConnectionType.USB, isScanning: false));
    } else {
      return OtherPrinterManager.instance.scanningStream;
    }
  }

  Stream<List<DeviceModel>> get devicesStream {
    if (Platform.isWindows) {
      return Stream.value([]);
    } else {
      return OtherPrinterManager.instance.devicesStream;
    }
  }

  Future<bool> isConnected(DeviceModel device) async {
    if (Platform.isWindows) {
      return false;
    } else {
      return await OtherPrinterManager.instance.isConnected(device);
    }
  }

  Future<bool> stopListening() async {
    if (Platform.isWindows) {
      return false;
    } else {
      return await OtherPrinterManager.instance.stopListening();
    }
  }

  Future<bool> startListening(DeviceModel device) async {
    if (Platform.isWindows) {
      return false;
    } else {
      return await OtherPrinterManager.instance.startListening(device);
    }
  }

  Future<bool> connect(DeviceModel device) async {
    if (Platform.isWindows) {
      return false;
    } else {
      return await OtherPrinterManager.instance.connect(device);
    }
  }

  Future<bool> disconnect(DeviceModel device) async {
    if (Platform.isWindows) {
      return false;
    } else {
      return  await OtherPrinterManager.instance.disconnect(device);
    }
  }

  Future<void> printData(
    DeviceModel device,
    List<int> bytes, {
    bool longData = false,
    bool withoutResponse = false,
  }) async {
    if (Platform.isWindows) {
      return;
    } else {
      return await OtherPrinterManager.instance.printData(
        device,
        bytes,
        longData: longData,
        withoutResponse: withoutResponse,
      );
    }
  }

  Future<void> getDevices({
    List<ConnectionType> connectionTypes = const [ConnectionType.USB],
    bool androidUsesFineLocation = false,
    int cloudPrinterNum = 1,
  }) async {
    if (Platform.isWindows) {
    } else {
      OtherPrinterManager.instance.getDevices(
        connectionTypes: connectionTypes,
        androidUsesFineLocation: androidUsesFineLocation,
        cloudPrinterNum: cloudPrinterNum,
      );
    }
  }

  Future<void> stopScan({
    bool stopBle = true,
    bool stopUsb = true,
    bool stopNetwork = true,
  }) async {
    if (Platform.isWindows) {
    } else {
      OtherPrinterManager.instance.stopScan(
        stopBle: stopBle,
        stopUsb: stopUsb,
        stopNetwork: stopNetwork,
      );
    }
  }

  // Turn On Bluetooth
  Future<void> turnOnBluetooth() async {
    if (Platform.isWindows) {
    } else {
      await OtherPrinterManager.instance.turnOnBluetooth();
    }
  }

  Stream<bool> get isBleTurnedOnStream {
    if (Platform.isWindows) {
      return Stream.value(false);
    } else {
      return OtherPrinterManager.instance.isBleTurnedOnStream;
    }
  }

  Future<Uint8List> screenShotWidget(
    BuildContext context, {
    required Widget widget,
    Duration delay = const Duration(milliseconds: 100),
    int? customWidth,
    PaperSize paperSize = PaperSize.mm80,
    Generator? generator,
  }) async {
    final controller = ScreenshotController();
    final image = await controller.captureFromLongWidget(widget,
        pixelRatio:1,
        // View.of(context).devicePixelRatio,
        delay: delay);
    Generator? generator0;
    if (generator == null) {
      final profile = await CapabilityProfile.load();
      generator0 = Generator(paperSize, profile);
    } else {
      final profile = await CapabilityProfile.load();
      generator0 = Generator(paperSize, profile);
    }
    img.Image? imagebytes = img.decodeImage(image);

    if (customWidth != null) {
      final width = _makeDivisibleBy8(customWidth);
      imagebytes = img.copyResize(imagebytes!, width: width);
    }

    imagebytes = _buildImageRasterAvaliable(imagebytes!);

    imagebytes = img.grayscale(imagebytes);
    final totalheight = imagebytes.height;
    final totalwidth = imagebytes.width;
    final timestoCut = totalheight ~/ 30;
    List<int> bytes = [];
    for (var i = 0; i < timestoCut; i++) {
      final croppedImage = img.copyCrop(
        imagebytes,
        x: 0,
        y: i * 30,
        width: totalwidth,
        height: 30,
      );
      final raster = generator0.imageRaster(
        croppedImage,
        imageFn: PosImageFn.bitImageRaster,
      );
      bytes += raster;
    }
    return Uint8List.fromList(bytes);
  }

  img.Image _buildImageRasterAvaliable(img.Image image) {
    final avaliable = image.width % 8 == 0;
    if (avaliable) {
      return image;
    }
    final newWidth = _makeDivisibleBy8(image.width);
    return img.copyResize(image, width: newWidth);
  }

  int _makeDivisibleBy8(int number) {
    if (number % 8 == 0) {
      return number;
    }
    return number + (8 - (number % 8));
  }

  Future<void> printWidget(
    BuildContext context, {
    required DeviceModel printer,
    required Widget widget,
    Duration delay = const Duration(milliseconds: 100),
    PaperSize paperSize = PaperSize.mm80,
    CapabilityProfile? profile,
    bool printOnBle = false,
    bool cutAfterPrinted = true,
  }) async {
    // if (printOnBle == false && printer.connectionType == ConnectionType.BLE) {
    //   throw Exception(
    //     "Image printing on BLE Printer may be slow or fail. Still Need try? set printOnBle to true",
    //   );
    // }
    final controller = ScreenshotController();

    final image = await controller.captureFromLongWidget(
      widget,
      pixelRatio: 1,
        // View.of(context).devicePixelRatio,
      delay: delay,
    );
    if (printer.connectionType == ConnectionType.BLE) {
      CapabilityProfile profile0 = profile ?? await CapabilityProfile.load();
      final ticket = Generator(paperSize, profile0);
      img.Image? imagebytes = img.decodeImage(image);
      imagebytes = _buildImageRasterAvaliable(imagebytes!);
      final raster = ticket.imageRaster(
        imagebytes,
        imageFn: PosImageFn.bitImageRaster,
      );
      await FlutterThermalPrinter.instance.printData(
        printer,
        raster,
        longData: true,
      );

      if (cutAfterPrinted) {
        await FlutterThermalPrinter.instance.printData(
          printer,
          ticket.cut(),
          longData: true,
        );
      }
      return;
    }

    CapabilityProfile profile0 = profile ?? await CapabilityProfile.load();
    final ticket = Generator(paperSize, profile0);
    img.Image? imagebytes = img.decodeImage(image);
    imagebytes = _buildImageRasterAvaliable(imagebytes!);
    final totalheight = imagebytes.height;
    final totalwidth = imagebytes.width;
    final timestoCut = totalheight ~/ 30;

    for (var i = 0; i < timestoCut; i++) {
      final croppedImage = img.copyCrop(
        imagebytes,
        x: 0,
        y: i * 30,
        width: totalwidth,
        height: 30,
      );
      final raster = ticket.imageRaster(
        croppedImage,
        imageFn: PosImageFn.bitImageRaster,
      );
      await FlutterThermalPrinter.instance.printData(
        printer,
        raster,
        longData: true,
      );
    }
    if (cutAfterPrinted) {
      await FlutterThermalPrinter.instance.printData(
        printer,
        ticket.cut(),
        longData: true,
      );
    }
  }

  Future<void> printImageBytes({
    required Uint8List imageBytes,
    required DeviceModel printer,
    Duration delay = const Duration(milliseconds: 100),
    PaperSize paperSize = PaperSize.mm80,
    CapabilityProfile? profile,
    Generator? generator,
    bool printOnBle = false,
    int? customWidth,
  }) async {
    if (printOnBle == false && printer.connectionType == ConnectionType.BLE) {
      throw Exception(
        "Image printing on BLE Printer may be slow or fail. Still Need try? set printOnBle to true",
      );
    }

    CapabilityProfile profile0 = profile ?? await CapabilityProfile.load();
    final ticket = generator ?? Generator(paperSize, profile0);
    img.Image? imagebytes = img.decodeImage(imageBytes);
    if (customWidth != null) {
      final width = _makeDivisibleBy8(customWidth);
      imagebytes = img.copyResize(imagebytes!, width: width);
    }
    imagebytes = _buildImageRasterAvaliable(imagebytes!);
    final totalheight = imagebytes.height;
    final totalwidth = imagebytes.width;
    final timestoCut = totalheight ~/ 30;
    for (var i = 0; i < timestoCut; i++) {
      final croppedImage = img.copyCrop(
        imagebytes,
        x: 0,
        y: i * 30,
        width: totalwidth,
        height: 30,
      );
      final raster = ticket.imageRaster(
        croppedImage,
        imageFn: PosImageFn.bitImageRaster,
      );
      await FlutterThermalPrinter.instance.printData(
        printer,
        raster,
        longData: true,
      );
    }
  }
}
