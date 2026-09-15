package com.dounai.checkin;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.inputmethod.InputMethodManager;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
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
    private TextView sessionResult;
    private TextView passwordCount;
    private WebView webView;
    private View appControls;
    private View browserControls;
    private boolean browserMode;
    private boolean pageRejected;
    private final Handler countHandler = new Handler(Looper.getMainLooper());
    private final Runnable countUpdater = new Runnable() {
        @Override public void run() {
            if (!browserMode) return;
            webView.evaluateJavascript("(function(){var p=document.getElementById('passwd');return p?p.value.length:-1;})()", value -> {
                if (!browserMode) return;
                try {
                    int count = Integer.parseInt(value);
                    passwordCount.setText(count < 0 ? "" : "密码 " + count + " 字符");
                } catch (NumberFormatException ignored) {
                    passwordCount.setText("");
                }
            });
            countHandler.postDelayed(this, 1500);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        siteUrl = findViewById(R.id.site_url);
        status = findViewById(R.id.status);
        lastResult = findViewById(R.id.last_result);
        sessionResult = findViewById(R.id.session_result);
        passwordCount = findViewById(R.id.password_count);
        webView = findViewById(R.id.web_view);
        appControls = findViewById(R.id.app_controls);
        browserControls = findViewById(R.id.browser_controls);
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
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                pageRejected = false;
            }

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
                    if ("/".equals(uri.getPath()) || uri.getPath() == null || uri.getPath().isEmpty()) {
                        view.evaluateJavascript("(function(){var p=document.getElementById('passwd');"
                                + "if(!p||p.dataset.dounaiPasswordInput)return;"
                                + "p.style.setProperty('-webkit-text-security','disc','important');"
                                + "if(getComputedStyle(p).webkitTextSecurity!=='disc')return;"
                                + "p.type='text';p.setAttribute('autocomplete','off');"
                                + "p.setAttribute('autocorrect','off');p.setAttribute('autocapitalize','off');"
                                + "p.setAttribute('spellcheck','false');"
                                + "p.dataset.dounaiPasswordInput='1';})()", null);
                    }
                    String cookie = CookieManager.getInstance().getCookie(savedUrl);
                    if (cookie != null && !cookie.trim().isEmpty()) {
                        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("cookie", cookie).apply();
                        if (!pageRejected && uri.getPath() != null && uri.getPath().startsWith("/user")) {
                            getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                                    .putBoolean("has_logged_in", true).apply();
                            SessionState.restored(MainActivity.this);
                            SessionRefreshScheduler.schedule(MainActivity.this);
                        }
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

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                if (!request.isForMainFrame() || response.getStatusCode() != 401
                        || !(PANEL_PATH.equals(request.getUrl().getPath())
                        || "/user".equals(request.getUrl().getPath()))) return;
                String savedUrl = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(URL_KEY, "");
                if (savedUrl.isEmpty() || !request.getUrl().getHost().equalsIgnoreCase(Uri.parse(savedUrl).getHost())) return;
                pageRejected = true;
                getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("login_expired", true).apply();
                SessionRefreshScheduler.notifyExpiry(MainActivity.this);
                status.setText("登录状态已失效；正在打开登录页…");
                view.post(() -> view.loadUrl(savedUrl + "/"));
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
                setBrowserMode(true);
                webView.reload();
            }
        });
        findViewById(R.id.exit_browser).setOnClickListener(v -> setBrowserMode(false));
        findViewById(R.id.browser_reload).setOnClickListener(v -> webView.reload());

        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState);
        }
        setBrowserMode(savedInstanceState != null && savedInstanceState.getBoolean("browser_mode"));
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
        String cookie = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("cookie", "");
        if (!baseUrl.equals(previous)) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .remove("cookie").putBoolean("has_logged_in", false)
                    .putBoolean("login_expired", false)
                    .putBoolean("login_expired_notified", false).apply();
            cookie = "";
        }
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(URL_KEY, baseUrl).apply();
        boolean loggedIn = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("has_logged_in", false)
                && !getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("login_expired", false)
                && !cookie.isEmpty();
        status.setText(loggedIn ? "正在打开签到页…" : "正在打开登录页…");
        setBrowserMode(true);
        webView.loadUrl(baseUrl + (loggedIn ? PANEL_PATH : "/"));
    }

    private void setBrowserMode(boolean enabled) {
        if (browserMode && !enabled) {
            InputMethodManager keyboard = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
            keyboard.hideSoftInputFromWindow(webView.getWindowToken(), 0);
            webView.clearFocus();
        }
        browserMode = enabled;
        appControls.setVisibility(enabled ? View.GONE : View.VISIBLE);
        browserControls.setVisibility(enabled ? View.VISIBLE : View.GONE);
        countHandler.removeCallbacks(countUpdater);
        if (enabled) countHandler.post(countUpdater);
    }

    @Override
    protected void onResume() {
        super.onResume();
        lastResult.setText(getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("last_result", "尚无签到记录"));
        sessionResult.setText("登录态：" + getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("last_refresh_result", "尚未自动刷新"));
    }

    @Override
    public void onBackPressed() {
        if (browserMode && webView.canGoBack()) {
            webView.goBack();
        } else if (browserMode) {
            setBrowserMode(false);
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        outState.putBoolean("browser_mode", browserMode);
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
        countHandler.removeCallbacks(countUpdater);
        webView.destroy();
        super.onDestroy();
    }
}
