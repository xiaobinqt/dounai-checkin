package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

import java.util.concurrent.TimeUnit;

final class BatteryMonitorScheduler {
    private static final String PERIODIC_WORK = "dounai-battery-monitor";
    private static final String IMMEDIATE_WORK = "dounai-battery-monitor-now";

    static void schedule(Context context) {
        SharedPreferences settings = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        WorkManager manager = WorkManager.getInstance(context);
        boolean enabled = settings.getBoolean("battery_alert_enabled", false);
        boolean hasBark = !settings.getString("bark_key", "").trim().isEmpty();
        if (!enabled || !hasBark) {
            cancel(context);
            settings.edit().putBoolean("battery_alert_sent", false).apply();
            return;
        }
        Constraints network = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();
        PeriodicWorkRequest periodic = new PeriodicWorkRequest.Builder(
                BatteryMonitorWorker.class, 15, TimeUnit.MINUTES)
                .setConstraints(network)
                .build();
        manager.enqueueUniquePeriodicWork(PERIODIC_WORK, ExistingPeriodicWorkPolicy.UPDATE, periodic);

        OneTimeWorkRequest immediate = new OneTimeWorkRequest.Builder(BatteryMonitorWorker.class)
                .setConstraints(network)
                .build();
        manager.enqueueUniqueWork(IMMEDIATE_WORK, ExistingWorkPolicy.REPLACE, immediate);
    }

    static void cancel(Context context) {
        WorkManager manager = WorkManager.getInstance(context);
        manager.cancelUniqueWork(PERIODIC_WORK);
        manager.cancelUniqueWork(IMMEDIATE_WORK);
    }

    private BatteryMonitorScheduler() {}
}
