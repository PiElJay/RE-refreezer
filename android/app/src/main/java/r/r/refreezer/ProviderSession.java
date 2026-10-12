package r.r.refreezer;
import java.util.Map;
import java.util.Objects;

/** One validated session shared by catalog and media. Never log its fields. */
final class ProviderSession {
    final String userId, sid, apiToken, licenseToken;
    private ProviderSession(String userId, String sid, String apiToken, String licenseToken) {
        this.userId = userId; this.sid = sid; this.apiToken = apiToken; this.licenseToken = licenseToken;
    }
    static ProviderSession fromBridge(Map<?, ?> data, String expectedArl) {
        if (data == null || expectedArl == null || expectedArl.isEmpty() || !Objects.equals(expectedArl, data.get("arl"))) return null;
        String id = text(data.get("userId")), sid = text(data.get("sid")), token = text(data.get("token"));
        if (id == null || !id.matches("[1-9][0-9]{0,19}") || sid == null || token == null) return null;
        if (sid.indexOf(';') >= 0 || sid.indexOf('\r') >= 0 || sid.indexOf('\n') >= 0) return null;
        return new ProviderSession(id, sid, token, text(data.get("licenseToken")));
    }
    private static String text(Object value) {
        if (!(value instanceof String)) return null;
        String text = (String)value;
        return text.isEmpty() || text.equals("null") ? null : text;
    }
}
