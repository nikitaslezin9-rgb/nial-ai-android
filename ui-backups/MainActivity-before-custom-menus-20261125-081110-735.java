package app.nial.ai;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputFilter;
import android.text.InputType;
import android.util.Base64;
import android.view.Gravity;
import android.view.WindowInsets;
import android.widget.*;
import org.json.JSONArray;
import org.json.JSONObject;
import javax.net.ssl.HttpsURLConnection;
import java.io.*;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class MainActivity extends Activity {
    private static final String BASE =
        "https://steady-wisp-637e8f.netlify.app";

    private final String[] ids = {"talk", "code", "learn"};
    private final String[] names = {
        "Собеседник", "Программист", "Наставник"
    };

    private int bg = Color.rgb(245,244,250);
    private int purple = Color.rgb(106,104,223);
    private int ink = Color.rgb(46,44,45);
    private int muted = Color.rgb(137,131,144);

    private final JSONArray[] chats = new JSONArray[3];
    private final String[] drafts = {"", "", ""};
    private final Button[] tabs = new Button[3];

    private SharedPreferences prefs;
    private LinearLayout messages;
    private ScrollView scroll;
    private EditText input;
    private TextView status;
    private Button send, clear;
    private int active = 0;
    private boolean busy = false;



    private String memory = "";

    @Override
    public void onCreate(Bundle saved) {
        super.onCreate(saved);
        prefs = getSharedPreferences("nial_native_v1", MODE_PRIVATE);
        prefs.edit().remove("access_iv").remove("access_data").apply();

        memory = prefs.getString("memory", "");
        active = Math.max(0, Math.min(2, prefs.getInt("active", 0)));

        for (int i = 0; i < 3; i++) {
            try {
                chats[i] = new JSONArray(prefs.getString(ids[i], "[]"));
            } catch (Exception e) {
                chats[i] = new JSONArray();
            }
            drafts[i] = prefs.getString("draft_" + ids[i], "");
        }

        loadAppearance();
        buildScreen();
        render();
    }

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + .5f);
    }

    private GradientDrawable shape(int color, int radius) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radius));
        return drawable;
    }

    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        return view;
    }

    private Button button(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setTextColor(purple);
        button.setTextSize(12);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setBackground(shape(surface, 16));
        return button;
    }

    private android.widget.FrameLayout screenHost;
    private LinearLayout chatScreen;
    private LinearLayout homeScreen;
    private LinearLayout welcomeScreen;
    private String currentScreen = "welcome";

    private LinearLayout column() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        return box;
    }

    private void space(LinearLayout box, int height) {
        android.view.View gap = new android.view.View(this);
        box.addView(gap, new LinearLayout.LayoutParams(1, dp(height)));
    }

    private Button primary(String label) {
        Button view = button(label);
        view.setTextColor(Color.WHITE);
        view.setTextSize(14);
        view.setBackground(shape(purple, 16));
        return view;
    }

    private TextView heading(String label, int size) {
        TextView view = text(label, size, ink);
        view.setTypeface(null, Typeface.BOLD);
        view.setLineSpacing(dp(2), 1);
        return view;
    }

    private void showScreen(String name) {
        if (chatScreen != null && input != null) {
            drafts[active] = input.getText().toString();
            persist();
        }

        currentScreen = name;
        android.view.View target = "chat".equals(name) ? chatScreen
            : "home".equals(name) ? homeScreen : welcomeScreen;
        target.animate().cancel();
        target.setAlpha(0f);
        target.setTranslationY(dp(12));
        target.animate().alpha(1f).translationY(0f)
            .setDuration(260).start();
        welcomeScreen.setVisibility(
            "welcome".equals(name) ? android.view.View.VISIBLE : android.view.View.GONE);
        homeScreen.setVisibility(
            "home".equals(name) ? android.view.View.VISIBLE : android.view.View.GONE);
        chatScreen.setVisibility(
            "chat".equals(name) ? android.view.View.VISIBLE : android.view.View.GONE);
    }

    private void enterAgent(int index) {
        switchAgent(index);
        showScreen("chat");
    }

    private void buildScreen() {
        LinearLayout outer = column();
        outer.setBackgroundColor(bg);
        setContentView(outer);

        outer.setOnApplyWindowInsetsListener((view, insets) -> {
            Insets safe = insets.getInsets(
                WindowInsets.Type.systemBars()
                | WindowInsets.Type.ime()
                | WindowInsets.Type.displayCutout());
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom);
            return WindowInsets.CONSUMED;
        });

        LinearLayout top = new LinearLayout(this);
        top.setPadding(dp(18), dp(9), dp(14), dp(4));
        top.setGravity(Gravity.CENTER_VERTICAL);

        TextView brand = text("Nial AI", 18, ink);
        brand.setLetterSpacing(.10f);
        top.addView(brand, new LinearLayout.LayoutParams(0, dp(44), 1));

        Button memoryButton = button("Профиль");
        memoryButton.setTextSize(11);
        memoryButton.setOnClickListener(v -> openProfileMenu());
        // NIAL_ORIGINAL_LAYOUT_THEME_PILL
        Button themeButton = button("тема");
        themeButton.setTextSize(14);
        themeButton.setBackground(shape(surface, 100));
        themeButton.setContentDescription("Тема: цвет и светлый или тёмный режим");
        themeButton.setOnClickListener(v -> showAppearance());
        LinearLayout.LayoutParams themeParams =
            new LinearLayout.LayoutParams(dp(80), dp(48));
        themeParams.setMargins(0, 0, dp(8), 0);
        top.addView(themeButton, themeParams);
        top.addView(memoryButton);
        outer.addView(top);

        screenHost = new android.widget.FrameLayout(this);
        outer.addView(screenHost, new LinearLayout.LayoutParams(-1, 0, 1));

        welcomeScreen = column();
        homeScreen = column();
        chatScreen = column();

        welcomeScreen.setPadding(dp(20), 0, dp(20), dp(18));
        homeScreen.setPadding(dp(18), 0, dp(18), dp(12));
        chatScreen.setPadding(dp(18), dp(8), dp(18), dp(10));

        screenHost.addView(welcomeScreen,
            new android.widget.FrameLayout.LayoutParams(-1, -1));
        screenHost.addView(homeScreen,
            new android.widget.FrameLayout.LayoutParams(-1, -1));
        screenHost.addView(chatScreen,
            new android.widget.FrameLayout.LayoutParams(-1, -1));

        buildWelcome();
        buildHome();
        buildChat();

        input.setText(drafts[active]);

        showScreen(prefs.getBoolean("onboarded", false) ? "home" : "welcome");
    }

    private TextView profileGreeting;

    private String profileHello() {
        String name = prefs.getString("profile_display_name", "").trim();
        return name.isEmpty() ? "Привет!" : "Привет, " + name + "!";
    }

    private void editProfileName() {
        EditText field = new EditText(this);
        field.setText(prefs.getString("profile_display_name", ""));
        field.setHint("Как к тебе обращаться?");
        field.setTextSize(18);
        field.setSingleLine(true);
        field.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        field.setFilters(new InputFilter[]{new InputFilter.LengthFilter(40)});
        LinearLayout box = column();
        box.setPadding(dp(24), dp(12), dp(24), dp(8));
        box.addView(field, new LinearLayout.LayoutParams(-1, -2));
        dialogBuilder()
            .setTitle("Моё имя")
            .setMessage("Имя сохраняется только на этом телефоне и используется в интерфейсе.")
            .setView(box)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Сохранить", (dialog, which) -> {
                prefs.edit().putString("profile_display_name",
                    field.getText().toString().trim()).apply();
                if (profileGreeting != null) profileGreeting.setText(profileHello());
            }).show();
    }

    private void openProfileMenu() {
        dialogBuilder()
            .setTitle("Настройки")
            .setItems(new String[]{"Моё имя", "Общая память", "Оформление", "О приложении"},
                (dialog, which) -> {
                    if (which == 0) editProfileName();
                    else if (which == 1) editMemory();
                    else if (which == 2) showAppearance();
                    else dialogBuilder()
                        .setTitle("О приложении")
                        .setMessage("Nial AI\nНа базе GigaChat.\n\n"
                            + "AI может ошибаться. Контекст разговора и общая память "
                            + "передаются серверу и GigaChat для ответа.\n\n"
                            + "Переписки хранятся на этом устройстве без дополнительного "
                            + "шифрования. Не сохраняй пароли и ключи.")
                        .setPositiveButton("Понятно", null).show();
                }).show();
    }

    private int surface = Color.WHITE;
    private int soft = Color.rgb(234,228,247);
    private int outline = Color.rgb(220,213,230);
    private boolean darkMode = false;

    private void loadAppearance() {
        String mode = prefs.getString("ui_mode", "system");
        int systemMode = getResources().getConfiguration().uiMode
            & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
        darkMode = "dark".equals(mode) || ("system".equals(mode)
            && systemMode == android.content.res.Configuration.UI_MODE_NIGHT_YES);
        String palette = prefs.getString("ui_palette", "lavender");
        if (darkMode) {
            bg = Color.rgb(23,23,27);
            surface = Color.rgb(34,34,39);
            ink = Color.rgb(244,240,243);
            muted = Color.rgb(189,182,190);
            outline = Color.rgb(79,70,79);
            if ("burgundy".equals(palette)) {
                purple = Color.rgb(177,66,90);
                soft = Color.rgb(65,33,42);
                bg = Color.rgb(27,19,22);
                surface = Color.rgb(43,29,34);
            } else if ("green".equals(palette)) {
                purple = Color.rgb(66,119,85);
                soft = Color.rgb(34,55,43);
                bg = Color.rgb(19,25,22);
                surface = Color.rgb(29,38,32);
            } else if ("peach".equals(palette)) {
                purple = Color.rgb(164,85,46);
                soft = Color.rgb(65,43,32);
                bg = Color.rgb(28,22,19);
                surface = Color.rgb(43,33,28);
            } else {
                purple = Color.rgb(112,93,186);
                soft = Color.rgb(47,39,68);
            }
        } else {
            bg = Color.rgb(245,244,250);
            surface = Color.WHITE;
            ink = Color.rgb(46,38,43);
            muted = Color.rgb(108,99,110);
            outline = Color.rgb(218,208,220);
            purple = Color.rgb(106,104,223);
            soft = Color.rgb(234,228,247);
            if ("burgundy".equals(palette)) {
                bg = Color.rgb(250,242,241);
                surface = Color.rgb(255,250,248);
                purple = Color.rgb(134,43,65);
                soft = Color.rgb(243,220,223);
                outline = Color.rgb(218,185,191);
            } else if ("green".equals(palette)) {
                bg = Color.rgb(242,247,240);
                surface = Color.rgb(252,254,248);
                purple = Color.rgb(61,107,73);
                soft = Color.rgb(221,235,217);
                outline = Color.rgb(190,209,186);
            } else if ("peach".equals(palette)) {
                bg = Color.rgb(255,246,238);
                surface = Color.rgb(255,252,247);
                purple = Color.rgb(155,74,38);
                soft = Color.rgb(251,226,206);
                outline = Color.rgb(225,199,178);
            }
        }
        getWindow().setStatusBarColor(bg);
        getWindow().setNavigationBarColor(bg);
        int flags = getWindow().getDecorView().getSystemUiVisibility();
        int light = android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            | android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        getWindow().getDecorView().setSystemUiVisibility(
            darkMode ? (flags & ~light) : (flags | light));
    }

    private AlertDialog.Builder dialogBuilder() {
        return new NialDialogBuilder();
    }

    private class NialDialogBuilder extends AlertDialog.Builder {
        NialDialogBuilder() {
            super(MainActivity.this, MainActivity.this.darkMode
                ? android.R.style.Theme_Material_Dialog_Alert
                : android.R.style.Theme_Material_Light_Dialog_Alert);
        }

        @Override
        public AlertDialog show() {
            AlertDialog dialog = super.show();
            android.view.Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(shape(surface, 26));
                android.view.View decor = window.getDecorView();
                decor.setBackground(shape(surface, 26));
                decor.setClipToOutline(true);
                window.setLayout(Math.min(
                    getResources().getDisplayMetrics().widthPixels - dp(32),
                    dp(560)), android.view.ViewGroup.LayoutParams.WRAP_CONTENT);
                styleDialogTree(decor);
            }
            for (int which : new int[]{AlertDialog.BUTTON_POSITIVE,
                    AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_NEUTRAL}) {
                Button button = dialog.getButton(which);
                if (button == null) continue;
                button.setAllCaps(false);
                button.setTextColor(purple);
                button.setTextSize(16);
                button.setMinHeight(dp(56));
                button.setMinimumHeight(dp(56));
                button.setPadding(dp(16), dp(10), dp(16), dp(10));
            }
            return dialog;
        }
    }

    private void styleDialogTree(android.view.View view) {
        if (view instanceof TextView) {
            TextView label = (TextView) view;
            label.setTextColor(ink);
            if (label.getTextSize() / getResources().getDisplayMetrics().scaledDensity < 16)
                label.setTextSize(16);
        }
        if (view instanceof EditText) {
            EditText field = (EditText) view;
            field.setHintTextColor(muted);
            field.setTextSize(18);
            field.setPadding(dp(16), dp(14), dp(16), dp(14));
            GradientDrawable fieldBackground = shape(soft, 18);
            fieldBackground.setStroke(dp(1), outline);
            field.setBackground(fieldBackground);
            field.setBackgroundTintList(null);
        }
        if (view instanceof android.view.ViewGroup) {
            android.view.ViewGroup group = (android.view.ViewGroup) view;
            if (group.getParent() instanceof android.view.View)
                group.setBackgroundColor(surface);
            for (int i = 0; i < group.getChildCount(); i++)
                styleDialogTree(group.getChildAt(i));
        }
    }

    private void showAppearance() {
        if (busy) {
            Toast.makeText(this, "Дождись ответа, чтобы изменить оформление",
                Toast.LENGTH_SHORT).show();
            return;
        }
        dialogBuilder().setTitle("Оформление")
            .setItems(new String[]{"Цветовая тема", "Светлый / тёмный режим"},
                (dialog, which) -> {
                    if (which == 0) choosePalette(); else chooseMode();
                })
            .setNegativeButton("Закрыть", null).show();
    }

    private void choosePalette() {
        final String[] values = {"lavender", "green", "peach", "burgundy"};
        String saved = prefs.getString("ui_palette", "lavender");
        int selected = 0;
        for (int i = 0; i < values.length; i++)
            if (values[i].equals(saved)) selected = i;
        dialogBuilder().setTitle("Цветовая тема")
            .setSingleChoiceItems(new String[]{"Лавандовая", "Зелёная",
                "Персиковая", "Бордовая"}, selected, (dialog, which) -> {
                prefs.edit().putString("ui_palette", values[which]).apply();
                dialog.dismiss();
                rebuildAppearance();
            }).setNegativeButton("Отмена", null).show();
    }

    private void chooseMode() {
        final String[] values = {"system", "light", "dark"};
        String saved = prefs.getString("ui_mode", "system");
        int selected = 0;
        for (int i = 0; i < values.length; i++)
            if (values[i].equals(saved)) selected = i;
        dialogBuilder().setTitle("Режим оформления")
            .setSingleChoiceItems(new String[]{"Как в системе", "Светлый", "Тёмный"},
                selected, (dialog, which) -> {
                    prefs.edit().putString("ui_mode", values[which]).apply();
                    dialog.dismiss();
                    rebuildAppearance();
                }).setNegativeButton("Отмена", null).show();
    }

    private void rebuildAppearance() {
        if (busy) return;
        String page = currentScreen;
        if (input != null) drafts[active] = input.getText().toString();
        persist();
        loadAppearance();
        buildScreen();
        render();
        showScreen(page);
    }

    private void buildWelcome() {
        ScrollView page = new ScrollView(this);
        page.setFillViewport(true);
        LinearLayout content = column();
        content.setPadding(0, dp(18), 0, dp(12));

        android.text.SpannableString title =
            new android.text.SpannableString(
                "Твой умный\nпомощник\nна каждый день.");
        title.setSpan(new android.text.style.ForegroundColorSpan(purple),
            5, 19, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);

        TextView headline = heading("", 42);
        headline.setText(title);
        headline.setLetterSpacing(-.05f);
        content.addView(headline);

        android.widget.FrameLayout art = new android.widget.FrameLayout(this);
        OrbView orb = new OrbView();
        android.widget.FrameLayout.LayoutParams op =
            new android.widget.FrameLayout.LayoutParams(dp(190), dp(210));
        op.gravity = Gravity.CENTER;
        art.addView(orb, op);

        TextView hello = text("Привет, я Nial!", 13, ink);
        hello.setPadding(dp(17), dp(11), dp(17), dp(11));
        hello.setBackground(shape(surface, 18));
        hello.setRotation(5);
        android.widget.FrameLayout.LayoutParams hp =
            new android.widget.FrameLayout.LayoutParams(-2, -2);
        hp.gravity = Gravity.TOP | Gravity.RIGHT;
        hp.setMargins(0, dp(14), dp(10), 0);
        art.addView(hello, hp);

        content.addView(art, new LinearLayout.LayoutParams(-1, dp(270)));

        TextView sub = text(
            "Для больших идей, маленьких вопросов и разговоров обо всём.",
            15, muted);
        sub.setLineSpacing(dp(4), 1);
        content.addView(sub);
        space(content, 22);

        Button start = button("Начать знакомство                         →");
        start.setTextColor(ink);
        start.setTextSize(15);
        start.setOnClickListener(v -> {
            prefs.edit().putBoolean("onboarded", true).apply();
            showScreen("home");
        });
        content.addView(start, new LinearLayout.LayoutParams(-1, dp(56)));

        page.addView(content);
        welcomeScreen.addView(page, new LinearLayout.LayoutParams(-1, -1));
    }

    private void buildHome() {
        ScrollView page = new ScrollView(this);
        LinearLayout content = column();
        space(content, 14);
        profileGreeting = heading(profileHello(), 30);
        profileGreeting.setOnClickListener(v -> editProfileName());
        content.addView(profileGreeting);
        space(content, 8);
        content.addView(text("Что сегодня придумаем вместе?", 14, muted));
        space(content, 23);

        LinearLayout hero = new LinearLayout(this);
        hero.setGravity(Gravity.CENTER_VERTICAL);
        hero.setPadding(dp(19), dp(22), dp(10), dp(22));
        hero.setBackground(shape(soft, 28));

        LinearLayout copy = column();

        TextView tag = text("Твой AI-помощник", 10, muted);
        tag.setPadding(dp(10), dp(5), dp(10), dp(5));
        tag.setBackground(shape(surface, 14));
        copy.addView(tag, new LinearLayout.LayoutParams(-2, -2));

        space(copy, 13);
        copy.addView(heading("Любая идея\nначинается\nс разговора.", 25));
        space(copy, 11);
        copy.addView(text("Выбери, чем займёмся.\nЯ рядом.", 12, muted));
        space(copy, 14);

        Button talk = primary("Давай поговорим →");
        talk.setTextSize(12);
        talk.setOnClickListener(v -> enterAgent(0));
        copy.addView(talk, new LinearLayout.LayoutParams(-1, dp(48)));

        hero.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));
        hero.addView(new OrbView(),
            new LinearLayout.LayoutParams(dp(112), dp(150)));
        content.addView(hero);
        space(content, 26);

        content.addView(heading("С чего начнём?", 20));
        space(content, 5);
        content.addView(text("У каждого своя переписка", 11, muted));
        space(content, 13);

        LinearLayout cards = new LinearLayout(this);
        String[] symbols = {"…", "</>", "Aa"};
        String[] titles = {"Поговорить", "Помочь\nс кодом", "Объяснить\nтему"};
        String[] subtitles = {"Собеседник", "Программист", "Наставник"};
        int[] accents = {
            Color.rgb(238,232,252),
            Color.rgb(255,240,229),
            Color.rgb(231,241,233)
        };

        for (int i = 0; i < 3; i++) {
            final int index = i;
            LinearLayout card = column();
            card.setPadding(dp(10), dp(17), dp(8), dp(17));
            card.setBackground(shape(surface, 20));

            TextView icon = text(symbols[i], 18, purple);
            icon.setGravity(Gravity.CENTER);
            icon.setBackground(shape(darkMode ? soft : accents[i], 13));
            card.addView(icon, new LinearLayout.LayoutParams(dp(40), dp(40)));
            space(card, 20);

            TextView title = heading(titles[i], 13);
            title.setMinHeight(dp(38));
            card.addView(title);
            space(card, 5);
            card.addView(text(subtitles[i], 10, muted));

            card.setOnClickListener(v -> enterAgent(index));

            LinearLayout.LayoutParams cp =
                new LinearLayout.LayoutParams(0, -1, 1);
            cp.setMargins(i == 0 ? 0 : dp(5), 0,
                i == 2 ? 0 : dp(5), 0);
            cards.addView(card, cp);
        }

        content.addView(cards, new LinearLayout.LayoutParams(-1, dp(182)));
        space(content, 26);
        content.addView(heading("Общая память", 20));
        space(content, 12);

        TextView memoryCard = text(
            "Ты решаешь, что помнить.\n"
            + "Нажми, чтобы посмотреть и изменить заметки.", 13, muted);
        memoryCard.setPadding(dp(18), dp(18), dp(18), dp(18));

        GradientDrawable memoryBackground = shape(bg, 18);
        memoryBackground.setStroke(dp(1), outline,
            dp(5), dp(4));
        memoryCard.setBackground(memoryBackground);
        memoryCard.setOnClickListener(v -> editMemory());
        content.addView(memoryCard);

        space(content, 16);
        // Storage disclosure is available in Profile > About.
        space(content, 20);

        space(content, 14);
        page.addView(content);
        homeScreen.addView(page, new LinearLayout.LayoutParams(-1, -1));
    }

    private void buildChat() {
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);

        Button back = button("‹");
        back.setTextSize(28);
        back.setOnClickListener(v -> showScreen("home"));
        header.addView(back, new LinearLayout.LayoutParams(dp(40), dp(44)));

        header.addView(new OrbView(),
            new LinearLayout.LayoutParams(dp(48), dp(50)));

        LinearLayout title = column();
        title.setPadding(dp(8), 0, 0, 0);
        title.addView(heading("Nial Ai", 18));
        title.addView(text("На базе GigaChat", 11, muted));
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));

        clear = button("Очистить");
        clear.setTextSize(10);
        clear.setOnClickListener(v -> clearChat());
        header.addView(clear);
        chatScreen.addView(header);
        space(chatScreen, 12);

        LinearLayout tabRow = new LinearLayout(this);
        for (int i = 0; i < 3; i++) {
            final int index = i;
            tabs[i] = button(names[i]);
            tabs[i].setTextSize(10);
            LinearLayout.LayoutParams tp =
                new LinearLayout.LayoutParams(0, dp(40), 1);
            tp.setMargins(dp(2), 0, dp(2), 0);
            tabRow.addView(tabs[i], tp);
            tabs[i].setOnClickListener(v -> switchAgent(index));
        }
        chatScreen.addView(tabRow);

        scroll = new ScrollView(this);
        scroll.setFillViewport(true);

        messages = column();
        messages.setPadding(0, dp(20), 0, dp(12));
        scroll.addView(messages);
        chatScreen.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        status = text("", 12, purple);
        status.setPadding(dp(4), dp(5), dp(4), dp(5));
        chatScreen.addView(status);

        LinearLayout compose = new LinearLayout(this);
        compose.setGravity(Gravity.BOTTOM);
        compose.setPadding(dp(14), dp(6), dp(7), dp(6));
        GradientDrawable inputBackground = shape(surface, 23);
        inputBackground.setStroke(dp(1), outline);
        compose.setBackground(inputBackground);

        input = new EditText(this);
        input.setTextColor(ink);
        input.setTextSize(15);
        input.setHint("Напиши сообщение…");
        input.setHintTextColor(muted);
        input.setBackgroundColor(Color.TRANSPARENT);
        input.setInputType(InputType.TYPE_CLASS_TEXT
            | InputType.TYPE_TEXT_FLAG_MULTI_LINE
            | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        input.setMaxLines(5);
        input.setFilters(new InputFilter[]{
            new InputFilter.LengthFilter(5000)
        });
        compose.addView(input, new LinearLayout.LayoutParams(0, -2, 1));

        send = primary("↑");
        send.setTextSize(24);
        send.setBackground(shape(purple, 25));
        send.setOnClickListener(v -> sendMessage());
        compose.addView(send,
            new LinearLayout.LayoutParams(dp(46), dp(46)));
        chatScreen.addView(compose);

        TextView footer = text(
            "AI может ошибаться · Контекст передаётся GigaChat", 9, muted);
        footer.setGravity(Gravity.CENTER);
        footer.setPadding(0, dp(8), 0, dp(3));
        // AI disclosure is available in Profile > About.
    }

    private class OrbView extends android.view.View {
        private final android.graphics.Paint paint =
            new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final long started = android.os.SystemClock.uptimeMillis();

        OrbView() {
            super(MainActivity.this);
            setImportantForAccessibility(
                android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);

            float time = (android.os.SystemClock.uptimeMillis() - started) / 1000f;
            float radius = Math.min(getWidth() * .43f, getHeight() * .36f);
            float cx = getWidth() / 2f;
            float cy = getHeight() * .45f
                + (float)Math.sin(time * (busy ? 3.2f : 1.25f)) * radius * .045f;

            paint.setShader(new android.graphics.RadialGradient(
                cx, getHeight() * .87f, radius,
                new int[]{0x449B70CF, 0x00CBA3D8},
                null, android.graphics.Shader.TileMode.CLAMP));
            canvas.save();
            canvas.scale(1, .19f, cx, getHeight() * .87f);
            canvas.drawCircle(cx, getHeight() * .87f, radius, paint);
            canvas.restore();

            paint.setShader(new android.graphics.LinearGradient(
                cx - radius, cy - radius, cx + radius * .6f, cy + radius,
                new int[]{
                    Color.rgb(220,164,238),
                    Color.rgb(170,119,221),
                    Color.rgb(239,169,146),
                    Color.rgb(255,226,175)
                },
                new float[]{0, .53f, .84f, 1},
                android.graphics.Shader.TileMode.CLAMP));
            canvas.drawCircle(cx, cy, radius, paint);

            paint.setShader(new android.graphics.RadialGradient(
                cx - radius * .38f, cy - radius * .55f, radius * 1.3f,
                new int[]{0x66FFE2F7, 0x00FFFFFF},
                null, android.graphics.Shader.TileMode.CLAMP));
            canvas.drawCircle(cx, cy, radius, paint);

            paint.setShader(null);
            paint.setColor(Color.WHITE);
            paint.setStyle(android.graphics.Paint.Style.FILL);

            float blink = (time % 6.5f > 6.29f) ? .12f : 1f;
            float eyeY = cy - radius * .02f;
            float eyeH = radius * .16f * blink;
            for (int side : new int[]{-1, 1}) {
                float eyeX = cx + side * radius * .23f;
                canvas.drawOval(
                    eyeX - radius * .065f, eyeY - eyeH,
                    eyeX + radius * .065f, eyeY + eyeH, paint);
            }

            paint.setStyle(android.graphics.Paint.Style.STROKE);
            paint.setStrokeWidth(Math.max(1.4f, radius * .026f));
            paint.setStrokeCap(android.graphics.Paint.Cap.ROUND);
            canvas.drawArc(cx - radius * .14f, cy + radius * .23f,
                cx + radius * .14f, cy + radius * .39f,
                10, 160, false, paint);
            paint.setStyle(android.graphics.Paint.Style.FILL);

            if (isShown()) postInvalidateDelayed(40);
        }

        @Override
        protected void onVisibilityChanged(android.view.View changed, int visibility) {
            super.onVisibilityChanged(changed, visibility);
            if (visibility == android.view.View.VISIBLE) invalidate();
        }
    }

    @Override
    public void onBackPressed() {
        if ("chat".equals(currentScreen)) {
            showScreen("home");
        } else if ("home".equals(currentScreen)) {
            showScreen("welcome");
        } else {
            super.onBackPressed();
        }
    }
    private void switchAgent(int index) {
        drafts[active] = input.getText().toString();
        active = index;
        persist();
        render();
    }

    private void render() {
        for (int i = 0; i < 3; i++) {
            tabs[i].setTextColor(i == active ? Color.WHITE : purple);
            tabs[i].setBackground(shape(i == active ? purple : surface, 18));
        }

        input.setText(drafts[active]);
        input.setSelection(input.length());
        messages.removeAllViews();

        JSONArray history = chats[active];
        if (history.length() == 0) {
            TextView empty = text(
                names[active] + "\n\nО чём поговорим?",
                21, purple);
            empty.setGravity(Gravity.CENTER);
            empty.setPadding(dp(12), dp(55), dp(12), dp(35));
            messages.addView(empty);
        }

        for (int i = 0; i < history.length(); i++) {
            JSONObject item = history.optJSONObject(i);
            if (item == null) continue;
            boolean user = "user".equals(item.optString("role"));

            LinearLayout row = new LinearLayout(this);
            row.setGravity(user ? Gravity.RIGHT : Gravity.LEFT);

            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(14), dp(10), dp(14), dp(12));
            card.setBackground(shape(user ? surface : soft, 18));

            TextView author = text(user ? "Ты" : "Nial Ai", 11, muted);
            TextView body = text(item.optString("content"), 15, ink);
            body.setTextIsSelectable(true);
            body.setMaxWidth(dp(300));
            body.setLineSpacing(dp(3), 1);
            card.addView(author);
            card.addView(body);

            LinearLayout.LayoutParams cp =
                new LinearLayout.LayoutParams(-2, -2);
            cp.setMargins(0, 0, 0, dp(14));
            row.addView(card, cp);
            messages.addView(row);
            if (i == history.length() - 1) {
                row.setAlpha(0f);
                row.setTranslationY(dp(8));
                row.animate().alpha(1f).translationY(0f)
                    .setDuration(240).start();
            }
        }

        send.setEnabled(!busy);
        clear.setEnabled(!busy);
        scroll.post(() -> scroll.fullScroll(ScrollView.FOCUS_DOWN));
    }

    private void persist() {
        SharedPreferences.Editor editor = prefs.edit();
        editor.putString("memory", memory);
        editor.putInt("active", active);
        for (int i = 0; i < 3; i++) {
            editor.putString(ids[i], chats[i].toString());
            editor.putString("draft_" + ids[i], drafts[i]);
        }
        editor.apply();
    }

    private android.animation.ValueAnimator waitingAnimation;

    private void updateWaitingMotion() {
        if (status == null) return;

        if (busy) {
            if (waitingAnimation != null && waitingAnimation.isRunning()) return;

            waitingAnimation =
                android.animation.ValueAnimator.ofFloat(.4f, 1f);
            waitingAnimation.setDuration(750);
            waitingAnimation.setRepeatCount(
                android.animation.ValueAnimator.INFINITE);
            waitingAnimation.setRepeatMode(
                android.animation.ValueAnimator.REVERSE);
            waitingAnimation.addUpdateListener(animation ->
                status.setAlpha((Float) animation.getAnimatedValue()));
            waitingAnimation.start();
        } else {
            if (waitingAnimation != null) {
                waitingAnimation.cancel();
                waitingAnimation = null;
            }
            status.setAlpha(1f);
        }
    }

    @Override
    protected void onDestroy() {
        if (waitingAnimation != null) waitingAnimation.cancel();
        super.onDestroy();
    }
    private void editMemory() {
        EditText field = new EditText(this);
        field.setText(memory);
        field.setMinLines(5);
        field.setGravity(Gravity.TOP);
        field.setFilters(new InputFilter[]{new InputFilter.LengthFilter(2500)});

        dialogBuilder()
            .setTitle("Общая память")
            .setMessage("Заметки передаются серверу вместе с сообщением. "
                + "Не сохраняй здесь ключи и пароли.")
            .setView(field)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Сохранить", (dialog, which) -> {
                memory = field.getText().toString().trim();
                persist();
            })
            .show();
    }

    private void clearChat() {
        if (busy) return;
        final int index = active;
        dialogBuilder()
            .setTitle("Удалить диалог?")
            .setMessage("Общая память и другие диалоги останутся.")
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Удалить", (dialog, which) -> {
                chats[index] = new JSONArray();
                drafts[index] = "";
                persist();
                render();
            })
            .show();
    }

    private JSONObject message(String role, String content) throws Exception {
        return new JSONObject().put("role", role).put("content", content);
    }

    private void sendMessage() {
        sendGuestMessage();
    }

    private void sendGuestMessage() {
        if (busy) return;

        final String value = input.getText().toString().trim();
        if (value.isEmpty()) return;

        final int index = active;
        final String memorySnapshot = memory;
        final JSONArray outgoing = new JSONArray();

        try {
            JSONArray history = chats[index];
            for (int i = Math.max(0, history.length() - 24);
                    i < history.length(); i++) {
                JSONObject item = history.getJSONObject(i);
                String content = item.getString("content");
                outgoing.put(message(
                    item.getString("role"),
                    content.substring(0, Math.min(2500, content.length()))));
            }
            outgoing.put(message("user", value));
        } catch (Exception e) {
            status.setText("Не удалось прочитать историю.");
            return;
        }

        // Keep the draft until a successful server response.
        drafts[index] = value;
        persist();

        busy = true;
        input.setEnabled(false);
        send.setEnabled(false);
        clear.setEnabled(false);
        for (Button tab : tabs) tab.setEnabled(false);

        status.setText("Подключаемся к Nial…");
        updateWaitingMotion();

        new Thread(() -> {
            String answer = null;
            String failure = null;
            HttpsURLConnection connection = null;

            try {
                com.google.firebase.auth.FirebaseAuth auth =
                    com.google.firebase.auth.FirebaseAuth.getInstance();

                com.google.firebase.auth.FirebaseUser user =
                    auth.getCurrentUser();

                if (user == null) {
                    com.google.firebase.auth.AuthResult signedIn =
                        com.google.android.gms.tasks.Tasks.await(
                            auth.signInAnonymously(),
                            45, java.util.concurrent.TimeUnit.SECONDS);

                    user = signedIn.getUser();
                }

                if (user == null) {
                    throw new IOException(
                        "Не удалось создать гостевую сессию Firebase.");
                }

                com.google.firebase.auth.GetTokenResult tokenResult =
                    com.google.android.gms.tasks.Tasks.await(
                        user.getIdToken(false),
                        45, java.util.concurrent.TimeUnit.SECONDS);

                String token = tokenResult.getToken();

                if (token == null || token.isEmpty()) {
                    throw new IOException(
                        "Firebase не вернул токен гостевой сессии.");
                }

                runOnUiThread(() -> {
                    if (!isDestroyed()) status.setText("Nial думает…");
                });

                JSONObject payload = new JSONObject()
                    .put("messages", outgoing)
                    .put("agent", ids[index])
                    .put("name", "Nial")
                    .put("memory", memorySnapshot)
                    .put("task", "chat");

                byte[] bytes = payload.toString()
                    .getBytes(StandardCharsets.UTF_8);

                connection = (HttpsURLConnection)
                    new URL(BASE + "/chat").openConnection();

                connection.setInstanceFollowRedirects(false);
                connection.setConnectTimeout(30000);
                connection.setReadTimeout(120000);
                connection.setRequestMethod("POST");
                connection.setDoOutput(true);
                connection.setRequestProperty(
                    "Content-Type", "application/json; charset=utf-8");
                connection.setRequestProperty("Accept", "application/json");
                connection.setRequestProperty("Authorization", "Bearer " + token);
                connection.setFixedLengthStreamingMode(bytes.length);

                try (OutputStream output = connection.getOutputStream()) {
                    output.write(bytes);
                }

                int code = connection.getResponseCode();

                String raw = readResponse(
                    code >= 200 && code < 300
                        ? connection.getInputStream()
                        : connection.getErrorStream());

                if (code == 401) {
                    throw new IOException(
                        "Сервер отклонил гостевой запрос. "
                        + "Возможно, серверное обновление ещё не опубликовано. "
                        + "Вводить пароль не нужно.");
                }

                if (code == 403) {
                    throw new IOException(
                        "Сервер запретил мобильный запрос. "
                        + "Нужно проверить опубликованную серверную версию.");
                }

                JSONObject data;
                try {
                    data = new JSONObject(raw);
                } catch (Exception e) {
                    throw new IOException(
                        "Сервер вернул неожиданный формат. HTTP " + code);
                }

                if (code < 200 || code >= 300) {
                    throw new IOException(data.optString(
                        "error", "Ошибка сервера HTTP " + code));
                }

                answer = data.optString("text", "");
                if (answer.trim().isEmpty()) {
                    throw new IOException("Сервер вернул пустой ответ.");
                }
            } catch (Exception e) {
                Throwable cause = e;
                while (cause instanceof java.util.concurrent.ExecutionException
                        && cause.getCause() != null) {
                    cause = cause.getCause();
                }

                if (cause instanceof java.util.concurrent.TimeoutException) {
                    failure = "Не удалось подключиться вовремя. "
                        + "Проверь интернет и попробуй позже.";
                } else {
                    failure = cause.getMessage() == null
                        ? "Ошибка подключения." : cause.getMessage();
                }
            } finally {
                if (connection != null) connection.disconnect();
            }

            final String result = answer;
            final String error = failure;

            runOnUiThread(() -> {
                if (isDestroyed()) return;

                busy = false;
                input.setEnabled(true);
                for (Button tab : tabs) tab.setEnabled(true);
                updateWaitingMotion();

                if (error == null) {
                    try {
                        chats[index].put(message("user", value));
                        chats[index].put(message("assistant", result));
                    } catch (Exception ignored) {}

                    drafts[index] = "";
                    status.setText("");
                } else {
                    drafts[index] = value;
                    status.setText(error);
                }

                persist();
                render();
            });
        }).start();
    }
    private String readResponse(InputStream stream) throws IOException {
        if (stream == null) return "";
        try (InputStream in = stream;
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int total = 0;
            int count;
            while ((count = in.read(buffer)) != -1) {
                total += count;
                if (total > 1024 * 1024) {
                    throw new IOException("Ответ сервера слишком большой.");
                }
                output.write(buffer, 0, count);
            }
            return output.toString("UTF-8");
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (input != null && !busy) {
            drafts[active] = input.getText().toString();
            persist();
        }
    }
}