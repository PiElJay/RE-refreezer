package r.r.refreezer;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Only fixed categories and numeric error codes, never response text or tokens. */
final class MediaResponseSummary {
    static String classify(String contentType, String body) {
        if (body == null || body.trim().isEmpty()) return "EMPTY";
        String value = body.trim();
        if (value.startsWith("{") || value.startsWith("[")) {
            Matcher code = Pattern.compile("\"code\"\\s*:\\s*([0-9]{1,6})(?=\\s*[,}])").matcher(value);
            return code.find() ? "JSON_ERROR_" + code.group(1) : "JSON";
        }
        String type = contentType == null ? "" : contentType.toLowerCase(Locale.ROOT);
        if (type.contains("html") || value.startsWith("<")) {
            String lower = value.toLowerCase(Locale.ROOT);
            return lower.contains("captcha") || lower.contains("challenge") || lower.contains("datadome") ? "HTML_CHALLENGE" : "HTML";
        }
        return "TEXT";
    }
}
