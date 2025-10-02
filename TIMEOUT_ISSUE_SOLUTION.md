# 蓝牙分片发送超时问题解决方案

## 问题描述

在分片发送大数据时遇到以下错误：
```
[log] Failed to send chunk 56: TimeoutException after 0:00:05.000000: Future not completed
[log] Failed to print data to device TimeoutException after 0:00:05.000000: Future not completed
```

## 解决方案

### 1. 智能重试机制 ✅

新的分片发送逻辑包含以下改进：

- **重试次数**：每个分片最多重试2次
- **超时时间**：从5秒增加到8秒
- **重试延迟**：超时错误重试等待1秒，其他错误等待200ms

```dart
// 代码实现
const int maxRetryAttempts = 2;
const int chunkTimeoutSeconds = 8; // 增加分片超时时间

for (int attempt = 1; attempt <= maxRetryAttempts && !chunkSent; attempt++) {
  try {
    bt.output.add(Uint8List.fromList(chunk));
    await bt.output.allSent.timeout(Duration(seconds: chunkTimeoutSeconds));
    chunkSent = true;
  } catch (e) {
    if (attempt < maxRetryAttempts) {
      final delayMs = e.toString().contains('TimeoutException') ? 
          1000 * attempt : 200 * attempt;
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }
}
```

### 2. 智能配置自适应 ✅

系统会自动跟踪设备超时失败次数，超过2次时自动切换到保守配置：

```dart
// 自动检测超时历史
final timeoutCount = _timeoutFailureCount[deviceAddress] ?? 0;
if (timeoutCount >= 2) {
  log('Device $deviceAddress has $timeoutCount timeout failures, using conservative configuration');
  configureBluetoothPerformance(BluetoothPerformanceConfig.conservative);
}
```

### 3. 保守配置模式 ✅

新增保守配置，针对容易超时的设备：

```dart
static const BluetoothPerformanceConfig conservative = BluetoothPerformanceConfig(
  mode: BluetoothPerformanceMode.stable,
  chunkSize: 512,          // 更小的分片
  delayMs: 10,             // 更多延迟
  largeDataThreshold: 1024,    // 更早启用分片
  extremeDataThreshold: 2048
  
);
```

## 如何应对当前问题

### 立即解决方案

1. **手动切换到保守模式**：
```dart
FlutterThermalPrinter.instance.useConservativeBluetoothConfig();
```

2. **检查设备失败统计**：
```dart
final performanceInfo = FlutterThermalPrinter.instance.getBluetoothPerformanceInfo();
print('Device failure counts: ${performanceInfo['timeoutFailureCounts']}');
```

3. **重置失败统计（如果需要）**：
```dart
// 如果设备已经修复连接问题
FlutterThermalPrinter.instance.resetDeviceTimeoutFailures(deviceAddress);
// 或重置所有设备
FlutterThermalPrinter.instance.resetAllTimeoutFailures();
```

### 长期解决方案

1. **自动适应**：系统现在会自动检测频繁超时的设备并切换配置
2. **错误隔离**：单个分片失败不会导致整个打印任务失败
3. **性能优化**：通过智能重试和配置调整提高成功率

## 配置建议

### 对于高数据量打印

如果你想打印大量数据而遇到超时问题：

```dart
// 方案1：使用保守配置（最稳定）
FlutterThermalPrinter.instance.configureBluetoothPerformance(
  BluetoothPerformanceConfig.conservative
);

// 方案2：自定义配置
final customConfig = BluetoothPerformanceConfig(
  mode: BluetoothPerformanceMode.stable,
  chunkSize: 1024,     // 较小的分片
  delayMs: 5,          // 适中的延迟
  largeDataThreshold: 2048,     // 较早开始分片
  extremeDataThreshold: 4096,   
);
FlutterThermalPrinter.instance.configureBluetoothPerformance(customConfig);
```

### 监控和调试

查看当前配置和失败统计：

```dart
final info = FlutterThermalPrinter.instance.getBluetoothPerformanceInfo();
print('Current configuration:');
print('  Chunk size: ${info['chunkSize']}');
print('  Delay: ${info['delayMs']}ms');
print('  Device failures: ${info['timeoutFailureCounts']}');
```

## 测试验证

完成配置后，重新测试打印功能：

1. **小数据测试**：打印少量文本验证基本功能
2. **大数据测试**：打印图片或复杂内容验证分片发送
3. **连续打印测试**：验证重试机制效果

系统现在应该能够：
- 自动重试失败的分片
- 根据设备历史自动调整配置
- 提供详细的错误和重试日志
- 避免单个分片失败导致整个任务失败

如果问题仍然存在，建议检查蓝牙设备的具体型号和距离，某些老式或距离较远的设备可能需要更保守的配置。
