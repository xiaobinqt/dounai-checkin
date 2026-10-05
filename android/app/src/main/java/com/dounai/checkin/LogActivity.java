package com.dounai.checkin;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Bundle;
import android.text.method.ScrollingMovementMethod;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public class LogActivity extends Activity {
    private TextView logView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        int padding = (int) (12 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(padding, padding, padding, padding);

        TextView title = new TextView(this);
        title.setText("运行日志");
        title.setTextSize(22);
        root.addView(title);

        TextView note = new TextView(this);
        note.setText("记录任务计划、实际唤醒、屏幕状态、重试和通知结果，不包含 Cookie、密码或通知密钥。");
        root.addView(note);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        String[] labels = {"刷新", "复制", "清空", "返回"};
        for (String label : labels) {
            Button button = new Button(this);
            button.setText(label);
            actions.addView(button, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
            if ("刷新".equals(label)) button.setOnClickListener(v -> refresh());
            if ("复制".equals(label)) button.setOnClickListener(v -> copy());
            if ("清空".equals(label)) button.setOnClickListener(v -> confirmClear());
            if ("返回".equals(label)) button.setOnClickListener(v -> finish());
        }
        root.addView(actions);

        logView = new TextView(this);
        logView.setTextSize(12);
        logView.setTextIsSelectable(true);
        logView.setGravity(Gravity.START);
        logView.setMovementMethod(new ScrollingMovementMethod());
        ScrollView scroll = new ScrollView(this);
        scroll.addView(logView);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));
        setContentView(root);
        refresh();
    }

    private void refresh() {
        logView.setText(DiagnosticLog.read(this));
    }

    private void copy() {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("豆奶签到运行日志", logView.getText()));
        Toast.makeText(this, "日志已复制", Toast.LENGTH_SHORT).show();
    }

    private void confirmClear() {
        new AlertDialog.Builder(this).setMessage("清空运行日志？")
                .setNegativeButton("取消", null)
                .setPositiveButton("清空", (dialog, which) -> {
                    DiagnosticLog.clear(this);
                    refresh();
                }).show();
    }
}
