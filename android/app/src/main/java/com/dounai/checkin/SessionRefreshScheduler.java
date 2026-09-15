package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.work.Constraints;
import androidx.work.ExistingWorkPolicy;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

import java.util.concurrent.TimeUnit;

final class SessionRefreshScheduler {
    private static final String WORK_NAME = "dounai-session-refresh";
    private static final String EXPIRY_WORK_NAME = "dounai-session-expiry-notice";

    static void schedule(Context context) {
        SharedPreferences settings = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        SharedPreferences site = context.getSharedPreferences("site", Context.MODE_PRIVATE);
        WorkManager manager = WorkManager.getInstance(context);
        if (!settings.getBoolean("auto_enabled", false)
                || site.getString("cookie", "").trim().isEmpty()) {
            manager.cancelUniqueWork(WORK_NAME);
            return;
        }
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(SessionRefreshWorker.class, 3, TimeUnit.HOURS)
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        manager.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request);
    }

    static void notifyExpiry(Context context) {
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(SessionRefreshWorker.class)
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        WorkManager.getInstance(context).enqueueUniqueWork(EXPIRY_WORK_NAME, ExistingWorkPolicy.KEEP, request);
    }

    private SessionRefreshScheduler() {}
}
