package r.r.refreezer;
class DeezerDecryptor {
    static byte[] getKey(String id) { throw new AssertionError("Offline data must already be playable"); }
    static byte[] decryptChunk(byte[] key, byte[] data) { throw new AssertionError("Offline data must not be decrypted twice"); }
}
