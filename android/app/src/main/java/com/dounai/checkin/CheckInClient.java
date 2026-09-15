package com.dounai.checkin;

import android.content.Context;
import android.content.SharedPreferences;
import android.webkit.CookieManager;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpCookie;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;

import javax.net.ssl.HttpsURLConnection;

final class CheckInClient {
    private static final String USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36";
    private final Context context;
    private final String baseUrl;
    private final Map<String, String> cookies = new TreeMap<>();
    private final TreeSet<String> initialCookieNames = new TreeSet<>();
    private String tokenSeed = "";

    CheckInClient(Context context, String baseUrl, String cookieHeader) {
        this.context = context;
        this.baseUrl = baseUrl;
        for (String part : cookieHeader.split(";")) {
            int separator = part.indexOf('=');
            if (separator > 0) {
                cookies.put(part.substring(0, separator).trim(), part.substring(separator + 1).trim());
            }
        }
        initialCookieNames.addAll(cookies.keySet());
    }

    String checkIn() throws Exception {
        if (cookies.isEmpty()) {
            throw new Exception("没有登录 Cookie，请先在应用中打开签到页并登录");
        }
        try {
            Response panel = request("GET", "/user/panel", null);
            requireAuthenticated(panel);

            Response captchaResponse = request("GET", "/auth/captcha?type=checkin&_=" + System.currentTimeMillis(), null);
            if (captchaResponse.status < 200 || captchaResponse.status >= 300) {
                throw new Exception("验证码接口返回 HTTP " + captchaResponse.status);
            }
            JSONObject captcha = new JSONObject(captchaResponse.body);
            if (captcha.optInt("ret") != 1 || captcha.optString("svg").trim().isEmpty()) {
                throw new Exception("验证码获取失败：" + captcha.optString("msg", "服务端未返回验证码"));
            }
            String seed = captcha.optString("seed").trim();
            if (!seed.isEmpty()) tokenSeed = seed;
            String code = CaptchaSolver.solve(context, captcha.getString("svg"));
            String token = checkInToken(captcha.optString("challenge").trim(), code,
                    tokenSeed, captcha.optString("salt_mask").trim());
            String body = "captcha_code=" + encode(code) + "&checkin_secret=&checkin_token=" + encode(token);
            Response resultResponse = request("POST", "/user/checkin", body);
            requireAuthenticated(resultResponse);
            JSONObject result = new JSONObject(resultResponse.body);
            String message = result.optString("msg").trim();
            if (result.optInt("ret") != 1 || !isConfirmedSuccess(message)) {
                throw new Exception(message.isEmpty() ? "签到未被服务端确认" : message);
            }
            return message;
        } finally {
            saveCookies();
        }
    }

