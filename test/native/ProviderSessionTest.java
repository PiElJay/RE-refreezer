package r.r.refreezer;
import java.util.HashMap;
import java.util.Map;

public class ProviderSessionTest {
    static int checks;
    static Map<String,Object> fixture() {
        Map<String,Object> map = new HashMap<>(); map.put("arl", "fixture-account");
        map.put("userId", "42"); map.put("sid", "catalog-session");
        map.put("token", "catalog-form-token"); map.put("licenseToken", "catalog-license"); return map;
    }
    static void reject(Map<?,?> map, String account) {
        if (ProviderSession.fromBridge(map, account) != null) throw new AssertionError("Invalid or mismatched session accepted"); checks++;
    }
    public static void main(String[] args) {
        ProviderSession session = ProviderSession.fromBridge(fixture(), "fixture-account");
        if (session == null || !session.sid.equals("catalog-session") || !session.apiToken.equals("catalog-form-token") || !session.licenseToken.equals("catalog-license")) throw new AssertionError("Catalog credentials changed before media transfer"); checks++;
        reject(fixture(), "different-account"); reject(null, "fixture-account");
        for (String field : new String[]{"userId", "sid", "token", "arl"}) {
            for (Object value : new Object[]{"", "null", 123}) { Map<String,Object> map=fixture(); map.put(field,value); reject(map,"fixture-account"); }
        }
        Map<String,Object> anonymous=fixture(); anonymous.put("userId","0"); reject(anonymous,"fixture-account");
        Map<String,Object> injected=fixture(); injected.put("sid","bad\r\nCookie: test"); reject(injected,"fixture-account");
        Map<String,Object> catalogOnly=fixture(); catalogOnly.remove("licenseToken");
        if (ProviderSession.fromBridge(catalogOnly,"fixture-account").licenseToken != null) throw new AssertionError("Catalog-only account was granted a media license"); checks++;
        System.out.println("Shared session checks passed: " + checks);
    }
}
