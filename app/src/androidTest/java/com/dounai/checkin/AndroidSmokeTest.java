package com.dounai.checkin;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Base64;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

@RunWith(AndroidJUnit4.class)
public class AndroidSmokeTest {
    @Test
    public void currentCheckInPageTicketIsParsedAndSigned() throws Exception {
        String ticket = "1700000000.abc.def";
        assertEquals(ticket, CheckInClient.extractCheckInTicket(
                "<script>var checkinTicket = \"" + ticket + "\";</script>"));
        assertEquals("7490275144fdb42049c3bf91a82234dc59e68eb1143c6a25ff714f51391afa73",
                CheckInClient.sha256(ticket + "_4"));
    }

    @Test
    public void svgCaptchaIsSolvedOnAndroid() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("4", CaptchaSolver.solve(context,
                "<svg><text>玖</text><text>-</text><text>伍</text><text>=</text></svg>"));
    }

    @Test
    public void pngCaptchaWithThinMinusIsSolvedOnAndroid() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = InstrumentationRegistry.getInstrumentation().getContext()
                .getAssets().open("captcha-six-minus-two.png")) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
        }
        String markup = "data:image/png;base64,"
                + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP);
        assertEquals("4", CaptchaSolver.solve(context, markup));
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
