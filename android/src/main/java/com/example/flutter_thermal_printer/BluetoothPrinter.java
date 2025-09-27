package com.example.flutter_thermal_printer;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.util.Log;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import androidx.core.content.ContextCompat;
import android.content.pm.PackageManager;
import android.Manifest;
import io.flutter.plugin.common.EventChannel;
import android.bluetooth.BluetoothProfile;

public class BluetoothPrinter implements EventChannel.StreamHandler {
    @SuppressLint("StaticFieldLeak")
    private static Context context;


    private static final String TAG = "BluetoothPrinter";
    private static final UUID SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");

    private EventChannel.EventSink events;
    private BluetoothAdapter bluetoothAdapter;
    private BroadcastReceiver bluetoothReceiver;
    private List<BluetoothDevice> discoveredDevices = new ArrayList<>();
    private boolean isScanning = false;

    // 存储多个蓝牙连接
    private Map<String, BluetoothSocket> bluetoothSockets = new HashMap<>();
    private Map<String, OutputStream> outputStreams = new HashMap<>();

    BluetoothPrinter(Context context) {
        System.out.println("BluetoothPrinter 构造函数执行");

        BluetoothPrinter.context = context;
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();

        // 检查设备蓝牙能力
        if (bluetoothAdapter != null) {
            Log.d(TAG, "Bluetooth adapter found");
            checkBluetoothCapabilities();
        } else {
            Log.d(TAG, "Bluetooth adapter is null - device may not support Bluetooth");
        }
    }

