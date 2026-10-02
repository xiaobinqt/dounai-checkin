package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.OutputStream;
import java.net.Socket;
import java.net.InetSocketAddress;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

final class Notifications {
    static String send(Context context, boolean success, String message) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        String title = success ? (message.contains("已签到") || message.contains("已续过命")
                ? "豆奶今日已签到" : "豆奶签到成功") : "豆奶签到失败";
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<String> bark = executor.submit(() -> channelError("Bark", () -> sendBark(prefs, title, message)));
            Future<String> email = executor.submit(() -> channelError("邮件", () -> sendEmail(prefs, title, message)));
            String barkError = awaitChannel(bark, "Bark");
            String emailError = awaitChannel(email, "邮件");
            if (barkError.isEmpty()) return emailError;
            if (emailError.isEmpty()) return barkError;
            return barkError + "；" + emailError;
        } finally {
            executor.shutdownNow();
        }
    }

    private static String channelError(String channel, NotificationAction action) {
        try {
            action.run();
            return "";
        } catch (Exception error) {
            String message = error.getMessage();
            return channel + "：" + (message == null || message.isEmpty()
                    ? error.getClass().getSimpleName() : message);
        }
    }

    private static String awaitChannel(Future<String> future, String channel) {
        try {
            return future.get();
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            return channel + "：通知任务被中断";
        } catch (ExecutionException error) {
            Throwable cause = error.getCause();
            String message = cause == null ? "未知错误" : cause.getMessage();
            return channel + "：" + (message == null || message.isEmpty() ? "未知错误" : message);
        }
    }

    private interface NotificationAction {
        void run() throws Exception;
    }

    static String test(Context context) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        if (prefs.getString("bark_key", "").trim().isEmpty()
                && prefs.getString("email", "").trim().isEmpty()) {
            return "请先配置 Bark 或邮件通知";
        }
        return send(context, true, "豆奶签到通知测试");
    }

    static String sendSessionExpired(Context context) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        try {
            sendBark(prefs, "豆奶登录已失效", "登录 Cookie 已失效，请在豆奶签到 APK 中重新登录。自动刷新无法恢复已经过期的会话。");
            return "";
        } catch (Exception error) {
            return "Bark：" + error.getMessage();
        }
    }

    static String sendLowBattery(Context context, int percent) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        try {
            sendBark(prefs, "手机电量低", "当前电量 " + percent + "% ，请及时充电。低电量提醒来自豆奶签到 APK。");
            return "";
        } catch (Exception error) {
            return error.getMessage();
        }
    }

    private static void sendBark(SharedPreferences prefs, String title, String body) throws Exception {
        String key = prefs.getString("bark_key", "").trim();
        if (key.isEmpty()) return;
        String server = prefs.getString("bark_server", "https://api.day.app").trim().replaceAll("/+$", "");
        URL url = new URL(server + "/" + java.net.URLEncoder.encode(key, "UTF-8"));
        if (!"https".equalsIgnoreCase(url.getProtocol())) throw new Exception("Bark 服务地址必须使用 HTTPS");
        JSONObject payload = new JSONObject().put("title", title).put("body", body).put("group", "豆奶签到");
        Exception lastError = null;
        long[] delays = {0L, 5000L, 15000L};
        for (long delay : delays) {
            if (delay > 0) {
                try {
                    Thread.sleep(delay);
                } catch (InterruptedException error) {
                    Thread.currentThread().interrupt();
                    throw new Exception("通知重试被中断", error);
                }
            }
            try {
                sendBarkOnce(url, payload);
                return;
            } catch (RetryableBarkException error) {
                lastError = error;
            }
        }
        throw lastError == null ? new Exception("Bark 请求失败") : lastError;
    }

    private static void sendBarkOnce(URL url, JSONObject payload) throws Exception {
        HttpsURLConnection connection = (HttpsURLConnection) url.openConnection();
        connection.setConnectTimeout(20000);
        connection.setReadTimeout(20000);
        connection.setRequestMethod("POST");
        connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
        connection.setDoOutput(true);
        try {
            try (OutputStream stream = connection.getOutputStream()) {
                stream.write(payload.toString().getBytes(StandardCharsets.UTF_8));
            }
            int status = connection.getResponseCode();
            if (status == 408 || status == 429 || status >= 500) {
                throw new RetryableBarkException("HTTP " + status);
            }
            if (status < 200 || status >= 300) throw new Exception("HTTP " + status);
            byte[] bytes;
            try (java.io.InputStream stream = connection.getInputStream()) {
                java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
                byte[] buffer = new byte[4096];
                int count;
                while ((count = stream.read(buffer)) != -1) {
                    if (output.size() + count > 1024 * 1024) throw new Exception("响应过大");
                    output.write(buffer, 0, count);
                }
                bytes = output.toByteArray();
            }
            JSONObject response = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
            if (response.optInt("code") != 200) throw new Exception(response.optString("message", "服务端拒绝通知"));
        } catch (IOException error) {
            String message = error.getMessage();
            throw new RetryableBarkException(message == null || message.isEmpty()
                    ? error.getClass().getSimpleName() : message, error);
        } finally {
            connection.disconnect();
        }
    }

    private static final class RetryableBarkException extends Exception {
        RetryableBarkException(String message) {
            super(message);
        }

        RetryableBarkException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    private static void sendEmail(SharedPreferences prefs, String title, String body) throws Exception {
        String address = prefs.getString("email", "").trim();
        String host = prefs.getString("email_host", "").trim();
        String password = prefs.getString("email_auth_code", "");
        int port = prefs.getInt("email_port", 0);
        if (address.isEmpty() && host.isEmpty() && password.isEmpty() && port == 0) return;
        if (address.isEmpty() || host.isEmpty() || password.isEmpty() || port < 1 || port > 65535) {
            throw new Exception("邮件地址、SMTP 主机、端口和授权码必须完整填写");
        }
        Exception lastError = null;
        long[] delays = {0L, 5000L, 15000L};
        for (long delay : delays) {
            if (delay > 0) {
                try {
                    Thread.sleep(delay);
                } catch (InterruptedException error) {
                    Thread.currentThread().interrupt();
                    throw new Exception("邮件重试被中断", error);
                }
            }
            try {
                sendEmailOnce(address, host, password, port, title, body);
                return;
            } catch (RetryableEmailException error) {
                lastError = error;
            }
        }
        throw lastError == null ? new Exception("邮件发送失败") : lastError;
    }

    private static void sendEmailOnce(String address, String host, String password, int port,
                                      String title, String body) throws Exception {
        boolean implicitTls = port == 465;
        Socket socket = new Socket();
        boolean messageBodyStarted = false;
        String stage = "连接服务器";
        try {
            socket.connect(new InetSocketAddress(host, port), 15000);
            if (implicitTls) {
                stage = "建立 TLS";
                socket = ((SSLSocketFactory) SSLSocketFactory.getDefault())
                        .createSocket(socket, host, port, true);
            }
            socket.setSoTimeout(15000);
            if (socket instanceof SSLSocket) {
                verifyHost((SSLSocket) socket);
                ((SSLSocket) socket).startHandshake();
            }
            stage = "读取服务器响应";
            SmtpSession smtp = new SmtpSession(socket);
            smtp.expect(220);
            smtp.command("EHLO dounai-checkin", 250);
            if (!implicitTls) {
                stage = "建立 STARTTLS";
                smtp.command("STARTTLS", 220);
                socket = ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(socket, host, port, true);
                socket.setSoTimeout(15000);
                verifyHost((SSLSocket) socket);
                ((SSLSocket) socket).startHandshake();
                smtp = new SmtpSession(socket);
                smtp.command("EHLO dounai-checkin", 250);
            }
            stage = "登录";
            smtp.command("AUTH LOGIN", 334);
            smtp.command(base64(address), 334);
            smtp.command(base64(password), 235);
            stage = "准备邮件";
            smtp.command("MAIL FROM:<" + address + ">", 250);
            smtp.command("RCPT TO:<" + address + ">", 250);
            smtp.command("DATA", 354);
            String mime = "From: <" + address + ">\r\nTo: <" + address + ">\r\n"
                    + "Subject: =?UTF-8?B?" + base64(title) + "?=\r\n"
                    + "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n"
                    + "Content-Transfer-Encoding: base64\r\n\r\n" + base64(body) + "\r\n.";
            stage = "提交邮件";
            messageBodyStarted = true;
            smtp.command(mime, 250);
            // Once the server returns 250 the message is accepted. Some mobile
            // networks or SMTP servers close the socket instead of replying to
            // QUIT; that must not turn an accepted message into a reported failure.
            try {
                smtp.command("QUIT", 221);
            } catch (Exception ignored) {
                // Delivery has already been confirmed.
            }
        } catch (IOException error) {
            String detail = error.getMessage();
            if (detail == null || detail.trim().isEmpty()) detail = error.getClass().getSimpleName();
            if (!messageBodyStarted) {
                throw new RetryableEmailException("SMTP " + stage + "失败：" + detail, error);
            }
            throw new Exception("SMTP 提交邮件时连接中断，发送状态未知，请检查收件箱", error);
        } finally {
            try {
                socket.close();
            } catch (IOException ignored) {
                // Closing a completed or already-aborted SMTP connection is harmless.
            }
        }
    }

    private static final class RetryableEmailException extends Exception {
        RetryableEmailException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    private static String base64(String text) {
        return android.util.Base64.encodeToString(text.getBytes(StandardCharsets.UTF_8), android.util.Base64.NO_WRAP);
    }

    private static void verifyHost(SSLSocket socket) {
        javax.net.ssl.SSLParameters parameters = socket.getSSLParameters();
        parameters.setEndpointIdentificationAlgorithm("HTTPS");
        socket.setSSLParameters(parameters);
    }

    private static final class SmtpSession {
        private final BufferedReader reader;
        private final BufferedWriter writer;

        SmtpSession(Socket socket) throws Exception {
            reader = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII));
            writer = new BufferedWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.US_ASCII));
        }

        void command(String command, int expected) throws Exception {
            writer.write(command);
            writer.write("\r\n");
            writer.flush();
            expect(expected);
        }

        void expect(int expected) throws Exception {
            String line;
            do {
                line = reader.readLine();
                if (line == null || line.length() < 4) throw new Exception("SMTP 连接被关闭");
            } while (line.charAt(3) == '-');
            int code = Integer.parseInt(line.substring(0, 3));
            if (code != expected) throw new Exception("SMTP 返回 " + code);
        }
    }

    private Notifications() {}
}
