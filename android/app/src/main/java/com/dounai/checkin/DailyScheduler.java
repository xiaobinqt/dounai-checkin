package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;

import java.util.Calendar;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

final class DailyScheduler {
    private static final String WORK_NAME = "dounai-daily";

    static void schedule(Context context) {
        schedule(context, ExistingWorkPolicy.REPLACE);
    }

    static void scheduleNext(Context context) {
        schedule(context, ExistingWorkPolicy.APPEND_OR_REPLACE);
    }

    private static void schedule(Context context, ExistingWorkPolicy policy) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        WorkManager manager = WorkManager.getInstance(context);
        if (!prefs.getBoolean("auto_enabled", false)) {
            manager.cancelUniqueWork(WORK_NAME);
            return;
        }
        String[] pieces = prefs.getString("checkin_time", "09:17").split(":");
        int hour = Integer.parseInt(pieces[0]), minute = Integer.parseInt(pieces[1]);
        Calendar target = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"));
        target.set(Calendar.HOUR_OF_DAY, hour);
        target.set(Calendar.MINUTE, minute);
        target.set(Calendar.SECOND, 0);
        target.set(Calendar.MILLISECOND, 0);
        if (target.getTimeInMillis() <= System.currentTimeMillis()) target.add(Calendar.DATE, 1);
        long delay = target.getTimeInMillis() - System.currentTimeMillis();
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(CheckInWorker.class)
                .setInputData(new Data.Builder().putBoolean("automatic", true).build())
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        manager.enqueueUniqueWork(WORK_NAME, policy, request);
    }

    static void checkInNow(Context context) {
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(CheckInWorker.class)
                .setInputData(new Data.Builder().putBoolean("automatic", false).build())
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        WorkManager.getInstance(context).enqueue(request);
    }

    private DailyScheduler() {}
}