    // 检查蓝牙权限 - 参考 Kotlin 实现
    public boolean isPermissionBluetoothGranted() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ 需要新的权限
            boolean hasScan = ContextCompat.checkSelfPermission(context, 
                Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED;
            boolean hasConnect = ContextCompat.checkSelfPermission(context, 
                Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
            return hasScan && hasConnect;
        } else {
            // Android 11 及以下需要位置权限
            boolean hasLocation = ContextCompat.checkSelfPermission(context, 
                Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
            boolean hasBluetooth = ContextCompat.checkSelfPermission(context, 
                Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED;
            boolean hasBluetoothAdmin = ContextCompat.checkSelfPermission(context, 
                Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED;
            return hasLocation && hasBluetooth && hasBluetoothAdmin;
        }
    }

    // 检查蓝牙是否启用 - 参考 Kotlin 实现
    public boolean bluetoothEnabled() {
        return bluetoothAdapter != null && bluetoothAdapter.isEnabled();
    }

    // 获取已配对的蓝牙设备 - 参考 Kotlin 实现
    public List<Map<String, Object>> pairedBluetooths() {
        List<Map<String, Object>> data = new ArrayList<>();
        
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            Log.d(TAG, "Bluetooth adapter is null or not enabled");
            return data;
        }

        Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
        for (BluetoothDevice device : pairedDevices) {
            HashMap<String, Object> deviceData = new HashMap<>();
            deviceData.put("address", device.getAddress());
            deviceData.put("name", device.getName() != null ? device.getName() : "Unknown Device");
            deviceData.put("connectionType", "BLUETOOTH_CLASSIC");
            deviceData.put("isConnected", isConnected(device.getAddress()));
            deviceData.put("bondState", device.getBondState());
            deviceData.put("deviceType", getDeviceTypeString(device.getType()));
            data.add(deviceData);
        }

        return data;
    }

    // 开始蓝牙扫描 - 改进版本
    public void startScan() {
        if (bluetoothAdapter == null) {
            Log.d(TAG, "Bluetooth adapter is null");
            return;
        }

        if (!bluetoothAdapter.isEnabled()) {
            Log.d(TAG, "Bluetooth is not enabled");
            return;
        }

        if (!isPermissionBluetoothGranted()) {
            Log.d(TAG, "Bluetooth permissions not granted");
            return;
        }

        if (isScanning) {
            Log.d(TAG, "Already scanning");
            return;
        }

        // 停止之前的扫描
        if (bluetoothAdapter.isDiscovering()) {
            Log.d(TAG, "Bluetooth is already discovering, canceling previous discovery");
            bluetoothAdapter.cancelDiscovery();
        }

        discoveredDevices.clear();
        
        Log.d(TAG, "Starting Bluetooth discovery");
        boolean discoveryStarted = bluetoothAdapter.startDiscovery();
        Log.d(TAG, "Bluetooth discovery start result: " + discoveryStarted);
        
        if (discoveryStarted) {
            isScanning = true;
            Log.d(TAG, "Bluetooth scan started successfully");
        } else {
            Log.d(TAG, "Failed to start Bluetooth discovery");
        }
    }

    // 停止蓝牙扫描
    public void stopScan() {
        if (bluetoothAdapter == null) {
            Log.d(TAG, "Bluetooth adapter is null");
            return;
        }

        if (!isScanning) {
            Log.d(TAG, "Not currently scanning");
            return;
        }

        bluetoothAdapter.cancelDiscovery();
        isScanning = false;
        Log.d(TAG, "Bluetooth scan stopped");
    }

    // 创建蓝牙接收器 - 改进版本
    private void createBluetoothReceiver() {
        Log.d(TAG, "Creating Bluetooth receiver");
        bluetoothReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                String action = intent.getAction();
                Log.d(TAG, "Bluetooth receiver received action: " + action);

                if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                    BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                    if (device != null) {
                        short rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE);
                        String deviceType = getDeviceTypeString(device.getType());
                        Log.d("BT", "发现设备: " + device.getName() + " - " + device.getAddress() + 
                              " RSSI: " + rssi + " Type: " + deviceType);
                        
                        // 只处理经典蓝牙设备
                        if (device.getType() == BluetoothDevice.DEVICE_TYPE_CLASSIC || 
                            device.getType() == BluetoothDevice.DEVICE_TYPE_DUAL) {
                            sendDevice(device);
                        } else {
                            Log.d(TAG, "Skipping BLE-only device: " + device.getName());
                        }
                    } else {
                        Log.d(TAG, "ACTION_FOUND received but device is null");
                    }
                } else if (BluetoothAdapter.ACTION_DISCOVERY_STARTED.equals(action)) {
                    Log.d(TAG, "Bluetooth discovery started");
                    isScanning = true;
                } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                    Log.d(TAG, "Bluetooth discovery finished");
                    isScanning = false;
                }
            }
        };
    }

    // 发送设备信息到 Flutter
    private void sendDevice(BluetoothDevice device) {
        if (device == null) {
            Log.d(TAG, "Device is null.");
            return;
        }

        boolean isConnected = isConnected(device.getAddress());
        HashMap<String, Object> deviceData = new HashMap<>();
        deviceData.put("address", device.getAddress());
        deviceData.put("name", device.getName() != null ? device.getName() : "Unknown Device");
        deviceData.put("connectionType", "BLUETOOTH_CLASSIC");
        deviceData.put("isConnected", isConnected);
        deviceData.put("bondState", device.getBondState());
        deviceData.put("deviceType", getDeviceTypeString(device.getType()));

        Log.d(TAG, "Sending device data: " + deviceData);
        new Handler(Looper.getMainLooper()).post(() -> {
            if (events != null) events.success(deviceData);
        });
    }

    // 获取设备类型字符串
    private String getDeviceTypeString(int type) {
        switch (type) {
            case BluetoothDevice.DEVICE_TYPE_CLASSIC:
                return "Classic";
            case BluetoothDevice.DEVICE_TYPE_LE:
                return "BLE";
            case BluetoothDevice.DEVICE_TYPE_DUAL:
                return "Dual";
            default:
                return "Unknown (" + type + ")";
        }
    }

    // 检查设备蓝牙能力
    private void checkBluetoothCapabilities() {
        Log.d(TAG, "=== Bluetooth Capabilities Check ===");
        
        // 检查是否支持 BLE
        boolean supportsBLE = false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            supportsBLE = context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE);
        }
        Log.d(TAG, "Supports BLE: " + supportsBLE);
        
        // 检查已配对的设备类型
        Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
        int classicCount = 0;
        int bleCount = 0;
        int dualCount = 0;
        
        for (BluetoothDevice device : pairedDevices) {
            int type = device.getType();
            switch (type) {
                case BluetoothDevice.DEVICE_TYPE_CLASSIC:
                    classicCount++;
                    break;
                case BluetoothDevice.DEVICE_TYPE_LE:
                    bleCount++;
                    break;
                case BluetoothDevice.DEVICE_TYPE_DUAL:
                    dualCount++;
                    break;
            }
        }
        
        Log.d(TAG, "Paired devices - Classic: " + classicCount + ", BLE: " + bleCount + ", Dual: " + dualCount);
        Log.d(TAG, "=== End Capabilities Check ===");
    }

    // EventChannel.StreamHandler 实现
    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        Log.d(TAG, "onListen called - setting up Bluetooth receiver");
        this.events = events;
        IntentFilter filter = new IntentFilter();
        filter.addAction(BluetoothDevice.ACTION_FOUND);
        filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED);
        filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);

        createBluetoothReceiver();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(bluetoothReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            context.registerReceiver(bluetoothReceiver, filter);
        }
        Log.d(TAG, "Bluetooth receiver registered successfully");
    }

    @Override
    public void onCancel(Object arguments) {
        if (events != null) {
            context.unregisterReceiver(bluetoothReceiver);
            events = null;
        }
    }

    public void turnOnBluetooth() {
        if (bluetoothAdapter == null) {
            Log.d(TAG, "Bluetooth adapter is null");
            return;
        }
        
        // 检查蓝牙是否已经启用
        if (bluetoothAdapter.isEnabled()) {
            Log.d(TAG, "Bluetooth is already enabled");
            return;
        }
        
        // 检查权限
        if (!isPermissionBluetoothGranted()) {
            Log.d(TAG, "Bluetooth permissions not granted");
            return;
        }
        
        // 使用 Intent 请求用户启用蓝牙
        Intent enableBtIntent = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
        enableBtIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(enableBtIntent);
            Log.d(TAG, "Bluetooth enable request sent to user");
        } catch (Exception e) {
            Log.d(TAG, "Failed to start Bluetooth enable activity: " + e.getMessage());
            // 如果无法启动 Activity，回退到直接启用
            bluetoothAdapter.enable();
        }
    }

    public boolean checkBluetoothPermission() {
        return isPermissionBluetoothGranted();
    }

    public List<Map<String, Object>> getBluetoothDevicesList() {
        return pairedBluetooths();
    }

    public boolean isConnected(String address) {
        if (bluetoothAdapter == null) {
            return false;
        }

        BluetoothSocket socket = bluetoothSockets.get(address);
        return socket != null && socket.isConnected();
    }

    public void connect(String address) {
        if (bluetoothAdapter == null) {
            Log.d(TAG, "Bluetooth adapter is null");
            return;
        }

        try {
            // 停止扫描
            if (isScanning) {
                bluetoothAdapter.cancelDiscovery();
            }

            BluetoothDevice device = bluetoothAdapter.getRemoteDevice(address);
            if (device == null) {
                Log.d(TAG, "Device not found: " + address);
                return;
            }

            // 创建RFCOMM socket
            BluetoothSocket socket = device.createRfcommSocketToServiceRecord(SPP_UUID);
            socket.connect();

            // 获取输出流
            OutputStream outputStream = socket.getOutputStream();

            // 存储连接
            bluetoothSockets.put(address, socket);
            outputStreams.put(address, outputStream);

            Log.d(TAG, "Connected to device: " + device.getName() + " - " + address);

        } catch (IOException e) {
            Log.d(TAG, "Connection failed: " + e.getMessage());
            closeConnection(address);
        }
    }

    public void printText(String address, List<Integer> bytes) {
        if (!isConnected(address)) {
            Log.d(TAG, "Not connected to device: " + address);
            return;
        }

        try {
            byte[] data = new byte[bytes.size()];
            for (int i = 0; i < bytes.size(); i++) {
                data[i] = bytes.get(i).byteValue();
            }

            OutputStream outputStream = outputStreams.get(address);
            if (outputStream != null) {
                outputStream.write(data);
                outputStream.flush();
                Log.d(TAG, "Data sent successfully to " + address + ", size: " + data.length);
            }

        } catch (IOException e) {
            Log.d(TAG, "Print failed to " + address + ": " + e.getMessage());
        }
    }

    public boolean disconnect(String address) {
        try {
            OutputStream outputStream = outputStreams.get(address);
            if (outputStream != null) {
                outputStream.close();
                outputStreams.remove(address);
            }

            BluetoothSocket socket = bluetoothSockets.get(address);
            if (socket != null) {
                socket.close();
                bluetoothSockets.remove(address);
            }

            Log.d(TAG, "Disconnected from device: " + address);
            return true;

        } catch (IOException e) {
            Log.d(TAG, "Disconnect failed for " + address + ": " + e.getMessage());
            return false;
        }
    }

    private void closeConnection(String address) {
        try {
            OutputStream outputStream = outputStreams.get(address);
            if (outputStream != null) {
                outputStream.close();
                outputStreams.remove(address);
            }

            BluetoothSocket socket = bluetoothSockets.get(address);
            if (socket != null) {
                socket.close();
                bluetoothSockets.remove(address);
            }
        } catch (IOException e) {
            Log.d(TAG, "Error closing connection for " + address + ": " + e.getMessage());
        }
    }

    // 断开所有连接
    public void disconnectAll() {
        for (String address : new ArrayList<>(bluetoothSockets.keySet())) {
            disconnect(address);
        }
    }

}