package com.dounai.checkin;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

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
    public void batteryAlertUsesStrictThresholdAndHysteresis() {
        assertEquals(false, BatteryMonitorWorker.shouldNotify(10, false, false));
        assertEquals(true, BatteryMonitorWorker.shouldNotify(9, false, false));
        assertEquals(false, BatteryMonitorWorker.shouldNotify(9, true, false));
        assertEquals(false, BatteryMonitorWorker.shouldNotify(9, false, true));
        assertEquals(false, BatteryMonitorWorker.shouldReset(14, false));
        assertEquals(true, BatteryMonitorWorker.shouldReset(15, false));
        assertEquals(true, BatteryMonitorWorker.shouldReset(5, true));
    }

    @Test
    public void currentCheckInPageTicketIsParsedAndSigned() throws Exception {
        String ticket = "1700000000.abc.def";
        assertEquals(ticket, CheckInClient.extractCheckInTicket(
                "<script>var checkinTicket = \"" + ticket + "\";</script>"));
        assertEquals("7490275144fdb42049c3bf91a82234dc59e68eb1143c6a25ff714f51391afa73",
                CheckInClient.sha256(ticket + "_4"));
    }

    @Test
    public void onlyCaptchaRejectionsUseTheCaptchaRetry() {
        assertTrue(CheckInClient.isCaptchaRejected("验证码错误，还剩2次机会"));
        assertTrue(CheckInClient.isCaptchaRejected("验证码不正确"));
        assertTrue(CheckInClient.isCaptchaRejected("验证码已过期，请刷新重试。"));
        assertTrue(CheckInClient.isCaptchaRejected("验证码超时"));
        assertFalse(CheckInClient.isCaptchaRejected("页面凭据已过期或失效"));
        assertFalse(CheckInClient.isCaptchaRejected("网络连接中断"));
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
