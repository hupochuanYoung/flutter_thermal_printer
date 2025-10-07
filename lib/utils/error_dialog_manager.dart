import 'package:flutter/material.dart';

/// 错误类型枚举
enum ErrorType {
  connection,
  printing,
  bluetooth,
  usb,
  network,
  general,
}

/// 错误弹窗管理器
class ErrorDialogManager {
  static final ErrorDialogManager _instance = ErrorDialogManager._internal();
  factory ErrorDialogManager() => _instance;
  ErrorDialogManager._internal();

  static ErrorDialogManager get instance => _instance;

  /// 初始化错误弹窗管理器
  Future<void> initialize() async {
    // 初始化逻辑，目前不需要特殊处理
  }

  /// 显示错误弹窗
  Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    ErrorType type = ErrorType.general,
    String? actionText,
    VoidCallback? onAction,
  }) async {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              _getErrorIcon(type),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Confirm'),
            ),
            if (actionText != null && onAction != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAction();
                },
                child: Text(actionText),
              ),
          ],
        );
      },
    );
  }

  /// 显示错误通知（简化版本，仅记录日志）
  Future<void> showErrorNotification({
    required String title,
    required String message,
    ErrorType type = ErrorType.general,
  }) async {
    // 简化版本：仅记录日志，不显示通知
    print('[$type] $title: $message');
  }

  /// 显示连接错误
  Future<void> showConnectionError(
    BuildContext context, {
    required String deviceName,
    String? customMessage,
  }) async {
    final message = customMessage ??
        'Unable to connect to device "$deviceName". Please check if the device is powered on and in a connectable state.';

    await showErrorDialog(
      context,
      title: 'Connection Failed',
      message: message,
      type: ErrorType.connection,

    );
  }

  /// 显示打印错误
  Future<void> showPrintingError(
    BuildContext context, {
    required String deviceName,
    String? customMessage,
  }) async {
    final message = customMessage ??
        'An error occurred while printing to device "$deviceName". Please check device status and connection.';

    await showErrorDialog(
      context,
      title: 'Printing Failed',
      message: message,
      type: ErrorType.printing,
    );
  }

  /// 显示蓝牙错误
  Future<void> showBluetoothError(
    BuildContext context, {
    String? customMessage,
  }) async {
    final message = customMessage ??
        'Bluetooth functionality has encountered an issue. Please check if Bluetooth is enabled and ensure the app has Bluetooth permissions.';

    await showErrorDialog(
      context,
      title: 'Bluetooth Error',
      message: message,
      type: ErrorType.bluetooth,
    );
  }

  /// 显示USB错误
  Future<void> showUsbError(
    BuildContext context, {
    String? customMessage,
  }) async {
    final message = customMessage ??
        'USB device connection has encountered an issue. Please check USB connection and permission settings.';

    await showErrorDialog(
      context,
      title: 'USB Error',
      message: message,
      type: ErrorType.usb,
    );
  }

  /// 显示网络错误
  Future<void> showNetworkError(
    BuildContext context, {
    String? customMessage,
  }) async {
    final message = customMessage ??
        'Network connection has encountered an issue. Please check network connection and printer IP address.';

    await showErrorDialog(
      context,
      title: 'Network Error',
      message: message,
      type: ErrorType.network,
    );
  }

  /// 显示通用错误
  Future<void> showGeneralError(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showErrorDialog(
      context,
      title: title,
      message: message,
      type: ErrorType.general,
    );
  }

  /// 获取错误图标
  Widget _getErrorIcon(ErrorType type) {
    IconData iconData;
    Color iconColor;

    switch (type) {
      case ErrorType.connection:
        iconData = Icons.link_off;
        iconColor = Colors.orange;
        break;
      case ErrorType.printing:
        iconData = Icons.print_disabled;
        iconColor = Colors.red;
        break;
      case ErrorType.bluetooth:
        iconData = Icons.bluetooth_disabled;
        iconColor = Colors.blue;
        break;
      case ErrorType.usb:
        iconData = Icons.usb_off;
        iconColor = Colors.green;
        break;
      case ErrorType.network:
        iconData = Icons.wifi_off;
        iconColor = Colors.purple;
        break;
      case ErrorType.general:
        iconData = Icons.error;
        iconColor = Colors.red;
        break;
    }

    return Icon(iconData, color: iconColor, size: 24);
  }
}
