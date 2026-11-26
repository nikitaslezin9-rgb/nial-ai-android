package app.nial.ai;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.Toast;
import java.util.ArrayList;
import java.util.Locale;
import java.util.function.BooleanSupplier;

final class NialVoice implements RecognitionListener {
    private final Activity activity;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private SpeechRecognizer recognizer;
    private TextToSpeech tts;
    private Button button;
    private EditText input;
    private Runnable send;
    private BooleanSupplier busy;
    private boolean enabled, ready, destroyed, awaiting;
    private String state = "Голос";
    private long generation;

    NialVoice(Activity activity) { this.activity = activity; }

    void bind(LinearLayout row, EditText input, Runnable send, BooleanSupplier busy) {
        this.input = input;
        this.send = send;
        this.busy = busy;
        button = new Button(activity);
        button.setTextSize(11);
        button.setAllCaps(false);
        button.setMinWidth(0);
        NialUi.styleVoice(button, state);
        button.setContentDescription("Включить или остановить голосовой диалог");
        int width = (int)(48 * activity.getResources().getDisplayMetrics().density + .5f);
        LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(width, width);
        vp.setMarginStart((int)(8 * activity.getResources().getDisplayMetrics().density + .5f));
        row.addView(button, vp);
        button.setOnClickListener(v -> toggle());
    }

    private void label(String text) {
        state = text;
        if (button != null) NialUi.styleVoice(button, text);
    }

    private void notice(String text) {
        Toast.makeText(activity, text, Toast.LENGTH_LONG).show();
    }

    private void toggle() {
        if (destroyed) return;
        if (enabled) { stop(); return; }
        if (busy.getAsBoolean()) { notice("Дождись ответа Nial."); return; }
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 7801);
            notice("Разреши микрофон, затем снова нажми «Голос».");
            return;
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            notice("На устройстве нет доступной службы распознавания речи.");
            return;
        }
        if (input != null && input.getText().toString().trim().length() > 0) {
            notice("Сначала отправь или убери черновик: голос не будет его перезаписывать.");
            return;
        }
        // NIAL_VOICE_TEXT_ONLY_V1
        enabled = true;
        generation++;
        listen();
    }
    private void listen() {
        if (!enabled || destroyed) return;
        if (busy.getAsBoolean()) { fail("Чат занят. Включи голос после ответа."); return; }
        try {
            releaseRecognizer();
            recognizer = SpeechRecognizer.createSpeechRecognizer(activity);
            recognizer.setRecognitionListener(this);
            Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU");
            intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false);
            label("Слушаю…");
            recognizer.startListening(intent);
        } catch (Exception e) { fail("Не удалось включить микрофон."); }
    }

    void onReply(String result, String error) {
        if (!enabled || !awaiting || destroyed) return;
        stop();
    }
    private void releaseRecognizer() {
        if (recognizer != null) {
            SpeechRecognizer old = recognizer;
            recognizer = null;
            try { old.cancel(); } catch (Exception ignored) {}
            try { old.destroy(); } catch (Exception ignored) {}
        }
    }

    void stop() {
        enabled = false;
        awaiting = false;
        generation++;
        handler.removeCallbacksAndMessages(null);
        releaseRecognizer();
        if (tts != null) {
            try { tts.stop(); } catch (Exception ignored) {}
            if (!ready) { tts.shutdown(); tts = null; }
        }
        label("Голос");
    }

    void destroy() {
        stop();
        destroyed = true;
        if (tts != null) { tts.shutdown(); tts = null; }
        button = null;
        input = null;
        send = null;
        busy = null;
    }

    private void fail(String message) { stop(); notice(message); }
    @Override public void onResults(Bundle results) {
        if (!enabled || destroyed) return;
        ArrayList<String> words = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        if (words == null || words.isEmpty() || words.get(0).trim().isEmpty()) {
            fail("Речь не распознана. Нажми «Голос», чтобы попробовать снова."); return;
        }
        if (busy.getAsBoolean()) { fail("Чат уже отправляет сообщение."); return; }
        if (input.getText().toString().trim().length() > 0) {
            fail("В поле появился черновик. Голос остановлен, чтобы сохранить его."); return;
        }
        input.setText(words.get(0).trim());
        awaiting = true;
        label("Думаю…");
        try {
            send.run();
            if (!busy.getAsBoolean()) fail("Сообщение не отправлено. Текст оставлен в поле ввода.");
        } catch (Exception e) { fail("Не удалось отправить сообщение. Текст оставлен в поле ввода."); }
    }
    @Override public void onError(int error) {
        if (!enabled || destroyed || awaiting) return;
        String message;
        switch (error) {
            case SpeechRecognizer.ERROR_NO_MATCH:
            case SpeechRecognizer.ERROR_SPEECH_TIMEOUT:
                message = "Речь не услышана. Нажми «Голос» и попробуй снова."; break;
            case SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS:
                message = "Нужно разрешить доступ к микрофону."; break;
            case SpeechRecognizer.ERROR_NETWORK:
            case SpeechRecognizer.ERROR_NETWORK_TIMEOUT:
                message = "Ошибка сети службы распознавания речи."; break;
            default: message = "Распознавание остановлено. Код: " + error;
        }
        fail(message);
    }
    @Override public void onReadyForSpeech(Bundle params) {}
    @Override public void onBeginningOfSpeech() {}
    @Override public void onRmsChanged(float value) {}
    @Override public void onBufferReceived(byte[] buffer) {}
    @Override public void onEndOfSpeech() { if (enabled && !awaiting) label("Распознаю…"); }
    @Override public void onPartialResults(Bundle results) {}
    @Override public void onEvent(int type, Bundle params) {}
}