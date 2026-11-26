package app.nial.ai;

import android.content.Context;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONObject;

public final class AgentActions {
    private AgentActions() {}

    private static final Pattern TAG =
        Pattern.compile("\\[\\[ACTION\\s*(\\{.*?\\})\\s*\\]\\]", Pattern.DOTALL);

    /** Убирает служебные теги из текста ответа. */
    public static String stripActions(String text) {
        if (text == null) return null;
        return TAG.matcher(text).replaceAll("").replaceAll("[ \\t]+\\n", "\n").trim();
    }

    /** Выполняет действия из ответа. Возвращает текст предупреждений или пустую строку. */
    public static String execute(Context c, String text) {
        if (text == null) return "";
        Matcher m = TAG.matcher(text);
        int launched = 0;
        StringBuilder notes = new StringBuilder();
        while (m.find()) {
            try {
                JSONObject o = new JSONObject(m.group(1));
                String phrase = toPhrase(o);
                if (phrase == null) continue;
                boolean torch = "torch".equals(o.optString("type"));
                if (!torch && launched >= 1) {
                    if (notes.length() > 0) notes.append("\n");
                    notes.append("Android открывает одно приложение за раз. Запроси остальное отдельно.");
                    break;
                }
                DeviceActions.Result r = DeviceActions.handle(c, phrase);
                if (!torch) launched++;
                if (r != null) {
                    String s = r.reply;
                    if (s.startsWith("Не ") || s.startsWith("На устройстве нет")
                            || s.startsWith("Системе не") || s.startsWith("Нет приложений")) {
                        if (notes.length() > 0) notes.append("\n");
                        notes.append(s);
                    }
                }
            } catch (Exception ignored) {}
        }
        return notes.toString();
    }

    private static String toPhrase(JSONObject o) {
        String type = o.optString("type", "").toLowerCase(Locale.ROOT);
        switch (type) {
            case "torch":
                return o.optBoolean("on", true) ? "включи фонарик" : "выключи фонарик";
            case "camera": {
                String mode = o.optString("mode", "open");
                if ("video".equals(mode)) return "сними видео";
                if ("selfie".equals(mode)) return "сделай селфи";
                if ("photo".equals(mode)) return "сделай снимок";
                return "включи камеру";
            }
            case "open_app": {
                String n = o.optString("name", "").trim();
                return n.isEmpty() ? null : "открой " + n;
            }
            case "call": {
                String n = o.optString("number", "").trim();
                return n.isEmpty() ? "позвони" : "позвони " + n;
            }
            case "alarm":
                return String.format(Locale.ROOT, "поставь будильник на %d:%02d",
                    o.optInt("hour", 7), o.optInt("minute", 0));
            case "timer": {
                int s = Math.max(1, o.optInt("seconds", 60));
                return s >= 60 ? "поставь таймер на " + (s / 60) + " минут"
                               : "поставь таймер на " + s + " сек";
            }
            case "email":
                return "напиши письмо: " + o.optString("body", "");
            case "share":
                return "напиши в телеграм: " + o.optString("text", "");
            case "event":
                return "создай событие в календаре: " + o.optString("title", "");
            case "calendar":
                return "открой календарь";
            case "search": {
                String q = o.optString("query", "").trim();
                return q.isEmpty() ? null : "найди в интернете " + q;
            }
            case "route": {
                String d = o.optString("dest", "").trim();
                return d.isEmpty() ? null : "проложи маршрут до " + d;
            }
            case "settings": {
                String p = o.optString("panel", "general");
                if ("wifi".equals(p)) return "открой настройки wifi";
                if ("bluetooth".equals(p)) return "открой настройки bluetooth";
                if ("volume".equals(p)) return "открой настройки громкости";
                return "открой настройки";
            }
            default:
                return null;
        }
    }
}