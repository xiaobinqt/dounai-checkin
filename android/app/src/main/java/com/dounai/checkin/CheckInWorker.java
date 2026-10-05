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
    static final Object RUN_LOCK = new Object();

    public CheckInWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        synchronized (RUN_LOCK) {
            Context context = getApplicationContext();
            boolean automatic = getInputData().getBoolean("automatic", false);
            String source = getInputData().getString("source");
            if (source == null || source.isEmpty()) source = automatic ? "work" : "manual";
            SharedPreferences site = context.getSharedPreferences("site", Context.MODE_PRIVATE);
            SharedPreferences settings = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
            String day = shanghaiDay();
            DiagnosticLog.add(context, "check-in started source=" + source
                    + " attempt=" + getRunAttemptCount() + " " + DiagnosticLog.screenState(context));
            if (automatic && !settings.getBoolean("auto_enabled", false)) {
                DiagnosticLog.add(context, "check-in skipped; automatic check-in disabled");
                return Result.success();
            }
            if (automatic && day.equals(site.getString("last_auto_date", ""))) {
                DiagnosticLog.add(context, "check-in skipped; automatic task already ran today");
                if (settings.getBoolean("auto_enabled", false)) DailyScheduler.scheduleNext(context);
                return Result.success();
            }
            boolean success = false;
            boolean expired = false;
            String message;
            try {
                String url = site.getString("url", "");
                String cookie = site.getString("cookie", "");
                if (url.isEmpty()) throw new Exception("请先设置站点地址并登录");
                if (cookie.isEmpty() && site.getBoolean("has_logged_in", false))
                    throw new CheckInClient.SessionExpiredException("登录态已失效，请在应用中重新登录");
                message = new CheckInClient(context, url, cookie).checkIn();
                success = true;
            } catch (CheckInClient.SessionExpiredException error) {
                expired = true;
                message = error.getMessage();
            } catch (CheckInClient.NetworkException error) {
                message = error.getMessage();
                if (automatic && error.isSafeToRetry() && getRunAttemptCount() < 3) {
                    site.edit().putString("last_result", "网络暂时不可用，后台签到将在稍后重试")
                            .putLong("last_run_at", System.currentTimeMillis()).apply();
                    DiagnosticLog.add(context, "check-in network retry queued nextAttempt="
                            + (getRunAttemptCount() + 1));
                    return Result.retry();
                }
            } catch (Exception error) {
                message = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
            }
            if (success) SessionState.restored(context);
            String notificationError = expired ? SessionState.expired(context)
                    : Notifications.send(context, success, message);
            String result = (success ? "成功：" : "失败：") + message;
            if (!notificationError.isEmpty()) result += "；通知失败：" + notificationError;
            site.edit().putString("last_result", result)
                    .putLong("last_run_at", System.currentTimeMillis()).apply();
            if (automatic) site.edit().putString("last_auto_date", day).apply();
            if (automatic && settings.getBoolean("auto_enabled", false)) DailyScheduler.scheduleNext(context);
            DiagnosticLog.add(context, "check-in finished success=" + success
                    + " sessionExpired=" + expired + " notificationError=" + !notificationError.isEmpty());
            return Result.success();
        }
    }

    private static String shanghaiDay() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        return format.format(new Date());
    }
}
