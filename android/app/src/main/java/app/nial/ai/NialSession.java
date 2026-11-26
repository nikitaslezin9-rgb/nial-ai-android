package app.nial.ai;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;

public final class NialSession {
    private NialSession() {}

    public interface Callback {
        void onReady(String token);
        void onError(String message);
    }

    public static void getToken(Callback callback) {
        FirebaseAuth auth = FirebaseAuth.getInstance();
        FirebaseUser user = auth.getCurrentUser();

        if (user != null) {
            readToken(user, callback);
            return;
        }

        auth.signInAnonymously().addOnCompleteListener(task -> {
            if (!task.isSuccessful()) {
                callback.onError(errorMessage(task.getException()));
                return;
            }

            FirebaseUser signedIn = auth.getCurrentUser();
            if (signedIn == null) {
                callback.onError("Firebase did not return a user.");
                return;
            }

            readToken(signedIn, callback);
        });
    }

    private static void readToken(
            FirebaseUser user, Callback callback) {
        user.getIdToken(false).addOnCompleteListener(task -> {
            if (!task.isSuccessful()) {
                callback.onError(errorMessage(task.getException()));
                return;
            }

            String token = task.getResult().getToken();
            if (token == null || token.isEmpty()) {
                callback.onError("Firebase returned an empty token.");
                return;
            }

            callback.onReady(token);
        });
    }

    private static String errorMessage(Exception error) {
        if (error == null || error.getMessage() == null) {
            return "Could not start the guest session.";
        }
        return error.getMessage();
    }
}