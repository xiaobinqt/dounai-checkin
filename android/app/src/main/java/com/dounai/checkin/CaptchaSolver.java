package com.dounai.checkin;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Base64;
import android.util.Xml;

import org.xmlpull.v1.XmlPullParser;

import java.io.StringReader;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class CaptchaSolver {
    private static final Pattern IMAGE_DATA = Pattern.compile("data:image/[^;]+;base64,([A-Za-z0-9+/=]+)", Pattern.CASE_INSENSITIVE);
    private static final Pattern EXPRESSION = Pattern.compile("^([0-9]{1,2})([+\\-*/])([0-9]{1,2})$");
    private static final Pattern ANSWER = Pattern.compile("^(?:[0-9]{4}|-?[0-9]{1,3})$");
    private static final String ALL = "0123456789+-xX*/=×÷加减乘除零〇一二两三四五六七八九壹贰貳叁參肆伍陆柒捌玖";
    private static final String OPERAND = "0123456789零〇一二两三四五六七八九壹贰貳叁參肆伍陆柒捌玖";
    private static final String OPERATOR = "+-xX*/×÷加减乘除";
    private static final String[] REPLACEMENTS = {
            " ", "", "　", "", "×", "*", "✕", "*", "✖", "*", "＊", "*", "x", "*", "X", "*", "乘", "*",
            "÷", "/", "／", "/", "除", "/", "＋", "+", "加", "+", "−", "-", "－", "-", "减", "-", "＝", "=", "?", "", "？", "",
            "零", "0", "〇", "0", "一", "1", "壹", "1", "二", "2", "两", "2", "贰", "2", "貳", "2",
            "三", "3", "叁", "3", "參", "3", "四", "4", "肆", "4", "五", "5", "伍", "5",
            "六", "6", "陆", "6", "七", "7", "柒", "7", "八", "8", "捌", "8",
            "九", "9", "玖", "9", "０", "0", "１", "1", "２", "2", "３", "3", "４", "4",
            "５", "5", "６", "6", "７", "7", "８", "8", "９", "9"
    };

    static String solve(Context context, String captchaMarkup) throws Exception {
        String raw;
        if (captchaMarkup.toLowerCase().contains("<svg")) {
            raw = extractSvgText(captchaMarkup);
        } else {
            Matcher matcher = IMAGE_DATA.matcher(captchaMarkup);
            if (!matcher.find()) throw new Exception("验证码不包含 SVG 文本或 PNG 图片");
            byte[] image = Base64.decode(matcher.group(1), Base64.DEFAULT);
            Bitmap bitmap = BitmapFactory.decodeByteArray(image, 0, image.length);
            if (bitmap == null) throw new Exception("验证码图片无法解码");
            raw = recognizeImage(context, bitmap);
        }
        String answer = solveExpression(raw);
        if (!ANSWER.matcher(answer).matches()) throw new Exception("验证码答案格式不正确");
        return answer;
    }

    private static String extractSvgText(String markup) throws Exception {
        XmlPullParser parser = Xml.newPullParser();
        parser.setInput(new StringReader(markup));
        StringBuilder text = new StringBuilder();
        boolean inText = false;
        int event;
        while ((event = parser.next()) != XmlPullParser.END_DOCUMENT) {
            if (event == XmlPullParser.START_TAG && "text".equals(parser.getName())) inText = true;
            else if (event == XmlPullParser.END_TAG && "text".equals(parser.getName())) inText = false;
            else if (event == XmlPullParser.TEXT && inText) text.append(parser.getText());
        }
        if (text.length() == 0) throw new Exception("SVG 验证码没有文本");
        return text.toString();
    }

    private static String recognizeImage(Context context, Bitmap bitmap) throws Exception {
        try (OnnxCaptchaRecognizer recognizer = new OnnxCaptchaRecognizer(context)) {
            Map<String, Integer> counts = new HashMap<>();
            String first = "";
            Bitmap[] variants = {bitmap, highContrast(bitmap, 90), highContrast(bitmap, 120)};
            for (Bitmap variant : variants) {
                String whole = recognizer.classify(variant, ALL);
                String slots;
                try {
                    slots = recognizeSlots(recognizer, variant);
                } catch (Exception error) {
                    slots = "";
                }
                String[] candidates = {whole, slots};
                for (String candidate : candidates) {
                    try {
                        String answer = solveExpression(candidate);
                        if (first.isEmpty()) first = candidate;
                        int count = counts.getOrDefault(answer, 0) + 1;
                        counts.put(answer, count);
                        if (count >= 2) return candidate;
                    } catch (Exception ignored) {
                        // Only structurally valid answers vote in the consensus.
                    }
                }
            }
            if (!first.isEmpty() && Pattern.matches("[0-9]{4}", solveExpression(first))) return first;
            throw new Exception("PNG 验证码识别结果不一致");
        }
    }

    private static String recognizeSlots(OnnxCaptchaRecognizer recognizer, Bitmap bitmap) throws Exception {
        int width = bitmap.getWidth();
        if (width < 4) throw new Exception("验证码图片太小");
        int[][] slots = {{4, 33}, {36, 66}, {69, 103}};
        StringBuilder expression = new StringBuilder();
        for (int i = 0; i < slots.length; i++) {
            int start = width * slots[i][0] / 140;
            int end = width * slots[i][1] / 140;
            if (end <= start) throw new Exception("验证码裁剪范围无效");
            Bitmap crop = Bitmap.createBitmap(bitmap, start, 0, end - start, bitmap.getHeight());
            expression.append(recognizer.classify(crop, i == 1 ? OPERATOR : OPERAND));
            crop.recycle();
        }
        return expression.append('=').toString();
    }

    private static Bitmap highContrast(Bitmap original, int threshold) {
        int width = original.getWidth(), height = original.getHeight();
        int[] pixels = new int[width * height];
        original.getPixels(pixels, 0, width, 0, 0, width, height);
        for (int i = 0; i < pixels.length; i++) {
            int pixel = pixels[i];
            int brightest = Math.max((pixel >> 16) & 255, Math.max((pixel >> 8) & 255, pixel & 255));
            pixels[i] = brightest >= threshold ? 0xffffffff : 0xff000000;
        }
        Bitmap result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        result.setPixels(pixels, 0, width, 0, 0, width, height);
        return result;
    }

    static String solveExpression(String raw) throws Exception {
        String normalized = raw.trim();
        for (int i = 0; i < REPLACEMENTS.length; i += 2) {
            normalized = normalized.replace(REPLACEMENTS[i], REPLACEMENTS[i + 1]);
        }
        if (normalized.endsWith("=")) normalized = normalized.substring(0, normalized.length() - 1);
        if (Pattern.matches("[0-9]{4}", normalized)) return normalized;
        Matcher match = EXPRESSION.matcher(normalized);
        if (!match.matches()) throw new Exception("验证码不是四位数字或简单算式");
        int left = Integer.parseInt(match.group(1)), right = Integer.parseInt(match.group(3));
        int value;
        switch (match.group(2)) {
            case "+": value = left + right; break;
            case "-": value = left - right; break;
            case "*": value = left * right; break;
            case "/":
                if (right == 0 || left % right != 0) throw new Exception("验证码除法结果不是整数");
                value = left / right;
                break;
            default: throw new Exception("未知验证码运算符");
        }
        return Integer.toString(value);
    }

    private CaptchaSolver() {}
}
