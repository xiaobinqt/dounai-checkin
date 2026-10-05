package com.dounai.checkin;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class DailyAlarmReceiver extends BroadcastReceiver {
    static final String ACTION = "com.dounai.checkin.DAILY_ALARM";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null && ACTION.equals(intent.getAction())) DailyScheduler.onAlarm(context);
    }
}
