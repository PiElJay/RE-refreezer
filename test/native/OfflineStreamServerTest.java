package r.r.refreezer;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
public final class OfflineStreamServerTest {
    static int checks;
    static int port;
    static String token;
    static void request(String query,String range,int status,byte[] expected,String contentRange)throws Exception {
        HttpURLConnection c=(HttpURLConnection)new URL("http://127.0.0.1:"+port+"/"+query+(query.contains("?")?"&":"?")+"_auth="+token).openConnection();
        c.setConnectTimeout(2000); c.setReadTimeout(2000);
        if(range!=null)c.setRequestProperty("Range",range);
        if(c.getResponseCode()!=status)throw new AssertionError("Wrong status for "+range);
        if(contentRange!=null&&!contentRange.equals(c.getHeaderField("Content-Range")))throw new AssertionError("Wrong Content-Range");
        if(expected!=null)try(InputStream input=c.getInputStream()) {
            if(!Arrays.equals(input.readAllBytes(),expected))throw new AssertionError("Corrupted bytes for "+range);
            if(c.getContentLengthLong()!=expected.length)throw new AssertionError("Wrong length");
        }
        c.disconnect(); checks++;
    }
    public static void main(String[] args)throws Exception {
        Path dir=Files.createTempDirectory("refreezer-offline-http-");byte[] track=new byte[8192];
        for(int i=0;i<track.length;i++)track[i]=(byte)(i*31+7);Files.write(dir.resolve("test-track"),track);
        StreamServer server=new StreamServer("test-only",dir.toString());
        try {
            server.start(); port=server.getPort(); token=server.getAccessToken(); request("health",null,200,"{\"status\":\"ready\"}".getBytes(),null);
            String correctToken=token; token="wrong";
            request("?id=test-track",null,403,null,null); token=correctToken;
            request("?id=../settings.json",null,400,null,null);
            request("?id=%2e%2e%2fsettings.json",null,400,null,null);
            request("?id=%2Fetc%2Fpasswd",null,400,null,null);
            request("?id=test-track&_auth=duplicate",null,403,null,null);
            request("?id=test-track",null,200,track,null);
            request("?id=test-track","bytes=0-0",206,new byte[]{track[0]},"bytes 0-0/8192");
            request("?id=test-track","bytes=4095-4097",206,Arrays.copyOfRange(track,4095,4098),"bytes 4095-4097/8192");
            request("?id=test-track","bytes=8191-",206,new byte[]{track[8191]},"bytes 8191-8191/8192");
            request("?id=test-track","bytes=-4",206,Arrays.copyOfRange(track,8188,8192),"bytes 8188-8191/8192");
            request("?id=test-track","bytes=8192-",416,null,"bytes */8192");
            request("?id=test-track","bytes=20-10",416,null,"bytes */8192");
            request("?id=test-track&q=9&trackToken=&streamTrackId=test-track&md5origin=&mv=",null,200,track,null);
            Path secret=dir.getParent().resolve("vybe-test-secret-"+System.nanoTime());
            Files.writeString(secret,"synthetic secret");
            Path link=dir.resolve("linked-track");
            try {
                Files.createSymbolicLink(link,secret);
                request("?id=linked-track",null,400,null,null);
            } finally { Files.deleteIfExists(link); Files.delete(secret); }
            StreamServer second=new StreamServer("test-only",dir.toString());
            try {
                second.start();
                if(server.getPort()==second.getPort())throw new AssertionError("Servers share a port");
                port=second.getPort(); token=second.getAccessToken();
                request("health",null,200,"{\"status\":\"ready\"}".getBytes(),null);
                request("?id=test-track",null,200,track,null);
            } finally {second.stop();port=server.getPort(); token=server.getAccessToken();}
            System.out.println("Real offline HTTP server checks passed: "+checks);
        }finally {server.stop();Files.delete(dir.resolve("test-track"));Files.delete(dir);}
    }
}
