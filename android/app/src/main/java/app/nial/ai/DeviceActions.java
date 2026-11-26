package app.nial.ai;

import android.app.SearchManager;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.AlarmClock;
import android.provider.CalendarContract;
import android.provider.MediaStore;
import android.provider.Settings;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class DeviceActions {
    private DeviceActions() {}

    private static boolean torchOn = false;
    private static String torchId = null;
    private static boolean callbackRegistered = false;

    private static final CameraManager.TorchCallback CALLBACK = new CameraManager.TorchCallback() {
        @Override
        public void onTorchModeChanged(String cameraId, boolean enabled) {
            if (cameraId != null && cameraId.equals(torchId)) torchOn = enabled;
        }
    };

    public static final class Result {
        public final String reply;
        Result(String reply) { this.reply = reply; }
    }

    private static final String[][] ALIASES = {
        {"телеграм", "telegram"}, {"ватсап", "whatsapp"}, {"вацап", "whatsapp"},
        {"ютуб", "youtube"}, {"карты", "maps"}, {"хром", "chrome"}, {"браузер", "chrome"},
        {"галерея", "gallery"}, {"галерею", "gallery"}, {"калькулятор", "calculator"},
        {"часы", "clock"}, {"контакты", "contacts"}, {"почта", "gmail"}, {"почту", "gmail"},
        {"музыка", "music"}, {"музыку", "music"}, {"плей маркет", "play store"},
        {"инстаграм", "instagram"}, {"вконтакте", "vk"}, {"тикток", "tiktok"},
        {"диск", "drive"}, {"файлы", "files"}, {"заметки", "notes"}, {"календарь", "calendar"},
        {"сообщения", "messages"}, {"телефон", "phone"}
    };

    public static boolean isTorchOn() { return torchOn; }

    private static String findTorchId(CameraManager m) throws Exception {
        String any = null;
        for (String id : m.getCameraIdList()) {
            CameraCharacteristics ch = m.getCameraCharacteristics(id);
            Boolean flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
            if (!Boolean.TRUE.equals(flash)) continue;
            Integer facing = ch.get(CameraCharacteristics.LENS_FACING);
            if (facing != null && facing.intValue() == CameraCharacteristics.LENS_FACING_BACK) return id;
            if (any == null) any = id;
        }
        return any;
    }

    public static String torch(Context c, boolean on) {
        try {
            CameraManager m = (CameraManager) c.getApplicationContext()
                    .getSystemService(Context.CAMERA_SERVICE);
            if (!callbackRegistered) {
                m.registerTorchCallback(CALLBACK, new Handler(Looper.getMainLooper()));
                callbackRegistered = true;
            }
            if (torchId == null) torchId = findTorchId(m);
            if (torchId == null) return "На этом устройстве нет вспышки.";
            m.setTorchMode(torchId, on);
            torchOn = on;
            return null;
        } catch (Exception e) {
            torchId = null;
            String why = e.getMessage() == null ? "" : ": " + e.getMessage();
            return "Не удалось управлять фонариком (" + e.getClass().getSimpleName() + why + ").";
        }
    }

    private static String start(Context c, Intent i, String missing) {
        try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
            return null;
        } catch (ActivityNotFoundException e) {
            return missing;
        } catch (SecurityException e) {
            return "Системе не хватило разрешения для этого действия.";
        }
    }

    public static String dial(Context c, String number) {
        Intent i = new Intent(Intent.ACTION_DIAL);
        if (number != null && !number.isEmpty()) i.setData(Uri.fromParts("tel", number, null));
        return start(c, i, "На устройстве нет приложения для звонков.");
    }

    public static String alarm(Context c, int hour, int minute) {
        Intent i = new Intent(AlarmClock.ACTION_SET_ALARM)
                .putExtra(AlarmClock.EXTRA_HOUR, hour)
                .putExtra(AlarmClock.EXTRA_MINUTES, minute)
                .putExtra(AlarmClock.EXTRA_MESSAGE, "Nial")
                .putExtra(AlarmClock.EXTRA_SKIP_UI, false);
        return start(c, i, "На устройстве нет приложения «Часы».");
    }

    public static String timer(Context c, int seconds) {
        Intent i = new Intent(AlarmClock.ACTION_SET_TIMER)
                .putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                .putExtra(AlarmClock.EXTRA_MESSAGE, "Nial")
                .putExtra(AlarmClock.EXTRA_SKIP_UI, false);
        return start(c, i, "На устройстве нет приложения «Часы».");
    }

    public static String email(Context c, String body) {
        Intent i = new Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"));
        i.putExtra(Intent.EXTRA_TEXT, body == null ? "" : body);
        return start(c, i, "На устройстве нет почтового приложения.");
    }

    public static String share(Context c, String text) {
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, text == null ? "" : text);
        return start(c, Intent.createChooser(send, "Отправить через"), "Нет приложений для отправки.");
    }

    public static String newEvent(Context c, String title) {
        Intent i = new Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI);
        i.putExtra(CalendarContract.Events.TITLE, title == null ? "" : title);
        return start(c, i, "На устройстве нет приложения календаря.");
    }

    public static String openCalendar(Context c) {
        Uri uri = CalendarContract.CONTENT_URI.buildUpon().appendPath("time")
                .appendPath(Long.toString(System.currentTimeMillis())).build();
        return start(c, new Intent(Intent.ACTION_VIEW, uri), "На устройстве нет приложения календаря.");
    }

    private static String afterColon(String raw) {
        int k = raw.indexOf(':');
        return k >= 0 && k + 1 < raw.length() ? raw.substring(k + 1).trim() : "";
    }

    private static boolean has(String t, String re) {
        return Pattern.compile(re).matcher(t).find();
    }

    private static String grab(String t, String re) {
        Matcher m = Pattern.compile(re).matcher(t);
        if (!m.find()) return "";
        return m.group(1).replaceAll("[.!?…]+$", "").trim();
    }

    private static final class AppHit {
        final Intent intent; final String label;
        AppHit(Intent i, String l) { intent = i; label = l; }
    }

    private static AppHit findApp(Context c, String raw) {
        String q = raw.toLowerCase(Locale.ROOT).trim();
        if (q.length() < 3 || q.length() > 40) return null;
        ArrayList<String> cands = new ArrayList<>();
        cands.add(q);
        for (String[] a : ALIASES) if (q.contains(a[0])) cands.add(a[1]);
        PackageManager pm = c.getPackageManager();
        Intent main = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> list = pm.queryIntentActivities(main, 0);
        String bestPkg = null, bestLabel = null;
        int bestLen = Integer.MAX_VALUE;
        for (ResolveInfo ri : list) {
            String label = String.valueOf(ri.loadLabel(pm));
            String low = label.toLowerCase(Locale.ROOT);
            String pkg = ri.activityInfo.packageName.toLowerCase(Locale.ROOT);
            for (String cand : cands) {
                if (low.contains(cand) || pkg.contains(cand)) {
                    if (low.length() < bestLen) {
                        bestLen = low.length();
                        bestPkg = ri.activityInfo.packageName;
                        bestLabel = label;
                    }
                    break;
                }
            }
        }
        if (bestPkg == null) return null;
        Intent launch = pm.getLaunchIntentForPackage(bestPkg);
        return launch == null ? null : new AppHit(launch, bestLabel);
    }

    /** Возвращает null, если фраза не похожа на команду телефона. */
    public static Result handle(Context c, String raw) {
        if (raw == null) return null;
        String t = raw.toLowerCase(Locale.ROOT).trim();

        if (has(t, "ф[оа]нар|вспышк")
                && has(t, "включ|выключ|зажг|погас|отключ|вруб|выруб|потуши|убери|свет")) {
            boolean off = has(t, "выключ|погас|отключ|убери|выруб|потуши");
            String err = torch(c, !off);
            if (err != null) return new Result(err);
            return new Result(off ? "Фонарик выключен."
                    : "Фонарик включён. Чтобы выключить, напиши «выключи фонарик».");
        }

        if (has(t, "видео") && has(t, "сними|запиши|включи|сделай|открой")) {
            String err = start(c, new Intent(MediaStore.INTENT_ACTION_VIDEO_CAMERA), "Нет приложения камеры.");
            return new Result(err != null ? err : "Открыл видеокамеру. Запись начнёшь ты кнопкой записи.");
        }

        if (has(t, "камер|фото|снимок|снимк|селфи|сфотограф")
                && has(t, "включ|открой|запусти|сделай|сними|сфотограф|вруб|селфи")) {
            boolean shoot = has(t, "сним|фото|селфи|сфотограф");
            String err = start(c, new Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA), "Нет приложения камеры.");
            if (err != null) return new Result(err);
            return new Result(shoot
                    ? "Камера открыта. Нажми на затвор, и снимок сохранится в галерее. Нажимать за тебя в другом приложении Android пока не позволяет: для этого нужен отдельный режим «Универсальный доступ»."
                    : "Камера открыта.");
        }

        if (has(t, "таймер") && has(t, "постав|запуст|завед|установ|включ|созда|на \\d")) {
            Matcher m = Pattern.compile("(\\d+)\\s*(мин|сек|час)").matcher(t);
            if (!m.find()) return new Result("Скажи, на сколько: например, «таймер на 10 минут».");
            int n = Integer.parseInt(m.group(1));
            String u = m.group(2);
            int sec = u.equals("час") ? n * 3600 : u.equals("мин") ? n * 60 : n;
            String err = timer(c, sec);
            return new Result(err != null ? err : "Таймер готов. Подтверди запуск в приложении «Часы».");
        }

        if (has(t, "будильник|разбуди") && has(t, "постав|завед|установ|созда|разбуди|включ")) {
            Matcher m = Pattern.compile("(\\d{1,2})[:.](\\d{2})").matcher(t);
            int h = -1, min = 0;
            if (m.find()) {
                h = Integer.parseInt(m.group(1));
                min = Integer.parseInt(m.group(2));
            } else {
                Matcher m2 = Pattern.compile("(?:^|\\s)в\\s*(\\d{1,2})(?!\\d)").matcher(t);
                if (m2.find()) h = Integer.parseInt(m2.group(1));
            }
            if (h < 0 || h > 23 || min > 59) return new Result("Скажи время, например: «поставь будильник на 7:30».");
            String err = alarm(c, h, min);
            return new Result(err != null ? err : String.format(Locale.ROOT,
                    "Будильник на %02d:%02d готов. Подтверди его в приложении «Часы».", h, min));
        }

        if (has(t, "позвони|набери|вызови|сделай звонок|совершить звонок")) {
            Matcher m = Pattern.compile("\\+?\\d[\\d\\s\\-()]{5,}\\d").matcher(raw);
            String number = m.find() ? m.group().replaceAll("[^+\\d]", "") : "";
            String err = dial(c, number);
            if (err != null) return new Result(err);
            return new Result(number.isEmpty()
                    ? "Открыл набор номера. Назови номер цифрами, и я подставлю его. Звонок начнёшь ты."
                    : "Открыл набор номера с " + number + ". Звонок начнёшь ты.");
        }

        if (has(t, "телеграм|telegram") && has(t, "напиши|отправь|пошли|скинь|подготов|созда")) {
            String err = share(c, afterColon(raw));
            return new Result(err != null ? err : "Выбери Telegram в списке. Отправишь ты.");
        }

        if (has(t, "письм|почт|email|e-mail|gmail") && has(t, "напиши|составь|отправь|создай|подготов|черновик")) {
            String err = email(c, afterColon(raw));
            return new Result(err != null ? err : "Открыл черновик письма. Отправишь ты.");
        }

        if (has(t, "календар|встреч") && has(t, "открой|покажи|созда|добав|запиш|постав")) {
            boolean create = has(t, "созда|добав|запиш|постав");
            String err = create ? newEvent(c, afterColon(raw)) : openCalendar(c);
            return new Result(err != null ? err : (create ? "Открыл создание события. Сохранишь ты." : "Открыл календарь."));
        }

        String q = grab(t, "(?:найди в интернете|найди в гугле|поищи в интернете|поищи в гугле|загугли)\\s+(.+)");
        if (!q.isEmpty()) {
            Intent i = new Intent(Intent.ACTION_WEB_SEARCH).putExtra(SearchManager.QUERY, q);
            String err = start(c, i, "Нет приложения для поиска.");
            return new Result(err != null ? err : "Ищу: «" + q + "».");
        }

        String dest = grab(t, "(?:проложи маршрут до|маршрут до|как доехать до|навигация до|поехали в)\\s+(.+)");
        if (!dest.isEmpty()) {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=" + Uri.encode(dest)));
            String err = start(c, i, "Нет приложения карт.");
            return new Result(err != null ? err : "Открыл карты: «" + dest + "». Маршрут запустишь ты.");
        }

        if (has(t, "wi-?fi|вай-?фай|вайфай|интернет|bluetooth|блютуз|блютус|громкост|настройк")
                && has(t, "включ|выключ|открой|настро|покажи|убавь|прибав")) {
            Intent i;
            String what;
            if (has(t, "bluetooth|блютуз|блютус")) {
                i = new Intent(Settings.ACTION_BLUETOOTH_SETTINGS); what = "Bluetooth";
            } else if (has(t, "громкост")) {
                i = Build.VERSION.SDK_INT >= 29 ? new Intent(Settings.Panel.ACTION_VOLUME)
                        : new Intent(Settings.ACTION_SOUND_SETTINGS);
                what = "громкости";
            } else if (has(t, "wi-?fi|вай-?фай|вайфай|интернет")) {
                i = Build.VERSION.SDK_INT >= 29 ? new Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
                        : new Intent(Settings.ACTION_WIFI_SETTINGS);
                what = "Wi‑Fi и интернета";
            } else {
                i = new Intent(Settings.ACTION_SETTINGS); what = "настроек";
            }
            String err = start(c, i, "Не удалось открыть настройки.");
            return new Result(err != null ? err : "Открыл панель " + what + ". Android не даёт приложениям переключать это напрямую: нажми нужный переключатель.");
        }

        String app = grab(t, "(?:открой|запусти|включи|зайди в|войди в)\\s+(?:приложение\\s+)?(.+)");
        if (!app.isEmpty()) {
            AppHit hit = findApp(c, app);
            if (hit != null) {
                String err = start(c, hit.intent, "Не удалось открыть приложение.");
                return new Result(err != null ? err : "Открываю «" + hit.label + "».");
            }
        }
        return null;
    }
}