package app.secretskeeper.sftpcheck;

import android.app.Instrumentation;
import android.os.Bundle;
import java.lang.reflect.InvocationTargetException;
import org.json.JSONObject;

/** Tests the installed, shrunk release. No vault access, authentication or file operations. */
public class SftpHandshakeInstrumentation extends Instrumentation {
    private Bundle options;
    @Override public void onCreate(Bundle arguments) { options = arguments; start(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        String outcome = "FAIL: host verification was not reached";
        try {
            JSONObject config = new JSONObject().put("type", "SFTP")
                .put("host", options.getString("host")).put("port", Integer.parseInt(options.getString("port")))
                .put("username", "synthetic-release-handshake-check").put("fingerprint", "");
            ClassLoader loader = getTargetContext().getClassLoader();
            Class<?> provider = loader.loadClass("__PROVIDER__");
            java.lang.reflect.Constructor<?> constructor = provider.getDeclaredConstructor(JSONObject.class);
            constructor.setAccessible(true);
            Object connection = constructor.newInstance(config);
            if (connection instanceof AutoCloseable) ((AutoCloseable) connection).close();
        } catch (Throwable error) {
            Throwable failure = error instanceof InvocationTargetException ? error.getCause() : error;
            if (failure != null && failure.getClass().getName().equals("__CHALLENGE__")) {
                outcome = "PASS: SFTP_HOST_TRUST_REACHED before authentication";
            } else if (failure != null && failure.getClass().getName().equals("__FAILURE__")) {
                // This application exception contains only fixed, sanitized guidance.
                outcome = "FAIL: " + failure.getMessage();
            } else {
                outcome = "FAIL: unexpected exception type " + (failure == null ? "none" : failure.getClass().getName());
            }
        }
        result.putString("stream", outcome + "\n");
        finish(outcome.startsWith("PASS:") ? 0 : 1, result);
    }
}
