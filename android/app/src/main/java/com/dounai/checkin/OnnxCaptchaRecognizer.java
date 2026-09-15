package com.dounai.checkin;

import android.content.Context;
import android.graphics.Bitmap;

import org.json.JSONArray;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtSession;
import ai.onnxruntime.TensorInfo;

final class OnnxCaptchaRecognizer implements AutoCloseable {
    private final OrtEnvironment environment;
    private final OrtSession session;
    private final String inputName;
    private final String[] charsets;

    OnnxCaptchaRecognizer(Context context) throws Exception {
        File model = new File(context.getFilesDir(), "common_old.onnx");
        if (!model.exists()) {
            try (InputStream source = context.getAssets().open("common_old.onnx");
                 FileOutputStream target = new FileOutputStream(model)) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = source.read(buffer)) != -1) target.write(buffer, 0, count);
            }
        }
        byte[] charsetBytes;
        try (InputStream source = context.getAssets().open("charsets_old.json")) {
            charsetBytes = new byte[source.available()];
            int offset = 0;
            while (offset < charsetBytes.length) {
                int count = source.read(charsetBytes, offset, charsetBytes.length - offset);
                if (count < 0) break;
                offset += count;
            }
        }
        JSONArray charsetJson = new JSONArray(new String(charsetBytes, java.nio.charset.StandardCharsets.UTF_8));
        charsets = new String[charsetJson.length()];
        for (int i = 0; i < charsets.length; i++) charsets[i] = charsetJson.optString(i);
        environment = OrtEnvironment.getEnvironment();
        OrtSession.SessionOptions options = new OrtSession.SessionOptions();
        options.setIntraOpNumThreads(1);
        options.setInterOpNumThreads(1);
        try {
            session = environment.createSession(model.getAbsolutePath(), options);
        } finally {
            options.close();
        }
        inputName = session.getInputNames().iterator().next();
    }

    String classify(Bitmap bitmap, String allowed) throws Exception {
        int height = 64;
        int width = Math.max(1, bitmap.getWidth() * height / bitmap.getHeight());
        Bitmap resized = Bitmap.createScaledBitmap(bitmap, width, height, true);
        ByteBuffer bytes = ByteBuffer.allocateDirect(width * height * Float.BYTES).order(ByteOrder.nativeOrder());
        FloatBuffer input = bytes.asFloatBuffer();
        int[] pixels = new int[width * height];
        resized.getPixels(pixels, 0, width, 0, 0, width, height);
        for (int pixel : pixels) {
            float red = (pixel >> 16) & 255, green = (pixel >> 8) & 255, blue = pixel & 255;
            float gray = (0.299f * red + 0.587f * green + 0.114f * blue) / 255f;
            input.put((gray - 0.5f) / 0.5f);
        }
        input.rewind();
        resized.recycle();
        try (OnnxTensor tensor = OnnxTensor.createTensor(environment, input, new long[]{1, 1, height, width});
             OrtSession.Result output = session.run(Collections.singletonMap(inputName, tensor))) {
            OnnxTensor result = (OnnxTensor) output.get(0);
            TensorInfo info = result.getInfo();
            long[] shape = info.getShape();
            int timesteps = (int) shape[0];
            int batch = shape.length == 3 ? (int) shape[1] : 1;
            int classes = (int) shape[shape.length - 1];
            FloatBuffer scores = result.getFloatBuffer();
            Set<Integer> allowedIndices = new HashSet<>();
            allowedIndices.add(0);
            for (int i = 1; i < charsets.length; i++) {
                if (!charsets[i].isEmpty() && allowed.contains(charsets[i])) allowedIndices.add(i);
            }
            StringBuilder text = new StringBuilder();
            int previous = -1;
            for (int t = 0; t < timesteps; t++) {
                int offset = t * batch * classes;
                int best = 0;
                float bestScore = -Float.MAX_VALUE;
                for (int index : allowedIndices) {
                    if (index >= classes) continue;
                    float score = scores.get(offset + index);
                    if (score > bestScore) {
                        bestScore = score;
                        best = index;
                    }
                }
                if (best != previous && best > 0 && best < charsets.length) text.append(charsets[best]);
                previous = best;
            }
            return text.toString().trim();
        }
    }

    @Override
    public void close() throws Exception {
        session.close();
    }
}
