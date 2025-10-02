// 蓝牙性能优化配置选项
enum BluetoothPerformanceMode {
  fast, // 快速模式：优先速度，最小延迟
  balanced, // 平衡模式：默认配置
  stable, // 稳定模式：优先稳定性，较慢但可靠
}

class BluetoothPerformanceConfig {
  final BluetoothPerformanceMode mode;
  final int chunkSize;
  final int delayMs;
  final int largeDataThreshold;
  final int extremeDataThreshold;
  final bool enableSmartReconnection;

  const BluetoothPerformanceConfig({
    required this.mode,
    this.chunkSize = 2048,
    this.delayMs = 2,
    this.largeDataThreshold = 4096,
    this.extremeDataThreshold = 8192,
    this.enableSmartReconnection = true,
  });

  // 根据连接失败次数自动调整配置
  static BluetoothPerformanceConfig adaptive(int failureCount) {
    if (failureCount >= 3) {
      return conservative; // 多次失败使用最保守配置
    } else if (failureCount >= 2) {
      return stable; // 中等失败使用稳定配置
    } else {
      return balanced; // 正常情况使用平衡配置
    }
  }

  static const BluetoothPerformanceConfig fast = BluetoothPerformanceConfig(
    mode: BluetoothPerformanceMode.fast,
    chunkSize: 3072, // 更大分片
    delayMs: 0, // 无延迟
    largeDataThreshold: 4096,
    extremeDataThreshold: 12288,
    enableSmartReconnection: true,
  );

  static const BluetoothPerformanceConfig balanced = BluetoothPerformanceConfig(
    mode: BluetoothPerformanceMode.balanced,
    chunkSize: 2048,
    delayMs: 2,
    largeDataThreshold: 4096,
    extremeDataThreshold: 8192,
    enableSmartReconnection: true,
  );

  static const BluetoothPerformanceConfig stable = BluetoothPerformanceConfig(
    mode: BluetoothPerformanceMode.stable,
    chunkSize: 1024, // 较小分片
    delayMs: 5, // 更多延迟
    largeDataThreshold: 2048,
    extremeDataThreshold: 4096,
    enableSmartReconnection: false,
  );

  // 针对易断开连接的保守配置
  static const BluetoothPerformanceConfig conservative =
      BluetoothPerformanceConfig(
    mode: BluetoothPerformanceMode.stable,
    chunkSize: 512, // 更小的分片以增强稳定性
    delayMs: 10, // 更多延迟
    largeDataThreshold: 1024, // 更早启用分片
    extremeDataThreshold: 2048,
    enableSmartReconnection: true,
  );
}
