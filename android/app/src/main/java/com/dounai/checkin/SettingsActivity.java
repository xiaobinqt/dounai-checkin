package com.dounai.checkin;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.text.InputType;
import android.view.WindowManager;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

public class SettingsActivity extends Activity {
    private EditText time, barkKey, barkServer, email, emailHost, emailPort, emailPassword;
    private CheckBox autoEnabled;
    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        SharedPreferences prefs = getSharedPreferences("settings", Context.MODE_PRIVATE);
        ScrollView scroll = new ScrollView(this);
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(24, 24, 24, 24);
        scroll.addView(form);
        setContentView(scroll);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);

        TextView title = new TextView(this);
        title.setText("自动签到与通知");
        title.setTextSize(22);
        form.addView(title);

        autoEnabled = new CheckBox(this);
        autoEnabled.setText("每天自动签到（北京时间；实际执行可能延迟）");
        autoEnabled.setChecked(prefs.getBoolean("auto_enabled", false));
        form.addView(autoEnabled);
        time = field(form, "签到时间 HH:MM", prefs.getString("checkin_time", "09:17"), InputType.TYPE_CLASS_DATETIME);
        barkKey = field(form, "Bark 设备 Key（可选）", prefs.getString("bark_key", ""), InputType.TYPE_CLASS_TEXT);
        barkServer = field(form, "Bark 服务地址", prefs.getString("bark_server", "https://api.day.app"), InputType.TYPE_TEXT_VARIATION_URI);
        email = field(form, "邮件地址（发件人及收件人，可选）", prefs.getString("email", ""), InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        emailHost = field(form, "SMTP 主机", prefs.getString("email_host", ""), InputType.TYPE_CLASS_TEXT);
        int savedPort = prefs.getInt("email_port", 0);
        emailPort = field(form, "SMTP 端口（465 或 587）", savedPort == 0 ? "" : Integer.toString(savedPort), InputType.TYPE_CLASS_NUMBER);
        emailPassword = field(form, "SMTP 授权码", prefs.getString("email_auth_code", ""), InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);

        TextView tlsHint = new TextView(this);
        tlsHint.setText("SMTP 465 使用直接 TLS；587 使用 STARTTLS。两种方式都会验证服务器证书。");
        form.addView(tlsHint);
        Button save = new Button(this);
        save.setText("保存并安排每日任务");
        form.addView(save);
        save.setOnClickListener(v -> save());
        Button test = new Button(this);
        test.setText("发送测试通知");
        form.addView(test);
        test.setOnClickListener(v -> {
            if (!save()) return;
            status.setText("正在发送测试通知…");
            new Thread(() -> {
                String error = Notifications.test(getApplicationContext());
                runOnUiThread(() -> status.setText(error.isEmpty() ? "测试通知已发送" : "测试通知失败：" + error));
            }).start();
        });
        status = new TextView(this);
        status.setText("请先在首页登录站点，再开启自动签到。");
        form.addView(status);
    }

    private EditText field(LinearLayout form, String hint, String value, int inputType) {
        EditText field = new EditText(this);
        field.setHint(hint);
        field.setSingleLine(true);
        field.setInputType(inputType);
        field.setText(value);
        form.addView(field);
        return field;
    }

    private boolean save() {
        SharedPreferences site = getSharedPreferences("site", Context.MODE_PRIVATE);
        if (autoEnabled.isChecked() && (!site.getBoolean("has_logged_in", false)
                || site.getBoolean("login_expired", false)
                || site.getString("cookie", "").trim().isEmpty())) {
            status.setText("请先在首页打开站点并完成网页登录");
            return false;
        }
        String checkInTime = time.getText().toString().trim();
        if (!checkInTime.matches("(?:[01][0-9]|2[0-3]):[0-5][0-9]")) {
            time.setError("请输入 24 小时制时间，例如 09:17");
            return false;
        }
        String server = barkServer.getText().toString().trim();
        if (!server.startsWith("https://")) {
            barkServer.setError("Bark 服务地址必须使用 HTTPS");
            return false;
        }
        String portText = emailPort.getText().toString().trim();
        int port;
        try {
            port = portText.isEmpty() ? 0 : Integer.parseInt(portText);
        } catch (NumberFormatException error) {
            emailPort.setError("端口必须是数字");
            return false;
        }
        String address = email.getText().toString().trim();
        String host = emailHost.getText().toString().trim();
        String password = emailPassword.getText().toString();
        if (!address.isEmpty() || !host.isEmpty() || !password.isEmpty() || port != 0) {
            if (address.isEmpty() || host.isEmpty() || password.isEmpty() || port < 1 || port > 65535) {
                status.setText("邮件通知需要完整填写地址、SMTP 主机、端口和授权码");
                return false;
            }
            if (port != 465 && port != 587) {
                emailPort.setError("当前版本支持 TLS 465 或 STARTTLS 587");
                return false;
            }
        }
        getSharedPreferences("settings", Context.MODE_PRIVATE).edit()
                .putBoolean("auto_enabled", autoEnabled.isChecked())
                .putString("checkin_time", checkInTime)
                .putString("bark_key", barkKey.getText().toString().trim())
                .putString("bark_server", server)
                .putString("email", address)
                .putString("email_host", host)
                .putInt("email_port", port)
                .putString("email_auth_code", password).apply();
        DailyScheduler.schedule(this);
        status.setText(autoEnabled.isChecked() ? "已安排下一次每日签到" : "自动签到已关闭；通知设置已保存");
        return true;
    }
}
