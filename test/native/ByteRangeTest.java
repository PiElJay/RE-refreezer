package r.r.refreezer;
public final class ByteRangeTest {
    static int checks;
    static void check(String header, long size, long start, long end, long length) {
        ByteRange range = ByteRange.parse(header, size);
        if (range.start != start || range.end != end || range.length() != length) throw new AssertionError("Wrong bounds for " + header);
        checks++;
    }
    static void invalid(String header, long size) {
        try { ByteRange.parse(header, size); } catch (IllegalArgumentException expected) { checks++; return; }
        throw new AssertionError("Accepted invalid range " + header);
    }
    public static void main(String[] args) {
        check(null, 100, 0, 99, 100); check("bytes=0-0",100,0,0,1); check("bytes=99-",100,99,99,1);
        check("bytes=10-19",100,10,19,10); check("bytes=10-200",100,10,99,90);
        check("bytes=-10",100,90,99,10); check("bytes=-1000",100,0,99,100);
        check("bytes=2147483648-",3000000000L,2147483648L,2999999999L,852516352L);
        invalid("bytes=100-",100); invalid("bytes=50-49",100); invalid("bytes=-0",100);
        invalid("bytes=0-1,2-3",100); invalid("bad",100); invalid("bytes=abc-",100); invalid(null,0);
        for(int start=0;start<100;start++) for(int end=start;end<100;end++) check("bytes="+start+"-"+end,100,start,end,end-start+1);
        System.out.println("Native byte-range checks passed: " + checks);
    }
}
