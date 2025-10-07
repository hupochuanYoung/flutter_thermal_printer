# Error Dialog Feature Usage Guide

## Overview

The Flutter Thermal Printer plugin now supports automatic error dialog functionality. When plugin operations fail, it will automatically display user-friendly error dialogs to help users understand issues and provide solutions.

## Features

- **Automatic Error Detection**: Automatically displays error dialogs when connection, printing, and other operations fail
- **Categorized Error Handling**: Supports different types of errors including connection, printing, Bluetooth, USB, and network errors
- **User-Friendly Interface**: Provides clear error information and operation suggestions
- **Customizable Messages**: Supports custom error message content
- **Non-Blocking Notifications**: Provides notification functionality without blocking user operations

## Quick Start

### 1. Initialize Error Dialog Manager

Initialize the error dialog manager when your application starts:

```dart
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize error dialog manager
  await FlutterThermalPrinter.instance.initializeErrorDialog();
  
  runApp(MyApp());
}
```

### 2. Set BuildContext

Set the BuildContext in your main page or any page where you need to display error dialogs:

```dart
class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    // Set BuildContext for displaying error dialogs
    FlutterThermalPrinter.instance.setErrorDialogContext(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Your UI code
    );
  }
}
```

### 3. Automatic Error Handling

Once set up, the plugin will automatically display error dialogs in the following situations:

- **Connection Failed**: When device connection fails
- **Printing Failed**: When printing operations fail
- **Bluetooth Error**: When Bluetooth-related operations fail
- **USB Error**: When USB device operations fail
- **Network Error**: When network printer connections fail

## Manual Error Dialog Display

You can also manually display error dialogs:

### Connection Error

```dart
await FlutterThermalPrinter.instance.showConnectionError(
  context,
  deviceName: 'My Printer',
  customMessage: 'Unable to connect to printer, please check device status.',
);
```

### Printing Error

```dart
await FlutterThermalPrinter.instance.showPrintingError(
  context,
  deviceName: 'My Printer',
  customMessage: 'Printing failed, please check paper and ink.',
);
```

### Bluetooth Error

```dart
await FlutterThermalPrinter.instance.showBluetoothError(
  context,
  customMessage: 'Bluetooth connection failed, please check Bluetooth settings.',
);
```

### USB Error

```dart
await FlutterThermalPrinter.instance.showUsbError(
  context,
  customMessage: 'USB device connection failed, please check USB connection.',
);
```

### Network Error

```dart
await FlutterThermalPrinter.instance.showNetworkError(
  context,
  customMessage: 'Network connection failed, please check network settings.',
);
```

### General Error

```dart
await FlutterThermalPrinter.instance.showGeneralError(
  context,
  title: 'Custom Error',
  message: 'This is a custom error message.',
);
```

## Error Notifications

In addition to dialogs, the plugin also supports displaying error notifications (non-blocking):

```dart
await FlutterThermalPrinter.instance.showErrorNotification(
  title: 'Printing Failed',
  message: 'Unable to connect to printer',
  type: ErrorType.printing,
);
```

## Error Types

The plugin supports the following error types:

- `ErrorType.connection` - Connection errors
- `ErrorType.printing` - Printing errors
- `ErrorType.bluetooth` - Bluetooth errors
- `ErrorType.usb` - USB errors
- `ErrorType.network` - Network errors
- `ErrorType.general` - General errors

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

class PrinterPage extends StatefulWidget {
  @override
  _PrinterPageState createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  @override
  void initState() {
    super.initState();
    // Initialize error dialog manager
    FlutterThermalPrinter.instance.initializeErrorDialog();
    // Set BuildContext
    FlutterThermalPrinter.instance.setErrorDialogContext(context);
  }

  Future<void> connectToPrinter() async {
    // Create device model
    final device = DeviceModel(
      name: 'My Printer',
      address: '00:11:22:33:44:55',
      connectionType: ConnectionType.BLE,
    );

    // Try to connect, error dialog will be displayed automatically if it fails
    final result = await FlutterThermalPrinter.instance.connect(device);
    if (result) {
      // Connection successful
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection successful')),
      );
    }
    // If connection fails, error dialog will be displayed automatically
  }

  Future<void> printTest() async {
    final device = DeviceModel(
      name: 'My Printer',
      address: '00:11:22:33:44:55',
      connectionType: ConnectionType.BLE,
    );

    // Try to print, error dialog will be displayed automatically if it fails
    await FlutterThermalPrinter.instance.printData(device, [1, 2, 3, 4, 5]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Printer Test')),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: connectToPrinter,
            child: Text('Connect to Printer'),
          ),
          ElevatedButton(
            onPressed: printTest,
            child: Text('Test Print'),
          ),
        ],
      ),
    );
  }
}
```

## Important Notes

1. **BuildContext Setup**: Make sure to set the correct BuildContext before displaying error dialogs
2. **Initialization Order**: It's recommended to initialize the error dialog manager when the application starts
3. **Error Handling**: The plugin automatically handles most errors, but you can still manually display custom error messages
4. **User Experience**: Error dialogs provide a user-friendly interface to help users understand issues and take appropriate actions

## Troubleshooting

If error dialogs are not displaying, please check:

1. Whether the error dialog manager is properly initialized
2. Whether the correct BuildContext is set
3. Whether the methods are called in the correct page context
4. Check console logs for any related error messages

By using the error dialog feature, you can greatly improve the user experience and make it easier for users to understand and resolve printer-related issues.

## Default Error Messages

The plugin provides the following default error messages in English:

### Connection Errors
- "Unable to connect to device [deviceName]. Please check if the device is powered on and in a connectable state."

### Printing Errors
- "An error occurred while printing to device [deviceName]. Please check device status and connection."

### Bluetooth Errors
- "Bluetooth functionality has encountered an issue. Please check if Bluetooth is enabled and ensure the app has Bluetooth permissions."

### USB Errors
- "USB device connection has encountered an issue. Please check USB connection and permission settings."

### Network Errors
- "Network connection has encountered an issue. Please check network connection and printer IP address."

All error messages can be customized by providing a `customMessage` parameter when calling the error dialog methods.
