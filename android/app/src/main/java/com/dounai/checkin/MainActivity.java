package com.dounai.checkin;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.TextView;

public class MainActivity extends Activity {
    private static final String PREFS = "site";
    private static final String URL_KEY = "url";
    private static final String PANEL_PATH = "/user/panel";

    private EditText siteUrl;
    private TextView status;
    private TextView lastResult;
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        siteUrl = findViewById(R.id.site_url);
        status = findViewById(R.id.status);
        lastResult = findViewById(R.id.last_result);
        webView = findViewById(R.id.web_view);
        siteUrl.setText(getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(URL_KEY, ""));

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        CookieManager.getInstance().setAcceptCookie(true);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("https".equalsIgnoreCase(uri.getScheme())) {
                    status.setText(uri.getHost());
                    return false;
                }
                status.setText("仅允许打开 HTTPS 网页");
                return true;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                Uri uri = Uri.parse(url);
                status.setText("当前站点：" + uri.getHost() + "。请在网页中完成验证码和签到。");
                String savedUrl = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(URL_KEY, "");
                if (!savedUrl.isEmpty() && uri.getHost() != null
                        && uri.getHost().equalsIgnoreCase(Uri.parse(savedUrl).getHost())) {
                    String cookie = CookieManager.getInstance().getCookie(savedUrl);
                    if (cookie != null && !cookie.trim().isEmpty()) {
                        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("cookie", cookie).apply();
                    }
                }
                CookieManager.getInstance().flush();
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    status.setText("页面加载失败：" + error.getDescription());
                }
            }
        });

        findViewById(R.id.open_panel).setOnClickListener(v -> openPanel());
        findViewById(R.id.settings).setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));
        findViewById(R.id.checkin_now).setOnClickListener(v -> {
            DailyScheduler.checkInNow(this);
            lastResult.setText("已提交一次签到任务；稍后打开应用查看结果。");
        });
        findViewById(R.id.reload_page).setOnClickListener(v -> {
            if (webView.getUrl() == null) {
                openPanel();
            } else {
                webView.reload();
            }
        });

        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState);
        }
    }

    private void openPanel() {
        String raw = siteUrl.getText().toString().trim();
        Uri uri = Uri.parse(raw);
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                || uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null
                || (uri.getPath() != null && !uri.getPath().isEmpty() && !"/".equals(uri.getPath()))) {
            siteUrl.setError("请输入站点的 HTTPS 根地址，例如 https://example.com");
            return;
        }
        String baseUrl = "https://" + uri.getEncodedAuthority();
        String previous = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(URL_KEY, "");
        if (!baseUrl.equals(previous)) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove("cookie").apply();
        }
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(URL_KEY, baseUrl).apply();
        status.setText("正在打开签到页…");
        webView.loadUrl(baseUrl + PANEL_PATH);
    }

    @Override
    protected void onResume() {
        super.onResume();
        lastResult.setText(getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("last_result", "尚无签到记录"));
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        webView.saveState(outState);
        super.onSaveInstanceState(outState);
    }

    @Override
    protected void onPause() {
        CookieManager.getInstance().flush();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        webView.destroy();
        super.onDestroy();
    }
}
