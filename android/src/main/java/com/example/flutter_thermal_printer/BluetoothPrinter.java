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
    private final Context context;

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
                        Log.d("BT", "发现设备: " + device.getName() + " - " + device.getAddress() + " RSSI: " + rssi + " Type: " + deviceType);
                        
                        // 只处理经典蓝牙设备
                        if (device.getType() == BluetoothDevice.DEVICE_TYPE_CLASSIC || 
                            device.getType() == BluetoothDevice.DEVICE_TYPE_DUAL) {
                            sendDevice(device);
                        } else {
                            Log.d(TAG, "Skipping BLE-only device: " + device.getName());
                        }
                    } else {
                        Log.e(TAG, "ACTION_FOUND received but device is null");
                    }
                } else if (BluetoothAdapter.ACTION_DISCOVERY_STARTED.equals(action)) {
                    Log.d(TAG, "Bluetooth discovery started");
                    isScanning = true;
                } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                    Log.d(TAG, "Bluetooth discovery finished");
                    isScanning = false;
                } else {
                    Log.d(TAG, "Received other action: " + action);
                }
            }
        };
        
        // 添加延迟检查，如果广播没有触发，手动设置状态
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (bluetoothAdapter.isDiscovering() && !isScanning) {
                Log.d(TAG, "Broadcast not received, manually setting isScanning to true");
                isScanning = true;
            }
        }, 1000);
    }

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
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(bluetoothReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                context.registerReceiver(bluetoothReceiver, filter);
            }
            Log.d(TAG, "Bluetooth receiver registered successfully");
        } catch (Exception e) {
            Log.e(TAG, "Failed to register Bluetooth receiver: " + e.getMessage());
        }
    }

    @Override
    public void onCancel(Object arguments) {
        if (events != null) {
            context.unregisterReceiver(bluetoothReceiver);
            events = null;
        }
    }

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

        Log.d(TAG, "Sending device data: " + deviceData);
        new Handler(Looper.getMainLooper()).post(() -> {
            if (events != null) events.success(deviceData);
        });

    }

    BluetoothPrinter(Context context) {
        this.context = context.getApplicationContext();
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
        
        // 检查设备蓝牙能力
        if (bluetoothAdapter != null) {
            Log.d(TAG, "Bluetooth adapter found");
            Log.d(TAG, "Bluetooth adapter state: " + bluetoothAdapter.getState());
            Log.d(TAG, "Bluetooth adapter is enabled: " + bluetoothAdapter.isEnabled());
            
            // 检查设备支持的蓝牙类型
            checkBluetoothCapabilities();
            
            // 检查已配对的设备
            checkPairedDevices();
        } else {
            Log.e(TAG, "Bluetooth adapter is null - device may not support Bluetooth");
        }
    }

    private void checkBluetoothCapabilities() {
        Log.d(TAG, "=== Bluetooth Capabilities Check ===");
        
        // 检查是否支持经典蓝牙
        boolean supportsClassic = bluetoothAdapter.getProfileConnectionState(BluetoothProfile.HEADSET) != BluetoothProfile.STATE_DISCONNECTED ||
                                 bluetoothAdapter.getProfileConnectionState(BluetoothProfile.A2DP) != BluetoothProfile.STATE_DISCONNECTED ||
                                 bluetoothAdapter.getProfileConnectionState(BluetoothProfile.HID_HOST) != BluetoothProfile.STATE_DISCONNECTED;
        
        Log.d(TAG, "Supports Classic Bluetooth: " + supportsClassic);
        
        // 检查是否支持 BLE
        boolean supportsBLE = false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            supportsBLE = context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE);
        }
        Log.d(TAG, "Supports BLE: " + supportsBLE);
        
        // 检查设备类型
        Log.d(TAG, "Device Bluetooth Type: " + getBluetoothTypeString());
        
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

    private String getBluetoothTypeString() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            boolean supportsBLE = context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE);
            boolean supportsClassic = bluetoothAdapter.getProfileConnectionState(BluetoothProfile.HEADSET) != BluetoothProfile.STATE_DISCONNECTED ||
                                     bluetoothAdapter.getProfileConnectionState(BluetoothProfile.A2DP) != BluetoothProfile.STATE_DISCONNECTED;
            
            if (supportsBLE && supportsClassic) {
                return "Dual Mode (Classic + BLE)";
            } else if (supportsBLE) {
                return "BLE Only";
            } else if (supportsClassic) {
                return "Classic Only";
            } else {
                return "Unknown";
            }
        } else {
            return "Classic Only (Android < 4.3)";
        }
    }

    private void checkPairedDevices() {
        Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
        Log.d(TAG, "=== Paired Devices Check ===");
        Log.d(TAG, "Number of paired devices: " + pairedDevices.size());
        
        for (BluetoothDevice device : pairedDevices) {
            String deviceType = getDeviceTypeString(device.getType());
            Log.d(TAG, "Paired device: " + device.getName() + " - " + device.getAddress() + " - Type: " + deviceType);
        }
        Log.d(TAG, "=== End Paired Devices Check ===");
    }

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

    public void turnOnBluetooth() {
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter is null");
            return;
        }
        
        // 检查蓝牙是否已经启用
        if (bluetoothAdapter.isEnabled()) {
            Log.d(TAG, "Bluetooth is already enabled");
            return;
        }
        
        // 检查权限
        if (!checkBluetoothPermission()) {
            Log.e(TAG, "Bluetooth permissions not granted");
            return;
        }
        
        // 使用 Intent 请求用户启用蓝牙
        Intent enableBtIntent = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
        enableBtIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(enableBtIntent);
            Log.d(TAG, "Bluetooth enable request sent to user");
        } catch (Exception e) {
            Log.e(TAG, "Failed to start Bluetooth enable activity: " + e.getMessage());
            // 如果无法启动 Activity，回退到直接启用
            bluetoothAdapter.enable();
        }
    }

    public boolean checkBluetoothPermission() {
        // Check for BLUETOOTH_CONNECT permission on Android 12+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(context,
                    Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "BLUETOOTH_CONNECT permission not granted");
                return false;
            }
            if (ContextCompat.checkSelfPermission(context,
                    Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "BLUETOOTH_SCAN permission not granted");
                return false;
            }
        } else {
            // For Android 11 and below, check location permissions
            if (ContextCompat.checkSelfPermission(context,
                    Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "ACCESS_FINE_LOCATION permission not granted");
                return false;
            }
        }

        return true;
    }

    public List<Map<String, Object>> getBluetoothDevicesList() {
        List<Map<String, Object>> data = new ArrayList<>();

        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter is null");
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
            data.add(deviceData);
        }

        return data;
    }

    public void startScan() {
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter is null");
            return;
        }

        if (!bluetoothAdapter.isEnabled()) {
            Log.e(TAG, "Bluetooth is not enabled");
            return;
        }

        if (!checkBluetoothPermission()) {
            Log.e(TAG, "Bluetooth permissions not granted");
            return;
        }

        if (isScanning) {
            Log.d(TAG, "Already scanning");
            return;
        }

        // 检查是否正在发现设备
        if (bluetoothAdapter.isDiscovering()) {
            Log.d(TAG, "Bluetooth is already discovering, canceling previous discovery");
            bluetoothAdapter.cancelDiscovery();
        }

        discoveredDevices.clear();
        
        // 添加更详细的日志
        Log.d(TAG, "About to start Bluetooth discovery");
        Log.d(TAG, "Bluetooth adapter state: " + bluetoothAdapter.getState());
        Log.d(TAG, "Bluetooth adapter is discovering: " + bluetoothAdapter.isDiscovering());
        
        // 检查权限状态
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            boolean hasScan = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED;
            boolean hasConnect = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
            Log.d(TAG, "Android 12+ permissions - SCAN: " + hasScan + ", CONNECT: " + hasConnect);
        } else {
            boolean hasLocation = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
            Log.d(TAG, "Android 11- permissions - LOCATION: " + hasLocation);
        }
        
        boolean discoveryStarted = bluetoothAdapter.startDiscovery();
        Log.d(TAG, "Bluetooth discovery start result: " + discoveryStarted);
        
        if (!discoveryStarted) {
            Log.e(TAG, "Failed to start Bluetooth discovery");
            return;
        }
        
        // 手动设置 isScanning 状态，因为广播可能不会触发
        isScanning = true;
        Log.d(TAG, "Manually set isScanning to true");
        
        Log.d(TAG, "Started Bluetooth scan");
        
        // 添加延迟检查
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            Log.d(TAG, "After 2 seconds - is discovering: " + bluetoothAdapter.isDiscovering());
            Log.d(TAG, "After 2 seconds - is scanning: " + isScanning);
            
            // 如果发现完成，手动设置 isScanning 为 false
            if (!bluetoothAdapter.isDiscovering()) {
                isScanning = false;
                Log.d(TAG, "Manually set isScanning to false (discovery finished)");
            }
        }, 2000);
    }

    public void stopScan() {
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter is null");
            return;
        }

        if (!isScanning) {
            Log.d(TAG, "Not currently scanning");
            return;
        }

        bluetoothAdapter.cancelDiscovery();
        Log.d(TAG, "Stopped Bluetooth scan");
    }

    public void connect(String address) {
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter is null");
            return;
        }

        try {
            // 停止扫描
            if (isScanning) {
                bluetoothAdapter.cancelDiscovery();
            }

            BluetoothDevice device = bluetoothAdapter.getRemoteDevice(address);
            if (device == null) {
                Log.e(TAG, "Device not found: " + address);
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
            Log.e(TAG, "Connection failed: " + e.getMessage());
            closeConnection(address);
        }
    }

    public void printText(String address, List<Integer> bytes) {
        if (!isConnected(address)) {
            Log.e(TAG, "Not connected to device: " + address);
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
            Log.e(TAG, "Print failed to " + address + ": " + e.getMessage());
        }
    }

    public boolean isConnected(String address) {
        if (bluetoothAdapter == null) {
            return false;
        }

        BluetoothSocket socket = bluetoothSockets.get(address);
        return socket != null && socket.isConnected();
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
            Log.e(TAG, "Disconnect failed for " + address + ": " + e.getMessage());
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
            Log.e(TAG, "Error closing connection for " + address + ": " + e.getMessage());
        }
    }

    // 断开所有连接
    public void disconnectAll() {
        for (String address : new ArrayList<>(bluetoothSockets.keySet())) {
            disconnect(address);
        }
    }

}