package r.r.refreezer;
public final class MediaResponseSummaryTest {
    static int checks;
    static void check(String type, String body, String expected) {
        String result = MediaResponseSummary.classify(type, body);
        if (!expected.equals(result)) throw new AssertionError("Wrong response category: " + result);
        if (!result.matches("[A-Z0-9_]{1,64}")) throw new AssertionError("Unsafe diagnostic");
        checks++;
    }
    public static void main(String[] args) {
        check("application/json", "{\"errors\":[{\"code\":1002,\"message\":\"secret license token\"}]}", "JSON_ERROR_1002");
        check("text/html", "<html>Forbidden</html>", "HTML");
        check("text/html", "<html>Captcha challenge containing cookie=secret</html>", "HTML_CHALLENGE");
        check("application/json", "{\"data\":[]}", "JSON");
        check("application/json", "{\"code\":\"private-token\"}", "JSON");
        check("application/json", "{\"code\":1234567890123}", "JSON");
        check(null, null, "EMPTY"); check("text/plain", "Forbidden token=secret", "TEXT");
        for (int i=0; i<100; i++) check("text/html", "<html>private credential " + i + "</html>", "HTML");
        System.out.println("Safe media-response checks passed: " + checks);
    }
}
