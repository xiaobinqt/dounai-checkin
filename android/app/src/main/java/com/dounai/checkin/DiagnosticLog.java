package com.dounai.checkin;

import android.content.Context;
import android.os.PowerManager;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

final class DiagnosticLog {
    private static final String FILE_NAME = "runtime.log";
    private static final int MAX_BYTES = 96 * 1024;
    private static final int KEEP_BYTES = 64 * 1024;

    static synchronized void add(Context context, String event) {
        String clean = event == null ? "unknown" : event.replace('\n', ' ').replace('\r', ' ');
        String line = timestamp() + " " + clean + "\n";
        File file = new File(context.getFilesDir(), FILE_NAME);
        try {
            if (file.length() > MAX_BYTES) trim(file);
            try (FileOutputStream output = new FileOutputStream(file, true)) {
                output.write(line.getBytes(StandardCharsets.UTF_8));
            }
        } catch (Exception ignored) {
            // Diagnostics must never interrupt a check-in task.
        }
    }

    static synchronized String read(Context context) {
        File file = new File(context.getFilesDir(), FILE_NAME);
        if (!file.exists()) return "尚无运行日志";
        try (FileInputStream input = new FileInputStream(file)) {
            long skipped = Math.max(0, file.length() - MAX_BYTES);
            while (skipped > 0) {
                long count = input.skip(skipped);
                if (count <= 0) break;
                skipped -= count;
            }
            byte[] bytes = new byte[(int) Math.min(file.length(), MAX_BYTES)];
            int count = input.read(bytes);
            return count <= 0 ? "尚无运行日志" : new String(bytes, 0, count, StandardCharsets.UTF_8);
        } catch (Exception error) {
            return "日志读取失败：" + error.getClass().getSimpleName();
        }
    }

    static synchronized void clear(Context context) {
        File file = new File(context.getFilesDir(), FILE_NAME);
        try (FileOutputStream ignored = new FileOutputStream(file, false)) {
            // Truncate the file without affecting the app when it fails.
        } catch (Exception ignored) {
        }
        add(context, "log cleared");
    }

    static String screenState(Context context) {
        PowerManager power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        return power != null && power.isInteractive() ? "screen=on" : "screen=off";
    }

    private static void trim(File file) throws Exception {
        byte[] all;
        try (FileInputStream input = new FileInputStream(file)) {
            all = new byte[(int) file.length()];
            int offset = 0;
            while (offset < all.length) {
                int count = input.read(all, offset, all.length - offset);
                if (count < 0) break;
                offset += count;
            }
        }
        int start = Math.max(0, all.length - KEEP_BYTES);
        while (start < all.length && all[start] != '\n') start++;
        if (start < all.length) start++;
        try (FileOutputStream output = new FileOutputStream(file, false)) {
            output.write(all, start, all.length - start);
        }
    }

    private static String timestamp() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));
        return format.format(new Date());
    }

    private DiagnosticLog() {}
}
