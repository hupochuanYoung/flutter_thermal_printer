# 蓝牙热打印性能优化说明

## 问题分析

在使用经典蓝牙进行热打印时，用户反馈打印速度仍然很慢。经过代码分析，发现了以下主要性能瓶颈：

1. **连接建立延迟**：在蓝牙连接建立后有500ms的硬编码延迟
2. **分片发送策略保守**：1024字节分片大小过小，5ms延迟过多
3. **频繁连接验证**：每次打印前都验证连接状态
4. **缺乏性能配置选项**：没有针对不同场景的优化配置

## 优化措施

### 1. 连接优化

**问题**：`bluetoothConnect` 方法中有500ms的不必要延迟
```dart
// 原始代码
await Future.delayed(const Duration(milliseconds: 500));
```

**解决方案**：减少到100ms的稳定时间
```dart
// 优化后
await Future.delayed(const Duration(milliseconds: 100));
```

**预期效果**：每次连接节省400ms

### 2. 分片发送策略优化

**问题**：
- 分片大小1024字节过小
- 5ms延迟过多
- 2048字节以上才启用分片

**解决方案**：
- 分片大小增加到2048字节
- 延迟减少到2ms
- 阈值提高到4096字节
- 只在超大数据(8192+字节)时添加延迟

**原始参数**：
```dart
const int chunkSize = 1024;
const int delayMs = 5;
if (longData || bytes.length > 2048) // 启用分片
```

**优化参数**：
```dart
int chunkSize = 2048;  // 可配置
int delayMs = 2;       // 可配置
if (longData || bytes.length > 4096) // 延迟启用分片
```

### 3. 智能连接管理

**问题**：每次打印都验证连接状态并可能重新连接

**解决方案**：引入智能重连机制
- 跟踪最近连接检查时间
- 10秒内跳过重复连接检查
- 尝试直接发送，失败时才重连

```dart
// 智能连接检查逻辑
if (_lastConnectionCheck.containsKey(address)) {
  final lastCheck = _lastConnectionCheck[address]!
  final timeSinceLastCheck = DateTime.now().difference(lastCheck);
  if (timeSinceLastCheck.inSeconds < 10) {
    // 尝试直接发送而不重新连接
    try {
      bt.output.add(Uint8List.fromList(bytes));
      await bt.output.allSent;
      return;
    } catch (e) {
      // 直接发送失败，进行重连
    }
  }
}
```

### 4. 性能配置系统

新增 `BluetoothPerformanceConfig` 类，提供三种预设模式：

#### 快速模式 (Fast)
```dart
BluetoothPerformanceConfig.fast
// chunkSize: 3072
// delayMs: 0  // 无延迟
// largeDataThreshold: 4096
// extremeDataThreshold: 12288
```

#### 平衡模式 (Balanced) - 默认
```dart
BluetoothPerformanceConfig.balanced
// chunkSize: 2048
// delayMs: 2
// largeDataThreshold: 4096
// extremeDataThreshold: 8192
```

#### 稳定模式 (Stable)
```dart
BluetoothPerformanceConfig.stable
// chunkSize: 1024
// delayMs: 5
// largeDataThreshold: 2048
// extremeDataThreshold: 4096
```

## 使用方法

### 基本使用

```dart
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';

// 使用快速模式以获得最快打印速度
FlutterThermalPrinter.instance.configureBluetoothPerformance(
  BluetoothPerformanceConfig.fast
);

// 检查当前配置
final config = FlutterThermalPrinter.instance.getBluetoothPerformanceInfo();
print('Current chunk size: ${config['chunkSize']}');
```

### 自定义配置

```dart
final customConfig = BluetoothPerformanceConfig(
  mode: BluetoothPerformanceMode.fast,
  chunkSize: 4096,
  delayMs: 1,
  largeDataThreshold: 8192,
  extremeDataThreshold: 16384,
);

FlutterThermalPrinter.instance.configureBluetoothPerformance(customConfig);
```

### 重置到默认设置

```dart
FlutterThermalPrinter.instance.resetBluetoothPerformanceToDefault();
```

## 性能提升预期

基于优化措施，预期在以下场景中获得显著性能提升：

1. **小数据打印** (< 4KB)：提升约50%
   - 原因：智能连接管理避免重复验证

2. **中等数据打印** (4KB - 8KB)：提升约30-40%
   - 原因：延迟连接建立，更大的分片大小

3. **大数据打印** (> 8KB)：提升约20-30%
   - 原因：更高效的索引发送和可配置的参数

## 兼容性说明

- 所有优化都向后兼容
- 原有的 `printData` 方法接口保持不变
- 新的性能配置为可选功能，默认使用平衡模式
- Windows平台自动跳过蓝牙相关优化

## 测试建议

1. **不同打印机型号测试**：在不同品牌的热敏打印机上验证性能
2. **数据量测试**：测试不同大小的打印数据（文本、图片）
3. **连续打印测试**：验证智能连接管理的效果
4. **稳定性测试**：确保优化后不影响打印质量

## 注意事项

1. **快速模式可能在某些老式打印机上不稳定**，此时建议使用稳定模式
2. **配置更改在下次打印任务中生效**
3. **连接失败的设备会自动尝试重新连接**
4. **极端大数据(>12KB)时建议测试分片发送的稳定性**
