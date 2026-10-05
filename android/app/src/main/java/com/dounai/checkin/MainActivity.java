package com.dounai.checkin;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.text.method.PasswordTransformationMethod;
import android.view.inputmethod.InputMethodManager;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

public class MainActivity extends Activity {
    private static final String PREFS = "site";
    private static final String URL_KEY = "url";
    private static final String PANEL_PATH = "/user/panel";

    private EditText siteUrl;
    private TextView status;
    private TextView lastResult;
    private TextView sessionResult;
    private TextView passwordCount;
    private Button passwordInput;
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
        passwordInput = findViewById(R.id.password_input);
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
                passwordInput.setVisibility(View.GONE);
                passwordCount.setText("");
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("dounai-checkin".equalsIgnoreCase(uri.getScheme())
                        && "password".equalsIgnoreCase(uri.getHost())) {
                    if (isTrustedLoginPage()) showPasswordDialog();
                    return true;
                }
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
                        preparePasswordInput(view);
                    } else {
                        passwordInput.setVisibility(View.GONE);
                        passwordCount.setText("");
                    }
                    String cookie = CookieManager.getInstance().getCookie(savedUrl);
                    if (cookie != null && !cookie.trim().isEmpty()) {
                        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("cookie", cookie).apply();
                        if (!pageRejected && uri.getPath() != null && uri.getPath().startsWith("/user")) {
                            getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                                    .putBoolean("has_logged_in", true).apply();
                            SessionState.restored(MainActivity.this);
                            sessionResult.setText("登录态：网页登录成功");
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
        findViewById(R.id.runtime_log).setOnClickListener(v -> startActivity(new Intent(this, LogActivity.class)));
        findViewById(R.id.checkin_now).setOnClickListener(v -> {
            DailyScheduler.checkInNow(this);
            lastResult.setText("已提交一次签到任务；稍后打开应用查看结果。");
        });
        findViewById(R.id.logout).setOnClickListener(v -> confirmLogout());
        findViewById(R.id.reload_page).setOnClickListener(v -> {
            if (webView.getUrl() == null) {
                openPanel();
            } else {
                setBrowserMode(true);
                webView.reload();
            }
        });
        findViewById(R.id.exit_browser).setOnClickListener(v -> setBrowserMode(false));
        passwordInput.setOnClickListener(v -> showPasswordDialog());
        findViewById(R.id.browser_reload).setOnClickListener(v -> webView.reload());

        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState);
        }
        setBrowserMode(savedInstanceState != null && savedInstanceState.getBoolean("browser_mode"));
        DiagnosticLog.add(this, "app opened " + DiagnosticLog.screenState(this));
        DailyScheduler.ensureAlarm(this);
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

    private void preparePasswordInput(WebView view) {
        String script = "(function(){var p=document.getElementById('passwd');if(!p)return false;"
                + "p.type='password';p.style.removeProperty('-webkit-text-security');"
                + "p.readOnly=true;p.setAttribute('inputmode','none');"
                + "p.setAttribute('autocomplete','current-password');p.style.cursor='pointer';"
                + "if(!p.dataset.dounaiNativePassword){"
                + "p.addEventListener('click',function(){location.href='dounai-checkin://password';});"
                + "p.dataset.dounaiNativePassword='1';}return true;})()";
        view.evaluateJavascript(script, value -> {
            boolean present = "true".equals(value);
            passwordInput.setVisibility(present ? View.VISIBLE : View.GONE);
            if (present && passwordCount.getText().length() == 0) {
                passwordCount.setText("网页可能只显示 1 个圆点，请点“输入密码”并以这里的字符数为准");
            }
        });
    }

    private void showPasswordDialog() {
        if (!isTrustedLoginPage()) {
            passwordCount.setText("请先打开本站登录页");
            return;
        }
        final EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint("网站密码");
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        input.setTransformationMethod(PasswordTransformationMethod.getInstance());

        final TextView count = new TextView(this);
        count.setText("已输入 0 个字符");
        input.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int countValue) {
                count.setText("已输入 " + s.length() + " 个字符");
            }
            @Override public void afterTextChanged(Editable s) {}
        });

        final CheckBox show = new CheckBox(this);
        show.setText("显示密码");
        show.setOnCheckedChangeListener((button, checked) -> {
            int selection = input.getSelectionStart();
            input.setTransformationMethod(checked ? null : PasswordTransformationMethod.getInstance());
            input.setSelection(Math.max(0, selection));
        });

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (24 * getResources().getDisplayMetrics().density);
        content.setPadding(padding, 0, padding, 0);
        content.addView(input);
        content.addView(count);
        content.addView(show);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("输入网站密码")
                .setMessage("请在这里完整输入密码。填入后，部分手机的网页密码栏仍只显示 1 个圆点，这是显示问题；请以页面顶部字符数为准。密码不会保存，验证码仍在网页中输入。")
                .setView(content)
                .setNegativeButton("取消", null)
                .setPositiveButton("填入网页", null)
                .create();
        dialog.setOnShowListener(ignored -> {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                if (input.length() == 0) {
                    input.setError("请输入密码");
                    return;
                }
                injectPassword(input.getText().toString());
                input.setText("");
                dialog.dismiss();
            });
            input.requestFocus();
            dialog.getWindow().setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE);
        });
        dialog.show();
    }

    private void injectPassword(String value) {
        if (!isTrustedLoginPage()) {
            passwordCount.setText("登录页已离开，请返回后重新输入");
            return;
        }
        String encoded = JSONObject.quote(value);
        String script = "(function(){var p=document.getElementById('passwd');if(!p)return -1;"
                + "p.value=" + encoded + ";"
                + "p.dispatchEvent(new Event('input',{bubbles:true}));"
                + "p.dispatchEvent(new Event('change',{bubbles:true}));"
                + "p.blur();return p.value.length;})()";
        webView.evaluateJavascript(script, result -> {
            try {
                int length = Integer.parseInt(result);
                if (length < 0) {
                    passwordCount.setText("网页密码框不存在，请刷新网页");
                } else {
                    passwordCount.setText("密码已完整填入 " + length + " 个字符；网页只显示 1 个圆点也不影响登录");
                    passwordInput.setText("重新输入密码");
                }
            } catch (NumberFormatException error) {
                passwordCount.setText("密码填入失败，请刷新网页重试");
            }
        });
    }

    private boolean isTrustedLoginPage() {
        String currentUrl = webView.getUrl();
        String savedUrl = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(URL_KEY, "");
        if (currentUrl == null || savedUrl.isEmpty()) return false;
        Uri current = Uri.parse(currentUrl);
        Uri saved = Uri.parse(savedUrl);
        String path = current.getPath();
        return "https".equalsIgnoreCase(current.getScheme())
                && current.getHost() != null && saved.getHost() != null
                && current.getHost().equalsIgnoreCase(saved.getHost())
                && (path == null || path.isEmpty() || "/".equals(path));
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

    private void confirmLogout() {
        new AlertDialog.Builder(this)
                .setTitle("退出账号")
                .setMessage("将清除本机登录 Cookie，并关闭自动签到。通知配置会保留。")
                .setNegativeButton("取消", null)
                .setPositiveButton("退出", (dialog, which) -> logout())
                .show();
    }

    private void logout() {
        String url = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(URL_KEY, "");
        String cookie = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("cookie", "");
        status.setText("正在退出账号…");
        getSharedPreferences("settings", Context.MODE_PRIVATE).edit()
                .putBoolean("auto_enabled", false).apply();
        DailyScheduler.cancel(this);
        SessionRefreshScheduler.cancel(this);
        new Thread(() -> {
            String serverError = "";
            synchronized (CheckInWorker.RUN_LOCK) {
                if (!url.isEmpty() && !cookie.isEmpty()) {
                    try {
                        new CheckInClient(getApplicationContext(), url, cookie).logout();
                    } catch (Exception error) {
                        serverError = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
                    }
                }
                getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .remove("cookie").remove("last_result").remove("last_refresh_result")
                        .putBoolean("has_logged_in", false)
                        .putBoolean("login_expired", false)
                        .putBoolean("login_expired_notified", false).commit();
            }
            String finalServerError = serverError;
            runOnUiThread(() -> {
                CookieManager.getInstance().removeAllCookies(value -> CookieManager.getInstance().flush());
                webView.loadUrl("about:blank");
                setBrowserMode(false);
                lastResult.setText("尚无签到记录");
                sessionResult.setText("登录态：已退出");
                status.setText(finalServerError.isEmpty()
                        ? "已退出账号并关闭自动签到"
                        : "已清除本机登录状态；服务端退出未确认：" + finalServerError);
            });
        }).start();
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
