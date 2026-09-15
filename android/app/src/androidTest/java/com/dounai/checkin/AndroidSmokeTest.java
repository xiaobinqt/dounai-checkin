package com.dounai.checkin;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class AndroidSmokeTest {
    @Test
    public void svgCaptchaIsSolvedOnAndroid() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("4", CaptchaSolver.solve(context,
                "<svg><text>玖</text><text>-</text><text>伍</text><text>=</text></svg>"));
    }

    @Test
    public void onnxModelLoadsAndRunsOnAndroid() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        Bitmap bitmap = Bitmap.createBitmap(140, 44, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.WHITE);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.BLACK);
        paint.setTextSize(32);
        canvas.drawText("9-5=", 6, 34, paint);
        try (OnnxCaptchaRecognizer recognizer = new OnnxCaptchaRecognizer(context)) {
            assertNotNull(recognizer.classify(bitmap, "0123456789+-="));
        }
    }
}
