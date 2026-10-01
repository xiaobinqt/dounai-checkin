package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

final class SessionState {
    static void restored(Context context) {
        context.getSharedPreferences("site", Context.MODE_PRIVATE).edit()
                .putBoolean("login_expired", false)
                .putBoolean("login_expired_notified", false).apply();
    }

    static String expired(Context context) {
        SharedPreferences site = context.getSharedPreferences("site", Context.MODE_PRIVATE);
        if (site.getBoolean("login_expired_notified", false)) {
            site.edit().putBoolean("login_expired", true).apply();
            return "";
        }
        site.edit().putBoolean("login_expired", true).apply();
        if (context.getSharedPreferences("settings", Context.MODE_PRIVATE)
                .getString("bark_key", "").trim().isEmpty()) return "";
        String error = Notifications.sendSessionExpired(context);
        if (error.isEmpty()) site.edit().putBoolean("login_expired_notified", true).apply();
        return error;
    }

    private SessionState() {}
}