    private Response request(String method, String path, String formBody) throws Exception {
        HttpsURLConnection connection = (HttpsURLConnection) new URL(baseUrl + path).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(15000);
        connection.setRequestMethod(method);
        connection.setRequestProperty("Cookie", cookieHeader());
        connection.setRequestProperty("User-Agent", USER_AGENT);
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8,en-US;q=0.7");
        boolean ajax = path.startsWith("/auth/captcha") || path.equals("/user/checkin");
        if (ajax) {
            connection.setRequestProperty("Accept", "application/json, text/javascript, */*; q=0.01");
            connection.setRequestProperty("Referer", baseUrl + "/user/panel");
            connection.setRequestProperty("X-Requested-With", "XMLHttpRequest");
            connection.setRequestProperty("Priority", "u=1, i");
            connection.setRequestProperty("Sec-CH-UA", "\"Chromium\";v=\"152\", \"Not?A_Brand\";v=\"24\", \"Google Chrome\";v=\"152\"");
            connection.setRequestProperty("Sec-CH-UA-Mobile", "?0");
            connection.setRequestProperty("Sec-CH-UA-Platform", "\"macOS\"");
            connection.setRequestProperty("Sec-Fetch-Dest", "empty");
            connection.setRequestProperty("Sec-Fetch-Mode", "cors");
            connection.setRequestProperty("Sec-Fetch-Site", "same-origin");
        } else {
            connection.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
        }
        if (formBody != null) {
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
            connection.setRequestProperty("Origin", baseUrl);
            try (OutputStream stream = connection.getOutputStream()) {
                stream.write(formBody.getBytes(StandardCharsets.UTF_8));
            }
        }
        try {
            int status = connection.getResponseCode();
            for (Map.Entry<String, java.util.List<String>> header : connection.getHeaderFields().entrySet()) {
                if (header.getKey() != null && header.getKey().equalsIgnoreCase("Set-Cookie")) {
                    for (String value : header.getValue()) {
                        try {
                            for (HttpCookie cookie : HttpCookie.parse(value)) {
                                if (cookie.hasExpired() || cookie.getMaxAge() == 0) cookies.remove(cookie.getName());
                                else cookies.put(cookie.getName(), cookie.getValue());
                            }
                        } catch (IllegalArgumentException ignored) {
                            // A malformed Set-Cookie must not discard the existing session.
                        }
                    }
                }
            }
            InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            if (stream != null) {
                try (InputStream input = stream) {
                    byte[] buffer = new byte[4096];
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        if (output.size() + count > 2 * 1024 * 1024) throw new Exception("服务端响应过大");
                        output.write(buffer, 0, count);
                    }
                }
            }
            return new Response(status, connection.getHeaderField("Location"), output.toString("UTF-8"));
        } finally {
            connection.disconnect();
        }
    }

    private void requireAuthenticated(Response response) throws Exception {
        if (response.status == 401 || response.status == 403 || response.status >= 300 && response.status < 400
                && response.location != null && response.location.toLowerCase().contains("login")
                || response.body.toLowerCase().contains("/auth/login") && response.body.contains("captcha_code")) {
            throw new Exception("登录态已失效，请在应用中重新登录");
        }
        if (response.status < 200 || response.status >= 300) {
            throw new Exception("服务端返回 HTTP " + response.status);
        }
    }

    private String cookieHeader() {
        StringBuilder header = new StringBuilder();
        for (Map.Entry<String, String> cookie : cookies.entrySet()) {
            if (header.length() > 0) header.append("; ");
            header.append(cookie.getKey()).append('=').append(cookie.getValue());
        }
        return header.toString();
    }

    private void saveCookies() {
        String header = cookieHeader();
        SharedPreferences prefs = context.getSharedPreferences("site", Context.MODE_PRIVATE);
        prefs.edit().putString("cookie", header).apply();
        CookieManager manager = CookieManager.getInstance();
        for (String oldName : initialCookieNames) {
            if (!cookies.containsKey(oldName)) manager.setCookie(baseUrl, oldName + "=; Max-Age=0");
        }
        for (Map.Entry<String, String> cookie : cookies.entrySet()) {
            manager.setCookie(baseUrl, cookie.getKey() + "=" + cookie.getValue());
        }
        manager.flush();
    }

    private static String encode(String value) throws Exception {
        return URLEncoder.encode(value, "UTF-8");
    }

    private static String checkInToken(String challenge, String code, String seed, String saltMask) throws Exception {
        if (challenge.isEmpty() || code.isEmpty()) return "";
        String salt = "dou_2026";
        if (!seed.isEmpty() || !saltMask.isEmpty()) {
            String[] pieces = challenge.split("\\.");
            String nonce = pieces.length >= 2 ? pieces[1] : "";
            salt = sha256(seed + "_" + nonce + "_" + saltMask);
        }
        return sha256(challenge + "_" + code + "_" + salt);
    }

    private static String sha256(String text) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
        StringBuilder hex = new StringBuilder(digest.length * 2);
        for (byte value : digest) hex.append(String.format("%02x", value & 0xff));
        return hex.toString();
    }

    private static boolean isConfirmedSuccess(String message) {
        if (message.isEmpty()) return false;
        if (message.contains("已经续过命") || message.contains("已续过命")
                || message.contains("已经签到") || message.contains("已签到")
                || message.contains("签到成功") || message.contains("续命成功")) return true;
        return java.util.regex.Pattern.compile("(?:^|[^未])获得了?\\s*[0-9]").matcher(message).find();
    }

    private static final class Response {
        final int status;
        final String location;
        final String body;

        Response(int status, String location, String body) {
            this.status = status;
            this.location = location;
            this.body = body;
        }
    }
}
