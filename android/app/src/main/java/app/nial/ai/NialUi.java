package app.nial.ai;

import android.animation.ValueAnimator;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;

final class NialUi {
    static int accent = Color.rgb(106,104,223);
    static int surface = Color.WHITE;
    static int ink = Color.rgb(46,44,45);
    static int muted = Color.GRAY;

    static boolean motion() { return ValueAnimator.areAnimatorsEnabled(); }
    static void press(View view) {
        view.setOnTouchListener((v, event) -> {
            if (!motion() || !v.isEnabled()) return false;
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_DOWN) {
                v.animate().scaleX(.95f).scaleY(.95f).setDuration(100).start();
            } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                v.animate().scaleX(1f).scaleY(1f).setDuration(170).start();
            }
            return false;
        });
    }

    static void icon(Button button, String kind, int fill, int foreground) {
        button.setText("");
        button.setPadding(0,0,0,0);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setMinHeight(0);
        button.setMinimumHeight(0);
        button.setStateListAnimator(null);
        button.setBackground(new Symbol(kind, fill, foreground));
        press(button);
    }

    static void styleVoice(Button button, String state) {
        boolean active = !"Голос".equals(state);
        icon(button, active ? "mic-active" : "mic", accent, Color.WHITE);
        button.setContentDescription(active ? state + ". Нажми, чтобы остановить" : "Голосовой ввод");
        button.setStateDescription(active ? state : "Выключен");
        if (active && motion()) {
            button.setAlpha(.6f);
            button.animate().alpha(1f).setDuration(220).start();
        } else { button.setAlpha(1f); }
    }

    private static final class Symbol extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final String kind;
        private final int fill, foreground;
        private int opacity = 255;
        Symbol(String kind, int fill, int foreground) {
            this.kind = kind; this.fill = fill; this.foreground = foreground;
        }
        @Override public void draw(Canvas c) {
            float w = getBounds().width(), h = getBounds().height();
            if (w <= 0 || h <= 0) return;
            c.save();
            c.translate(getBounds().left, getBounds().top);
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(fill);
            paint.setAlpha(opacity);
            float r = Math.min(w,h) * .34f;
            c.drawRoundRect(new RectF(0,0,w,h), r,r,paint);
            float unit = Math.min(w,h) / 48f;
            c.translate((w-24*unit)/2f, (h-24*unit)/2f);
            c.scale(unit,unit);
            paint.setColor(foreground);
            paint.setAlpha(opacity);
            paint.setStrokeWidth(1.8f);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeJoin(Paint.Join.ROUND);
            paint.setStyle(Paint.Style.STROKE);
            if (kind.startsWith("mic")) {
                c.drawRoundRect(new RectF(9,3,15,14),3,3,paint);
                c.drawArc(new RectF(6,7,18,18),0,180,false,paint);
                c.drawLine(12,18,12,21,paint);
                c.drawLine(9,21,15,21,paint);
                if (kind.equals("mic-active")) {
                    c.drawLine(3,8,3,13,paint);
                    c.drawLine(21,8,21,13,paint);
                }
            } else if (kind.equals("send")) {
                c.drawLine(12,19,12,5,paint);
                c.drawLine(6,11,12,5,paint);
                c.drawLine(12,5,18,11,paint);
            } else if (kind.equals("theme")) {
                c.drawCircle(12,12,7,paint);
                paint.setStyle(Paint.Style.FILL);
                c.drawArc(new RectF(5,5,19,19),90,180,true,paint);
            } else if (kind.equals("history")) {
                c.drawArc(new RectF(4,4,20,20),-65,290,false,paint);
                c.drawLine(3,4,3,9,paint);
                c.drawLine(3,9,8,9,paint);
                c.drawLine(12,7,12,12,paint);
                c.drawLine(12,12,16,14,paint);
            }
            c.restore();
        }
        @Override public void setAlpha(int alpha) { opacity = alpha; invalidateSelf(); }
        @Override public void setColorFilter(ColorFilter filter) { paint.setColorFilter(filter); }
        @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
    }
}