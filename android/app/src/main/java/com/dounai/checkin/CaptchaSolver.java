package com.dounai.checkin;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Base64;
import android.util.Xml;

import org.xmlpull.v1.XmlPullParser;

import java.io.File;
import java.io.FileOutputStream;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
            Map<String, Integer> variantVotes = new HashMap<>();
            Map<String, String> representativeCandidates = new HashMap<>();
            List<String> rawResults = new ArrayList<>();
            List<Bitmap> variants = imageVariants(bitmap);
            try {
                for (int variantIndex = 0; variantIndex < variants.size(); variantIndex++) {
                    Bitmap variant = variants.get(variantIndex);
                    String whole = recognizer.classify(variant, ALL);
                    String slots;
                    try {
                        slots = recognizeSlots(recognizer, variant);
                    } catch (Exception error) {
                        slots = "";
                    }
                    String[] candidates = {whole, slots};
                    Set<String> answersInVariant = new HashSet<>();
                    Map<String, String> candidatesInVariant = new HashMap<>();
                    for (String candidate : candidates) {
                        if (!candidate.isEmpty()) rawResults.add("v" + variantIndex + ":" + compact(candidate));
                        try {
                            String answer = solveExpression(candidate);
                            answersInVariant.add(answer);
                            candidatesInVariant.putIfAbsent(answer, candidate);
                        } catch (Exception ignored) {
                            // Only structurally valid candidates can vote.
                        }
                    }
                    // Whole-image and slot recognition from the same pixels are not
                    // independent votes. A preprocessing variant votes only when all
                    // of its valid candidates agree.
                    if (answersInVariant.size() == 1) {
                        String answer = answersInVariant.iterator().next();
                        representativeCandidates.putIfAbsent(answer, candidatesInVariant.get(answer));
                        variantVotes.put(answer, variantVotes.getOrDefault(answer, 0) + 1);
                    }
                }
            } finally {
                for (Bitmap variant : variants) {
                    if (variant != bitmap) variant.recycle();
                }
            }
            String accepted = uniqueBestAnswer(variantVotes);
            if (accepted != null && variantVotes.get(accepted) >= 2) {
                DiagnosticLog.add(context, "captcha recognition accepted votes="
                        + variantVotes.get(accepted) + "/" + variants.size());
                return representativeCandidates.get(accepted);
            }
            saveFailure(context, bitmap, rawResults);
            DiagnosticLog.add(context, "captcha recognition rejected variants=" + variants.size()
                    + " candidates=" + compact(rawResults.toString()));
            throw new Exception("PNG 验证码未得到跨图像版本的一致结果：" + rawResults);
        }
    }

    private static List<Bitmap> imageVariants(Bitmap original) {
        List<Bitmap> variants = new ArrayList<>();
        Set<Long> fingerprints = new LinkedHashSet<>();
        addVariant(variants, fingerprints, original);
        int threshold = otsuThreshold(original);
        for (int offset : new int[]{-28, 0, 28}) {
            Bitmap variant = highContrast(original, Math.max(24, Math.min(231, threshold + offset)));
            if (!addVariant(variants, fingerprints, variant)) variant.recycle();
        }
        return variants;
    }

    private static boolean addVariant(List<Bitmap> variants, Set<Long> fingerprints, Bitmap bitmap) {
        if (!fingerprints.add(fingerprint(bitmap))) return false;
        variants.add(bitmap);
        return true;
    }

    private static long fingerprint(Bitmap bitmap) {
        int width = bitmap.getWidth(), height = bitmap.getHeight();
        int[] pixels = new int[width * height];
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height);
        long hash = 0xcbf29ce484222325L;
        for (int pixel : pixels) {
            hash ^= pixel;
            hash *= 0x100000001b3L;
        }
        return hash ^ ((long) width << 32) ^ height;
    }

    static String uniqueBestAnswer(Map<String, Integer> votes) {
        if (votes.isEmpty()) return null;
        int bestVotes = Collections.max(votes.values());
        String best = null;
        for (Map.Entry<String, Integer> entry : votes.entrySet()) {
            if (entry.getValue() != bestVotes) continue;
            if (best != null) return null;
            best = entry.getKey();
        }
        return best;
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
            expression.append(i == 1
                    ? recognizer.classifySingle(crop, OPERATOR)
                    : recognizer.classify(crop, OPERAND));
            crop.recycle();
        }
        return expression.append('=').toString();
    }

    private static Bitmap highContrast(Bitmap original, int threshold) {
        int width = original.getWidth(), height = original.getHeight();
        int[] pixels = new int[width * height];
        original.getPixels(pixels, 0, width, 0, 0, width, height);
        for (int i = 0; i < pixels.length; i++) {
            pixels[i] = luminance(pixels[i]) >= threshold ? 0xffffffff : 0xff000000;
        }
        Bitmap result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        result.setPixels(pixels, 0, width, 0, 0, width, height);
        return result;
    }

    static int otsuThreshold(Bitmap bitmap) {
        int width = bitmap.getWidth(), height = bitmap.getHeight();
        int[] pixels = new int[width * height];
        int[] histogram = new int[256];
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height);
        for (int pixel : pixels) histogram[luminance(pixel)]++;
        long totalSum = 0;
        for (int i = 0; i < histogram.length; i++) totalSum += (long) i * histogram[i];
        long backgroundSum = 0;
        int backgroundWeight = 0;
        double bestVariance = -1;
        int bestThreshold = 127;
        for (int threshold = 0; threshold < 255; threshold++) {
            backgroundWeight += histogram[threshold];
            if (backgroundWeight == 0) continue;
            int foregroundWeight = pixels.length - backgroundWeight;
            if (foregroundWeight == 0) break;
            backgroundSum += (long) threshold * histogram[threshold];
            double backgroundMean = (double) backgroundSum / backgroundWeight;
            double foregroundMean = (double) (totalSum - backgroundSum) / foregroundWeight;
            double difference = backgroundMean - foregroundMean;
            double variance = (double) backgroundWeight * foregroundWeight * difference * difference;
            if (variance > bestVariance) {
                bestVariance = variance;
                bestThreshold = threshold;
            }
        }
        return bestThreshold;
    }

    private static int luminance(int pixel) {
        int alpha = (pixel >>> 24) & 255;
        int red = (pixel >>> 16) & 255;
        int green = (pixel >>> 8) & 255;
        int blue = pixel & 255;
        if (alpha < 255) {
            red = (red * alpha + 255 * (255 - alpha)) / 255;
            green = (green * alpha + 255 * (255 - alpha)) / 255;
            blue = (blue * alpha + 255 * (255 - alpha)) / 255;
        }
        return (77 * red + 150 * green + 29 * blue) >> 8;
    }

    private static void saveFailure(Context context, Bitmap bitmap, List<String> candidates) {
        File directory = new File(context.getFilesDir(), "captcha-diagnostics");
        try {
            if (!directory.exists() && !directory.mkdirs()) return;
            try (FileOutputStream image = new FileOutputStream(new File(directory, "last-failure.png"))) {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, image);
            }
            try (FileOutputStream metadata = new FileOutputStream(new File(directory, "last-failure.txt"))) {
                metadata.write(compact(candidates.toString()).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            }
        } catch (Exception ignored) {
            // Captcha diagnostics must never interrupt a check-in task.
        }
    }

    private static String compact(String value) {
        String clean = value == null ? "" : value.replace('\n', ' ').replace('\r', ' ');
        return clean.length() <= 240 ? clean : clean.substring(0, 240);
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
