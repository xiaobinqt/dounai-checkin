package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.OutputStream;
import java.net.Socket;
import java.net.InetSocketAddress;
import java.net.URL;
import java.nio.charset.StandardCharsets;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

final class Notifications {
    static String send(Context context, boolean success, String message) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        String title = success ? (message.contains("已签到") || message.contains("已续过命")
                ? "豆奶今日已签到" : "豆奶签到成功") : "豆奶签到失败";
        StringBuilder errors = new StringBuilder();
        try {
            sendBark(prefs, title, message);
        } catch (Exception error) {
            errors.append("Bark：").append(error.getMessage());
        }
        try {
            sendEmail(prefs, title, message);
        } catch (Exception error) {
            if (errors.length() > 0) errors.append("；");
            errors.append("邮件：").append(error.getMessage());
        }
        return errors.toString();
    }

    static String test(Context context) {
        SharedPreferences prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE);
        if (prefs.getString("bark_key", "").trim().isEmpty()
                && prefs.getString("email", "").trim().isEmpty()) {
            return "请先配置 Bark 或邮件通知";
        }
        return send(context, true, "豆奶签到通知测试");
    }

    private static void sendBark(SharedPreferences prefs, String title, String body) throws Exception {
        String key = prefs.getString("bark_key", "").trim();
        if (key.isEmpty()) return;
        String server = prefs.getString("bark_server", "https://api.day.app").trim().replaceAll("/+$", "");
        URL url = new URL(server + "/" + java.net.URLEncoder.encode(key, "UTF-8"));
        if (!"https".equalsIgnoreCase(url.getProtocol())) throw new Exception("Bark 服务地址必须使用 HTTPS");
        HttpsURLConnection connection = (HttpsURLConnection) url.openConnection();
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(10000);
        connection.setRequestMethod("POST");
        connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
        connection.setDoOutput(true);
        JSONObject payload = new JSONObject().put("title", title).put("body", body).put("group", "豆奶签到");
        try {
            try (OutputStream stream = connection.getOutputStream()) {
                stream.write(payload.toString().getBytes(StandardCharsets.UTF_8));
            }
            int status = connection.getResponseCode();
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
        } finally {
            connection.disconnect();
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
        boolean implicitTls = port == 465;
        Socket socket = new Socket();
        socket.connect(new InetSocketAddress(host, port), 15000);
        if (implicitTls) socket = ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(socket, host, port, true);
        socket.setSoTimeout(15000);
        try {
            if (socket instanceof SSLSocket) {
                verifyHost((SSLSocket) socket);
                ((SSLSocket) socket).startHandshake();
            }
            SmtpSession smtp = new SmtpSession(socket);
            smtp.expect(220);
            smtp.command("EHLO dounai-checkin", 250);
            if (!implicitTls) {
                smtp.command("STARTTLS", 220);
                socket = ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(socket, host, port, true);
                socket.setSoTimeout(15000);
                verifyHost((SSLSocket) socket);
                ((SSLSocket) socket).startHandshake();
                smtp = new SmtpSession(socket);
                smtp.command("EHLO dounai-checkin", 250);
            }
            smtp.command("AUTH LOGIN", 334);
            smtp.command(base64(address), 334);
            smtp.command(base64(password), 235);
            smtp.command("MAIL FROM:<" + address + ">", 250);
            smtp.command("RCPT TO:<" + address + ">", 250);
            smtp.command("DATA", 354);
            String mime = "From: <" + address + ">\r\nTo: <" + address + ">\r\n"
                    + "Subject: =?UTF-8?B?" + base64(title) + "?=\r\n"
                    + "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n"
                    + "Content-Transfer-Encoding: base64\r\n\r\n" + base64(body) + "\r\n.";
            smtp.command(mime, 250);
            smtp.command("QUIT", 221);
        } finally {
            socket.close();
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
