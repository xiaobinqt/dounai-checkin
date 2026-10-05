package com.dounai.checkin;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;

import java.util.Calendar;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

final class DailyScheduler {
    private static final String WORK_NAME = "dounai-daily";
    private static final String WORK_TAG = "dounai-checkin";
    private static final String ALARM_WORK_PREFIX = "dounai-alarm-";
    private static final int ALARM_REQUEST_CODE = 2105;

    static void schedule(Context context) {
        schedule(context, ExistingWorkPolicy.REPLACE);
        SessionRefreshScheduler.schedule(context);
    }

    static void scheduleNext(Context context) {
        schedule(context, ExistingWorkPolicy.APPEND_OR_REPLACE);
    }

    static void restore(Context context) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        if (prefs.getBoolean("auto_enabled", false)) schedule(context, ExistingWorkPolicy.REPLACE);
        else cancelAlarm(context);
    }

    static void ensureAlarm(Context context) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        if (!prefs.getBoolean("auto_enabled", false)) return;
        // Re-register every time the app opens. A force-stop can remove the actual alarm while
        // leaving the PendingIntent token alive, so FLAG_NO_CREATE cannot prove an alarm exists.
        long triggerAt = nextTrigger(prefs);
        String mode = scheduleAlarm(context, triggerAt);
        DiagnosticLog.add(context, "daily alarm ensured target=" + format(triggerAt)
                + " alarm=" + mode);
    }

    private static void schedule(Context context, ExistingWorkPolicy policy) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        WorkManager manager = WorkManager.getInstance(context);
        if (!prefs.getBoolean("auto_enabled", false)) {
            manager.cancelUniqueWork(WORK_NAME);
            cancelAlarm(context);
            DiagnosticLog.add(context, "daily schedule disabled");
            return;
        }
        long triggerAt = nextTrigger(prefs);
        long delay = triggerAt - System.currentTimeMillis();
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(CheckInWorker.class)
                .addTag(WORK_TAG)
                .setInputData(new Data.Builder().putBoolean("automatic", true).build())
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .setBackoffCriteria(androidx.work.BackoffPolicy.LINEAR, 5, TimeUnit.MINUTES)
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        manager.enqueueUniqueWork(WORK_NAME, policy, request);
        String alarmMode = scheduleAlarm(context, triggerAt);
        DiagnosticLog.add(context, "daily scheduled target=" + format(triggerAt)
                + " workPolicy=" + policy + " alarm=" + alarmMode);
    }

    static void checkInNow(Context context) {
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(CheckInWorker.class)
                .addTag(WORK_TAG)
                .setInputData(new Data.Builder().putBoolean("automatic", false).build())
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        WorkManager.getInstance(context).enqueue(request);
        DiagnosticLog.add(context, "manual check-in queued " + DiagnosticLog.screenState(context));
    }

    static void onAlarm(Context context) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        DiagnosticLog.add(context, "daily alarm received " + DiagnosticLog.screenState(context));
        if (!prefs.getBoolean("auto_enabled", false)) {
            DiagnosticLog.add(context, "daily alarm ignored; automatic check-in disabled");
            cancelAlarm(context);
            return;
        }
        SimpleDateFormat dayFormat = new SimpleDateFormat("yyyyMMdd", Locale.US);
        dayFormat.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        String day = dayFormat.format(new Date());
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(CheckInWorker.class)
                .addTag(WORK_TAG)
                .setInputData(new Data.Builder().putBoolean("automatic", true)
                        .putString("source", "alarm").build())
                .setBackoffCriteria(androidx.work.BackoffPolicy.LINEAR, 5, TimeUnit.MINUTES)
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build();
        WorkManager.getInstance(context).enqueueUniqueWork(
                ALARM_WORK_PREFIX + day, ExistingWorkPolicy.KEEP, request);
        long next = nextTrigger(prefs);
        String mode = scheduleAlarm(context, next);
        DiagnosticLog.add(context, "alarm check-in queued; next=" + format(next) + " alarm=" + mode);
    }

    static void cancel(Context context) {
        WorkManager manager = WorkManager.getInstance(context);
        manager.cancelUniqueWork(WORK_NAME);
        manager.cancelAllWorkByTag(WORK_TAG);
        cancelAlarm(context);
        DiagnosticLog.add(context, "daily schedule cancelled");
    }

    private static long nextTrigger(SharedPreferences prefs) {
        String[] pieces = prefs.getString("checkin_time", "09:17").split(":");
        int hour = Integer.parseInt(pieces[0]), minute = Integer.parseInt(pieces[1]);
        Calendar target = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"));
        target.set(Calendar.HOUR_OF_DAY, hour);
        target.set(Calendar.MINUTE, minute);
        target.set(Calendar.SECOND, 0);
        target.set(Calendar.MILLISECOND, 0);
        if (target.getTimeInMillis() <= System.currentTimeMillis()) target.add(Calendar.DATE, 1);
        return target.getTimeInMillis();
    }

    private static String scheduleAlarm(Context context, long triggerAt) {
        AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarm == null) return "unavailable";
        PendingIntent pending = PendingIntent.getBroadcast(context, ALARM_REQUEST_CODE,
                alarmIntent(context), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        try {
            boolean exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S
                    || alarm.canScheduleExactAlarms();
            if (exactAllowed) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
                } else {
                    alarm.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending);
                }
                return "exact-wakeup";
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
            } else {
                alarm.set(AlarmManager.RTC_WAKEUP, triggerAt, pending);
            }
            return "inexact-wakeup(permission unavailable)";
        } catch (SecurityException error) {
            alarm.set(AlarmManager.RTC_WAKEUP, triggerAt, pending);
            return "inexact-wakeup(security fallback)";
        }
    }

    private static void cancelAlarm(Context context) {
        AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pending = PendingIntent.getBroadcast(context, ALARM_REQUEST_CODE,
                alarmIntent(context), PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
        if (alarm != null && pending != null) alarm.cancel(pending);
        if (pending != null) pending.cancel();
    }

    private static Intent alarmIntent(Context context) {
        return new Intent(context, DailyAlarmReceiver.class).setAction(DailyAlarmReceiver.ACTION);
    }

    private static String format(long millis) {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        return format.format(new Date(millis));
    }

    private DailyScheduler() {}
}
