package r.r.refreezer;


import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.net.URL;
import java.util.HashMap;
import java.util.Objects;

import javax.net.ssl.HttpsURLConnection;
import fi.iki.elonen.NanoHTTPD;

public class StreamServer {

    public HashMap<String, StreamInfo> streams = new HashMap<>();

    private WebServer server;
    private final String offlinePath;

    //Shared log & API
    private final DownloadLog logger;
    private final Deezer deezer;
    private boolean authorized = false;
    private volatile boolean ready = false;
    private volatile String serverErrorCode = "NONE";
    HashMap<String, Object> diagnostics() {
        HashMap<String, Object> state = new HashMap<>();
        state.put("ready", ready); state.put("authorized", authorized);
        state.put("errorCode", serverErrorCode.equals("NONE") ? deezer.lastErrorCode : serverErrorCode);
        state.put("httpStatus", deezer.lastHttpStatus);
        state.put("mediaStatus", deezer.mediaHttpStatus);
        state.put("mediaResponse", deezer.mediaResponseType);
        state.put("fatal", deezer.fatalStreamError || !ready);
        return state;
    }

    StreamServer(String arl, String offlinePath) {
        //Initialize shared variables
        logger = new DownloadLog();
        deezer = new Deezer();
        deezer.init(logger, arl);
        this.offlinePath = offlinePath;
    }

    boolean matchesSession(String arl) { return Objects.equals(deezer.arl, arl); }
    HashMap<String, Object> refreshSession() { authorized = deezer.refreshSession(); return diagnostics(); }

    //Create server
    void start() throws IOException {
        try {
            String host = "127.0.0.1";
            int port = 0;
            server = new WebServer(host, port);
            server.start(); ready = true;
        } catch (IOException e) {
            ready = false; serverErrorCode = "SERVER_BIND_FAILED"; throw e;
        }
    }

    int getPort() { return server == null ? 0 : server.getListeningPort(); }

    void stop() {
        ready = false;
        if (server != null)
            server.stop();
    }

    //Information about streamed audio - for showing in UI
    public static class StreamInfo {
        String format;
        long size;
        //"Stream" or "Offline"
        String source;

        StreamInfo(String format, long size, String source) {
            this.format = format;
            this.size = size;
            this.source = source;
        }

        //For passing into UI
        public HashMap<String, Object> toJSON() {
            HashMap<String, Object> out = new HashMap<>();
            out.put("format", format);
            out.put("size", size);
            out.put("source", source);
            return out;
        }

    }

    private class WebServer extends NanoHTTPD {
        public WebServer(String hostname, int port) {
            super(hostname, port);
        }

