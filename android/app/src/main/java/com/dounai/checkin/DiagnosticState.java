package com.dounai.checkin;

import android.app.AlarmManager;
import android.app.ActivityManager;
import android.app.job.JobScheduler;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;

import androidx.work.WorkInfo;
import androidx.work.WorkManager;

import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;

/** Only records explicitly selected diagnostic fields; never preferences or server messages. */
final class DiagnosticState {
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    static void capture(Context context, String reason) {
        Context app = context.getApplicationContext();
        try {
            SharedPreferences settings = app.getSharedPreferences("settings", Context.MODE_PRIVATE);
            SharedPreferences history = app.getSharedPreferences("diagnostics", Context.MODE_PRIVATE);
            int boot = Settings.Global.getInt(app.getContentResolver(), Settings.Global.BOOT_COUNT, -1);
            PowerManager power = (PowerManager) app.getSystemService(Context.POWER_SERVICE);
            AlarmManager alarm = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
            ActivityManager activity = (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE);
            JobScheduler jobs = (JobScheduler) app.getSystemService(Context.JOB_SCHEDULER_SERVICE);
            DiagnosticLog.add(app, "state reason=" + reason
                    + " version=" + app.getPackageManager().getPackageInfo(app.getPackageName(), 0).versionName
                    + " sdk=" + Build.VERSION.SDK_INT + " boot=" + boot
                    + " previousBoot=" + history.getInt("boot", -1)
                    + " previousObservation=" + history.getLong("observed_at", 0)
                    + " auto=" + settings.getBoolean("auto_enabled", false)
                    + " checkinTime=" + settings.getString("checkin_time", "09:17")
                    + " idle=" + (power != null && power.isDeviceIdleMode())
                    + " powerSave=" + (power != null && power.isPowerSaveMode())
                    + " batteryExempt=" + (power != null && power.isIgnoringBatteryOptimizations(app.getPackageName()))
                    + " backgroundRestricted=" + (Build.VERSION.SDK_INT >= 28 && activity != null && activity.isBackgroundRestricted())
                    + " exactAllowed=" + (alarm != null && (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()))
                    + " pendingJobs=" + (jobs == null ? -1 : jobs.getAllPendingJobs().size())
                    + " " + DiagnosticLog.screenState(app));
            history.edit().putInt("boot", boot).putLong("observed_at", System.currentTimeMillis()).apply();
            EXECUTOR.execute(() -> {
                try {
                    List<WorkInfo> work = WorkManager.getInstance(app)
                            .getWorkInfosByTag("dounai-checkin").get(5, TimeUnit.SECONDS);
                    int finished = 0;
                    for (WorkInfo info : work) {
                        if (info.getState().isFinished()) { finished++; continue; }
                        DiagnosticLog.add(app, "work snapshot reason=" + reason + " id=" + info.getId()
                                + " state=" + info.getState() + " attempts=" + info.getRunAttemptCount());
                    }
                    DiagnosticLog.add(app, "work snapshot reason=" + reason + " total=" + work.size()
                            + " finished=" + finished);
                } catch (Exception error) {
                    DiagnosticLog.add(app, "work snapshot unavailable type=" + error.getClass().getSimpleName());
                }
            });
        } catch (Exception error) {
            DiagnosticLog.add(app, "state unavailable reason=" + reason + " type=" + error.getClass().getSimpleName());
        }
    }

    private DiagnosticState() {}
}
