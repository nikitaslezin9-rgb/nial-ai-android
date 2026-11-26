package app.nial.ai;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class NialIntroActivity extends Activity {
    private WebView web;

    private SharedPreferences prefs() {
        return getSharedPreferences("nial_intro", MODE_PRIVATE);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        boolean night = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        int bg = night ? Color.parseColor("#06040F") : Color.parseColor("#EFE9FF");
        getWindow().getDecorView().setBackgroundColor(bg);
        web = new WebView(this);
        web.setBackgroundColor(bg);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new Bridge(), "NialBridge");
        setContentView(web);
        web.loadUrl("file:///android_asset/intro.html?theme=" + (night ? "dark" : "light"));
    }

    private class Bridge {
        @JavascriptInterface
        public void saveProfile(String name, String age, String addr) {
            prefs().edit().putString("name", name).putString("age", age).putString("addr", addr).apply();
        }

        @JavascriptInterface
        public void complete(int pick) {
            prefs().edit().putBoolean("done", true).putInt("pick", pick).apply();
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    NialIntroActivity.this.finish();
                }
            });
        }
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.destroy();
        }
        super.onDestroy();
    }
}