package com.example.flutter_thermal_printer.utils;
import com.example.flutter_thermal_printer.BuildConfig;

import android.util.Log;



public class AppLogger {
    private static final boolean ENABLE_LOGGING = BuildConfig.IS_LOGGING_ENABLED;
    private static final String DEFAULT_TAG = "APP_LOG";
    private static long lastLogTime = 0;
    private static final int LOG_INTERVAL_MS = 1000;

    public static void d(String tag, String message) {
        if (ENABLE_LOGGING)
            Log.d(tag, message);
    }

    public static void i(String tag, String message) {
        if (ENABLE_LOGGING) Log.i(tag, message);
    }

    public static void w(String tag, String message) {
        if (ENABLE_LOGGING) Log.w(tag, message);
    }

    public static void e(String tag, String message) {
        if (ENABLE_LOGGING)
            Log.e(tag, message);
    }

    public static void e(String tag, String message, Throwable t) {
        if (ENABLE_LOGGING)
            Log.e(tag, message, t);
    }

    public static void logThrottled(String tag, String message) {
        long current = System.currentTimeMillis();
        if (current - lastLogTime > LOG_INTERVAL_MS) {
            d(tag, message);
            lastLogTime = current;
        }
    }

    public static void logIfChanged(String tag, String message, String lastLogged) {
        if (!message.equals(lastLogged)) {
            d(tag, message);
        }
    }
}