        @Override
        public Response serve(IHTTPSession session) {
            //Must be only GET
            if (session.getMethod() != Method.GET)
                return newFixedLengthResponse(Response.Status.METHOD_NOT_ALLOWED, MIME_PLAINTEXT, "Only GET request supported!");

            if (session.getUri().equals("/health")) return newFixedLengthResponse(Response.Status.OK, "application/json", "{\"status\":\"ready\"}");
            try {
                String requestedId = session.getParameters().get("id") == null ? null : session.getParameters().get("id").get(0);
                if (requestedId != null && !session.getParameters().containsKey("forceOnline")) {
                    File local = new File(offlinePath, requestedId);
                    if (local.isFile() && local.length() > 0) return offlineStream(session);
                }
                //Parse range header
                String rangeHeader = session.getHeaders().get("range");
                int startBytes = 0;
                boolean isRanged = false;
                int end = -1;
                if (rangeHeader != null && rangeHeader.startsWith("bytes")) {
                    isRanged = true;
                    String[] ranges = rangeHeader.split("=")[1].split("-");
                    startBytes = Integer.parseInt(ranges[0]);
                    if (ranges.length > 1 && !ranges[1].equals(" ")) {
                        end = Integer.parseInt(ranges[1]);
                    }
                }

                //Check query parameters
                if (session.getParameters().keySet().size() < 6) {
                    //Play offline
                    if (session.getParameters().get("id") != null) {
                        return offlineStream(session);
                    }
                    //Missing QP
                    return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, "Invalid / Missing QP");
                }

                //Stream
                return deezerStream(session, startBytes, end, isRanged);
            } catch (Exception e) {
                e.printStackTrace();
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, "An error occurred while serving the request.");
            }
        }

        private Response offlineStream(IHTTPSession session) {
            String trackId = Objects.requireNonNull(session.getParameters().get("id")).get(0);
            File file = new File(offlinePath, trackId); long size = file.length();
            final ByteRange range;
            try { range = ByteRange.parse(session.getHeaders().get("range"), size); }
            catch (IllegalArgumentException e) {
                Response out = newFixedLengthResponse(Response.Status.RANGE_NOT_SATISFIABLE, MIME_PLAINTEXT, "Invalid byte range");
                out.addHeader("Content-Range", "bytes */" + size); return out;
            }
            try {
                final RandomAccessFile input = new RandomAccessFile(file, "r");
                byte[] signature = new byte[4]; input.read(signature);
                boolean flac = new String(signature).equals("fLaC"); input.seek(range.start);
                InputStream bounded = new InputStream() {
                    long remaining = range.length();
                    @Override public int read() throws IOException {
                        if (remaining <= 0) return -1;
                        int value = input.read(); if (value >= 0) remaining--; return value;
                    }
                    @Override public int read(byte[] b, int off, int len) throws IOException {
                        if (len == 0) return 0; if (remaining <= 0) return -1;
                        int count = input.read(b, off, (int)Math.min(len, remaining));
                        if (count > 0) remaining -= count; return count;
                    }
                    @Override public void close() throws IOException { input.close(); }
                };
                Response out = newFixedLengthResponse(range.partial ? Response.Status.PARTIAL_CONTENT : Response.Status.OK,
                    flac ? "audio/flac" : "audio/mpeg", bounded, range.length());
                if (range.partial) out.addHeader("Content-Range", "bytes " + range.start + "-" + range.end + "/" + size);
                out.addHeader("Accept-Ranges", "bytes");
                streams.put(trackId, new StreamInfo(flac ? "FLAC" : "MP3", size, "Offline")); return out;
            } catch (IOException e) {
                serverErrorCode = "LOCAL_FILE_READ_FAILED";
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, serverErrorCode);
            }
        }

        private Response deezerStream(IHTTPSession session, int startBytes, int end, boolean isRanged) {
            // Authorize
            if (!authorized) {
                authorized = deezer.authorize();
                if (!authorized) return newFixedLengthResponse(Response.Status.UNAUTHORIZED, MIME_PLAINTEXT, "GW_NOT_AUTHENTICATED");
            }

            //Get QP into Quality Info
            Deezer.QualityInfo qualityInfo = new Deezer.QualityInfo(
                    Integer.parseInt(Objects.requireNonNull(session.getParameters().get("q")).get(0)),
                    Objects.requireNonNull(session.getParameters().get("streamTrackId")).get(0),
                    Objects.requireNonNull(session.getParameters().get("trackToken")).get(0),
                    Objects.requireNonNull(session.getParameters().get("md5origin")).get(0),
                    Objects.requireNonNull(session.getParameters().get("mv")).get(0),
                    logger
            );
            //Fallback
            String sURL;
            try {
                sURL = qualityInfo.fallback(deezer);
                if (sURL == null)
                    throw new Exception("No more to fallback!");
            } catch (Exception e) {
                if (deezer.lastErrorCode.equals("NONE")) deezer.lastErrorCode = "MEDIA_SOURCE_UNAVAILABLE";
                return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, deezer.lastErrorCode);
            }

            //Calculate Deezer offsets
            int _deezerStart = startBytes;
            if (qualityInfo.encrypted)
                _deezerStart -= startBytes % 2048;
            final int deezerStart = _deezerStart;
            int dropBytes = startBytes % 2048;

            //Start download
            try {
                URL url = new URL(sURL);
                HttpsURLConnection connection = (HttpsURLConnection) url.openConnection();
                //Set headers
                connection.setConnectTimeout(10000);
                connection.setReadTimeout(10000);
                connection.setRequestMethod("GET");
                connection.setRequestProperty("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.130 Safari/537.36");
                connection.setRequestProperty("Accept-Language", "*");
                connection.setRequestProperty("Accept", "*/*");
                connection.setRequestProperty("Range", "bytes=" + Integer.toString(deezerStart) + "-" + ((end == -1) ? "" : Integer.toString(end)));
                connection.connect();
                int status = connection.getResponseCode();
                if (status >= 400) {
                    deezer.lastErrorCode = "CDN_HTTP_" + status; connection.disconnect();
                    return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, deezer.lastErrorCode);
                }
                deezer.lastErrorCode = "NONE"; deezer.fatalStreamError = false; serverErrorCode = "NONE";
                Response outResponse;
                // Encrypted response
                if (qualityInfo.encrypted) {
                    //Get decryption key
                    final byte[] key = DeezerDecryptor.getKey(qualityInfo.trackId);

                    outResponse = newFixedLengthResponse(
                            isRanged ? Response.Status.PARTIAL_CONTENT : Response.Status.OK,
                            (qualityInfo.quality == 9) ? "audio/flac" : "audio/mpeg",
                            new BufferedInputStream(new FilterInputStream(connection.getInputStream()) {

                                int counter = deezerStart / 2048;
                                int drop = dropBytes;

                                //Decryption stream
                                @Override
                                public int read(byte[] b, int off, int len) throws IOException {
                                    //Read 2048b or EOF
                                    byte[] buffer = new byte[2048];
                                    int read = 0;
                                    int totalRead = 0;
                                    while (read != -1 && totalRead != 2048) {
                                        read = in.read(buffer, totalRead, 2048 - totalRead);
                                        if (read != -1)
                                            totalRead += read;
                                    }
                                    if (totalRead == 0)
                                        return -1;

                                    //Not full chunk return unencrypted
                                    if (totalRead != 2048) {
                                        System.arraycopy(buffer, 0, b, off, totalRead);
                                        return totalRead;
                                    }
                                    //Decrypt every 3rd full chunk
                                    if ((counter % 3) == 0) {
                                        buffer = DeezerDecryptor.decryptChunk(key, buffer);
                                    }
                                    //Drop bytes from rounding to 2048
                                    if (drop > 0) {
                                        int output = 2048 - drop;
                                        System.arraycopy(buffer, drop, b, off, output);
                                        drop = 0;
                                        counter++;
                                        return output;
                                    }
                                    //Copy
                                    System.arraycopy(buffer, 0, b, off, 2048);
                                    counter++;
                                    return 2048;
                                }
                            }, 2048),
                            connection.getContentLength() - dropBytes
                    );
                } else {
                    // Decrypted
                    outResponse = newFixedLengthResponse(
                        isRanged ? Response.Status.PARTIAL_CONTENT : Response.Status.OK,
                        (qualityInfo.quality == 9) ? "audio/flac" : "audio/mpeg",
                        connection.getInputStream(),
                        connection.getContentLength()
                    );
                }

                //Ranged header
                if (isRanged) {
                    String range = "bytes " + Integer.toString(startBytes) + "-" + Integer.toString((end == -1) ? (connection.getContentLength() + deezerStart) - 1 : end);
                    range += "/" + Integer.toString(connection.getContentLength() + deezerStart);
                    outResponse.addHeader("Content-Range", range);
                }
                outResponse.addHeader("Accept-Ranges", "bytes");

                //Save stream info, use original track id since this is used to communicate with Flutter UI
                streams.put(Objects.requireNonNull(session.getParameters().get("id")).get(0), new StreamInfo(
                        ((qualityInfo.quality == 9) ? "FLAC" : "MP3"),
                        deezerStart + connection.getContentLength(),
                        "Stream"
                ));

                return outResponse;
            } catch (Exception e) {
                e.printStackTrace();
            }
            return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, "Failed getting data!");
        }
    }
}