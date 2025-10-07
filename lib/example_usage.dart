import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

/// 错误弹窗功能使用示例
class ErrorDialogExample extends StatefulWidget {
  const ErrorDialogExample({super.key});

  @override
  State<ErrorDialogExample> createState() => _ErrorDialogExampleState();
}

class _ErrorDialogExampleState extends State<ErrorDialogExample> {
  @override
  void initState() {
    super.initState();
    // 初始化错误弹窗管理器
    FlutterThermalPrinter.instance.initializeErrorDialog();
    // 设置用于显示错误弹窗的BuildContext
    FlutterThermalPrinter.instance.setErrorDialogContext(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error Dialog Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Error Dialog Feature Demo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Connection error example
            ElevatedButton(
              onPressed: () => _showConnectionError(),
              child: const Text('Show Connection Error'),
            ),
            const SizedBox(height: 10),

            // Printing error example
            ElevatedButton(
              onPressed: () => _showPrintingError(),
              child: const Text('Show Printing Error'),
            ),
            const SizedBox(height: 10),

            // Bluetooth error example
            ElevatedButton(
              onPressed: () => _showBluetoothError(),
              child: const Text('Show Bluetooth Error'),
            ),
            const SizedBox(height: 10),

            // USB error example
            ElevatedButton(
              onPressed: () => _showUsbError(),
              child: const Text('Show USB Error'),
            ),
            const SizedBox(height: 10),

            // Network error example
            ElevatedButton(
              onPressed: () => _showNetworkError(),
              child: const Text('Show Network Error'),
            ),
            const SizedBox(height: 10),

            // General error example
            ElevatedButton(
              onPressed: () => _showGeneralError(),
              child: const Text('Show General Error'),
            ),
            const SizedBox(height: 20),

            // Real usage example
            const Text(
              'Real Usage Example:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: () => _testRealConnection(),
              child: const Text(
                  'Test Real Connection (Will Trigger Error Dialog)'),
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectionError() {
    FlutterThermalPrinter.instance.showConnectionError(
      context,
      deviceName: 'Test Printer',
      customMessage: 'This is an example connection error message.',
    );
  }

  void _showPrintingError() {
    FlutterThermalPrinter.instance.showPrintingError(
      context,
      deviceName: 'Test Printer',
      customMessage: 'This is an example printing error message.',
    );
  }

  void _showBluetoothError() {
    FlutterThermalPrinter.instance.showBluetoothError(
      context,
      customMessage: 'This is an example Bluetooth error message.',
    );
  }

  void _showUsbError() {
    FlutterThermalPrinter.instance.showUsbError(
      context,
      customMessage: 'This is an example USB error message.',
    );
  }

  void _showNetworkError() {
    FlutterThermalPrinter.instance.showNetworkError(
      context,
      customMessage: 'This is an example network error message.',
    );
  }

  void _showGeneralError() {
    FlutterThermalPrinter.instance.showGeneralError(
      context,
      title: 'Custom Error',
      message: 'This is an example general error message.',
    );
  }

  void _testRealConnection() async {
    // Create a virtual device to test connection
    final device = DeviceModel(
      name: 'Test Device',
      address: '00:00:00:00:00:00',
      connectionType: ConnectionType.BLE,
    );

    // Try to connect, this will trigger error dialog
    final result = await FlutterThermalPrinter.instance.connect(device);
    if (!result) {
      // Connection failed, error dialog has been automatically displayed
      print('Connection failed, error dialog has been displayed');
    }
  }
}
