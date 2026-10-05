package com.dounai.checkin;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class ScheduleRestoreReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? "unknown" : intent.getAction();
        DiagnosticLog.add(context, "schedule restore action=" + action);
        DailyScheduler.restore(context);
        BatteryMonitorScheduler.schedule(context);
    }
}
