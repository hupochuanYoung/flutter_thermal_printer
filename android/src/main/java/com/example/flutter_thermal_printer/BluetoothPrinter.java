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

import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import io.flutter.plugin.common.EventChannel;

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

    private void createBluetoothReceiver() {
        bluetoothReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                String action = intent.getAction();
                
                if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                    BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                    Log.d(TAG, "Bluetooth device found");
                    sendDevice(device);
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

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
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
        events.success(deviceData);
    }

    BluetoothPrinter(Context context) {
        BluetoothPrinter.context = context;
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
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
        
        if (isScanning) {
            Log.d(TAG, "Already scanning");
            return;
        }
        
        discoveredDevices.clear();
        bluetoothAdapter.startDiscovery();
        Log.d(TAG, "Started Bluetooth scan");
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