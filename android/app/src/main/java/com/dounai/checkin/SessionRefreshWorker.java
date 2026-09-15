package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

public class SessionRefreshWorker extends Worker {
    public SessionRefreshWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        synchronized (CheckInWorker.RUN_LOCK) {
            Context context = getApplicationContext();
            SharedPreferences settings = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
            SharedPreferences site = context.getSharedPreferences("site", Context.MODE_PRIVATE);
            if (!settings.getBoolean("auto_enabled", false)
                    && !site.getBoolean("login_expired", false)) return Result.success();
            String url = site.getString("url", "");
            String cookie = site.getString("cookie", "");
            if (url.isEmpty()) return Result.success();

            String message;
            if (site.getBoolean("login_expired", false) || cookie.isEmpty()) {
                String notifyError = SessionState.expired(context);
                message = "登录态已失效，请重新登录";
                if (!notifyError.isEmpty()) message += "；通知失败：" + notifyError;
            } else {
                try {
                    new CheckInClient(context, url, cookie).refreshSession();
                    SessionState.restored(context);
                    message = "登录态已刷新";
                } catch (CheckInClient.SessionExpiredException error) {
                    String notifyError = SessionState.expired(context);
                    message = error.getMessage();
                    if (!notifyError.isEmpty()) message += "；通知失败：" + notifyError;
                } catch (Exception error) {
                    message = "暂时无法刷新登录态：" + error.getMessage();
                }
            }
            site.edit().putString("last_refresh_result", message)
                    .putLong("last_refresh_at", System.currentTimeMillis()).apply();
            return Result.success();
        }
    }
}
