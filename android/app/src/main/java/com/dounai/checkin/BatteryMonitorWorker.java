package com.dounai.checkin;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.BatteryManager;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

public class BatteryMonitorWorker extends Worker {
    private static final int ALERT_BELOW_PERCENT = 10;
    private static final int RESET_AT_PERCENT = 15;

    public BatteryMonitorWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context context = getApplicationContext();
        SharedPreferences settings = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        if (!settings.getBoolean("battery_alert_enabled", false)) return Result.success();
        if (settings.getString("bark_key", "").trim().isEmpty()) return Result.success();

        BatteryState state = readBatteryState(context);
        if (state.percent < 0) {
            settings.edit().putString("last_battery_result", "暂时无法读取手机电量")
                    .putLong("last_battery_check_at", System.currentTimeMillis()).apply();
            return Result.success();
        }

        boolean sent = settings.getBoolean("battery_alert_sent", false);
        String result = "当前电量 " + state.percent + "%" + (state.charging ? "，正在充电" : "");
        SharedPreferences.Editor editor = settings.edit()
                .putInt("last_battery_level", state.percent)
                .putLong("last_battery_check_at", System.currentTimeMillis());

        if (shouldReset(state.percent, state.charging)) {
            sent = false;
            editor.putBoolean("battery_alert_sent", false);
        }
        if (shouldNotify(state.percent, state.charging, sent)) {
            String error = Notifications.sendLowBattery(context, state.percent);
            if (error.isEmpty()) {
                editor.putBoolean("battery_alert_sent", true);
                result += "；已发送低电量 Bark";
            } else {
                result += "；Bark 发送失败：" + error;
            }
        }
        editor.putString("last_battery_result", result).apply();
        return Result.success();
    }

    static boolean shouldNotify(int percent, boolean charging, boolean sent) {
        return percent >= 0 && percent < ALERT_BELOW_PERCENT && !charging && !sent;
    }

    static boolean shouldReset(int percent, boolean charging) {
        return charging || percent >= RESET_AT_PERCENT;
    }

    private static BatteryState readBatteryState(Context context) {
        Intent status = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (status == null) return new BatteryState(-1, false);
        int level = status.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = status.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        int batteryStatus = status.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN);
        boolean charging = batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING
                || batteryStatus == BatteryManager.BATTERY_STATUS_FULL;
        int percent = level >= 0 && scale > 0 ? Math.round(level * 100f / scale) : -1;
        return new BatteryState(percent, charging);
    }

    private static final class BatteryState {
        final int percent;
        final boolean charging;

        BatteryState(int percent, boolean charging) {
            this.percent = percent;
            this.charging = charging;
        }
    }
}
