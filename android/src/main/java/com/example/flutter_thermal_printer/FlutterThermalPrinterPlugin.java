package com.example.flutter_thermal_printer;

import android.content.Context;

import androidx.annotation.NonNull;

import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.EventChannel;

/** FlutterThermalPrinterPlugin */
public class FlutterThermalPrinterPlugin implements FlutterPlugin, MethodCallHandler {
    /// The MethodChannel that will the communication between Flutter and native
    /// Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine
    /// and unregister it
    /// when the Flutter Engine is detached from the Activity
    private MethodChannel channel;
    private EventChannel eventChannel;
    private EventChannel bluetoothEventChannel;
    private Context context;
    private UsbPrinter usbPrinter;
    private BluetoothPrinter bluetoothPrinter;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_thermal_printer");
        eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_thermal_printer/events");
        bluetoothEventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(),
                "flutter_thermal_printer/bluetooth_events");
        channel.setMethodCallHandler(this);
        context = flutterPluginBinding.getApplicationContext();
        usbPrinter = new UsbPrinter(context);
        bluetoothPrinter = new BluetoothPrinter(context);
        eventChannel.setStreamHandler(usbPrinter);
        bluetoothEventChannel.setStreamHandler(bluetoothPrinter);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "getPlatformVersion":
                result.success("Android " + android.os.Build.VERSION.RELEASE);
                break;
            case "getUsbDevicesList":
                result.success(usbPrinter.getUsbDevicesList());
                break;
            case "connect": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                usbPrinter.connect(vendorId, productId);
                result.success(false);
                break;
            }
            case "disconnect": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                String address = call.argument("address");
                if (address == null) {
                    result.success(usbPrinter.disconnect(vendorId, productId));
                } else {
                    result.success(bluetoothPrinter.disconnect(address));
                }
                result.success(usbPrinter.disconnect(vendorId, productId));
                break;
            }
            case "printText": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                String address = call.argument("address");
                List<Integer> data = call.argument("data");
                if (address == null) {
                    usbPrinter.printText(vendorId, productId, data);
                } else {
                    bluetoothPrinter.printText(address, data);
                }
                result.success(true);
                break;
            }
            case "isConnected": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                String address = call.argument("address");
                if (address == null) {
                    result.success(usbPrinter.isConnected(vendorId, productId));
                } else {
                    result.success(bluetoothPrinter.isConnected(address));
                }
                break;
            }
            // 经典蓝牙相关方法
            case "turnOnBluetooth": {
                bluetoothPrinter.turnOnBluetooth();
                result.success(true);
                break;
            }
            case "checkBluetoothPermission": {
                result.success(bluetoothPrinter.checkBluetoothPermission());
                break;
            }
            case "getBluetoothDevicesList":
                result.success(bluetoothPrinter.getBluetoothDevicesList());
                break;
            case "startBluetoothScan":
                bluetoothPrinter.startScan();
                result.success(true);
                break;
            case "stopBluetoothScan":
                bluetoothPrinter.stopScan();
                result.success(true);
                break;

            default:
                result.notImplemented();
                break;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }
}
