# Bluetooth Timeout Issue Solution

## Problem
You're experiencing Bluetooth connection timeouts with error: `PlatformException(couldNotConnect, read failed, socket might closed or timeout, read ret: -1, null, null)`

## Quick Solution

Add this to your app initialization or before connecting to Bluetooth:

```dart
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';

// For frequently disconnecting Bluetooth devices
FlutterThermalPrinter.instance.useConservativeBluetoothConfig();
```

## What This Does

The conservative configuration uses:
- **Smaller chunk size (512 bytes)** instead of 2048
- **More delay (10ms)** between chunks
- **Earlier chunking (1024 bytes)** instead of 4096
- **Enhanced retry logic** with exponential backoff
- **Better timeout handling** (10 seconds with 3 retry attempts)

## Alternative Solutions

### 1. For Occasional Timeouts
```dart
// Use stable mode
FlutterThermalPrinter.instance.configureBluetoothPerformance(
  BluetoothPerformanceConfig.stable
);
```

### 2. For Severe Connection Issues
```dart
// Use the most conservative settings
FlutterThermalPrinter.instance.configureBluetoothPerformance(
  BluetoothPerformanceConfig.conservative
);
```

### 3. Monitor Connection Health
```dart
// Check current configuration
final info = FlutterThermalPrinter.instance.getBluetoothPerformanceInfo();
print('Current config: $info');
```

## Key Improvements Made

1. **Enhanced Retry Logic**: Now tries up to 3 times with exponential backoff
2. **Timeout Protection**: 10-second connection timeout with 5-second data send timeout
3. **Adaptive Configuration**: Automatically switches to conservative mode after failures
4. **Better Error Handling**: Distinguishes between retryable and non-retryable errors
5. **Connection Monitoring**: Tracks failures per device and applies appropriate settings
6. **Detailed Logging**: Enhanced logging for troubleshooting

## Testing Steps

1. Apply conservative configuration before connecting
2. Monitor logs for connection attempts and failures
3. If still failing, try manual bonding first:
   ```dart
   await printerManager.bondDevice("0C:25:76:CB:6E:EA");
   await printerManager.connect(device);
   ```

## Debugging

Enable debug logging to see detailed connection flow:
```dart
import 'dart:developer' as dev;
dev.log('Bluetooth connection details...');
```

The enhanced logging will show:
- Connection attempt numbers
- Timeout occurrences
- Adaptive configuration changes
- Data chunk progress

## Expected Results

- Significantly reduced connection timeouts
- Better stability for problematic Bluetooth devices
- Automatic recovery from temporary disconnections
- Improved reliability for thermal printing
