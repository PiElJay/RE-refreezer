package r.r.refreezer;
/** Provider fixture: any remote operation during offline playback fails. */
class Deezer {
    String lastErrorCode = "NONE"; int lastHttpStatus = 0; boolean fatalStreamError = false;
    void init(DownloadLog logger, String arl) {}
    boolean authorize() { throw new AssertionError("Offline playback contacted Deezer"); }
    static class QualityInfo {
        boolean encrypted = false; int quality; String trackId;
        QualityInfo(int quality, String id, String token, String md5, String version, DownloadLog logger) {}
        String fallback(Deezer deezer) { throw new AssertionError("Offline playback requested a remote source"); }
    }
}
