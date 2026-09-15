package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class CheckInWorker extends Worker {
    private static final Object RUN_LOCK = new Object();

    public CheckInWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        synchronized (RUN_LOCK) {
            Context context = getApplicationContext();
            boolean automatic = getInputData().getBoolean("automatic", false);
            SharedPreferences site = context.getSharedPreferences("site", Context.MODE_PRIVATE);
            SharedPreferences settings = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
            String day = shanghaiDay();
            if (automatic && day.equals(site.getString("last_auto_date", ""))) return Result.success();
            if (automatic) site.edit().putString("last_auto_date", day).commit();
            boolean success = false;
            String message;
            try {
                String url = site.getString("url", "");
                String cookie = site.getString("cookie", "");
                if (url.isEmpty()) throw new Exception("请先设置站点地址并登录");
                message = new CheckInClient(context, url, cookie).checkIn();
                success = true;
            } catch (Exception error) {
                message = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
            }
            String notificationError = Notifications.send(context, success, message);
            String result = (success ? "成功：" : "失败：") + message;
            if (!notificationError.isEmpty()) result += "；通知失败：" + notificationError;
            site.edit().putString("last_result", result)
                    .putLong("last_run_at", System.currentTimeMillis()).apply();
            if (automatic && settings.getBoolean("auto_enabled", false)) DailyScheduler.scheduleNext(context);
            return Result.success();
        }
    }

    private static String shanghaiDay() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        return format.format(new Date());
    }
}
