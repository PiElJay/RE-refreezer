package r.r.refreezer;

import android.Manifest;
import android.app.Activity;
import android.content.ContentUris;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Read-only discovery. Runtime audio permission is requested only on Scan. */
final class LocalMusicBridge {
    static final int PERMISSION_REQUEST = 5821, FOLDER_REQUEST = 5822;
    private final Activity activity;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private MethodChannel.Result pending;
    LocalMusicBridge(Activity activity) { this.activity = activity; }
    private boolean begin(MethodChannel.Result result) {
        if (pending != null) { result.error("SCAN_BUSY", "Scansione già in corso", null); return false; }
        pending = result; return true;
    }
    void scan(MethodChannel.Result result) {
        if (!begin(result)) return;
        String permission = Build.VERSION.SDK_INT >= 33 ? Manifest.permission.READ_MEDIA_AUDIO : Manifest.permission.READ_EXTERNAL_STORAGE;
        if (ContextCompat.checkSelfPermission(activity, permission) != PackageManager.PERMISSION_GRANTED)
            ActivityCompat.requestPermissions(activity, new String[]{permission}, PERMISSION_REQUEST);
        else scanAsync(null);
    }
    void pickFolder(MethodChannel.Result result) {
        if (!begin(result)) return;
        try {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            activity.startActivityForResult(intent, FOLDER_REQUEST);
        } catch (Exception e) { fail("PICKER_UNAVAILABLE"); }
    }
    boolean permissionResult(int request, int[] grants) {
        if (request != PERMISSION_REQUEST) return false;
        if (grants.length == 0 || grants[0] != PackageManager.PERMISSION_GRANTED) fail("AUDIO_PERMISSION_DENIED");
        else scanAsync(null);
        return true;
    }
    boolean activityResult(int request, int code, Intent data) {
        if (request != FOLDER_REQUEST) return false;
        if (code != Activity.RESULT_OK || data == null || data.getData() == null) {
            HashMap<String, Object> cancelled = new HashMap<>();
            cancelled.put("items", new ArrayList<>()); cancelled.put("cancelled", true); complete(cancelled);
        } else {
            Uri tree = data.getData();
            try {
                activity.getContentResolver().takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                scanAsync(tree);
            } catch (SecurityException e) { fail("FOLDER_PERMISSION_DENIED"); }
        }
        return true;
    }
    private void scanAsync(Uri tree) {
        worker.execute(() -> {
            try {
                ArrayList<HashMap<String, Object>> items = new ArrayList<>();
                int[] counters = new int[3];
                if (tree == null) scanMedia(items);
                else walk(tree, DocumentsContract.getTreeDocumentId(tree), "", 0, new HashSet<>(), items, counters);
                HashMap<String, Object> result = new HashMap<>(); result.put("items", items);
                result.put("unreadable", counters[1]); result.put("truncated", counters[2] != 0);
                main.post(() -> complete(result));
            } catch (SecurityException e) { main.post(() -> fail("AUDIO_PERMISSION_DENIED")); }
            catch (Exception e) { main.post(() -> fail("LOCAL_SCAN_FAILED")); }
        });
    }
    private void scanMedia(ArrayList<HashMap<String, Object>> items) {
        Uri collection = Build.VERSION.SDK_INT >= 29 ? MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL) : MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
        String pathColumn = Build.VERSION.SDK_INT >= 29 ? MediaStore.Audio.Media.RELATIVE_PATH : MediaStore.Audio.Media.DATA;
        String[] columns = {MediaStore.Audio.Media._ID, MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.SIZE, pathColumn,
            MediaStore.Audio.Media.IS_MUSIC, MediaStore.Audio.Media.IS_RINGTONE,
            MediaStore.Audio.Media.IS_ALARM, MediaStore.Audio.Media.IS_NOTIFICATION};
        try (Cursor cursor = activity.getContentResolver().query(collection, columns, null, null, MediaStore.Audio.Media.TITLE + " ASC")) {
            if (cursor == null) return;
            while (!Thread.currentThread().isInterrupted() && cursor.moveToNext()) {
                HashMap<String, Object> item = new HashMap<>();
                item.put("uri", ContentUris.withAppendedId(collection, cursor.getLong(0)).toString());
                item.put("name", text(cursor.getString(1))); item.put("title", text(cursor.getString(2)));
                item.put("artist", text(cursor.getString(3))); item.put("album", text(cursor.getString(4)));
                item.put("durationMs", cursor.getLong(5)); item.put("size", cursor.getLong(6));
                item.put("path", text(cursor.getString(7))); item.put("isMusic", cursor.getInt(8) != 0);
                item.put("isRingtone", cursor.getInt(9) != 0); item.put("isAlarm", cursor.getInt(10) != 0);
                item.put("isNotification", cursor.getInt(11) != 0); items.add(item);
            }
        }
    }
    private void walk(Uri tree, String id, String path, int depth, HashSet<String> seen,
            ArrayList<HashMap<String, Object>> items, int[] counters) throws Exception {
        if (depth > 16 || counters[0] >= 20000) { counters[2] = 1; return; }
        if (!seen.add(id)) return;
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id);
        String[] columns = {DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE};
        try (Cursor cursor = activity.getContentResolver().query(children, columns, null, null, null)) {
            if (cursor == null) return;
            while (!Thread.currentThread().isInterrupted() && cursor.moveToNext()) {
                if (++counters[0] > 20000) { counters[2] = 1; return; }
                String childId = cursor.getString(0), name = text(cursor.getString(1)), mime = text(cursor.getString(2));
                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) {
                    walk(tree, childId, path + "/" + name, depth + 1, seen, items, counters); continue;
                }
                if (!mime.startsWith("audio/") && !mime.equals("application/octet-stream") && !name.matches("[0-9]+")) continue;
                Uri uri = DocumentsContract.buildDocumentUriUsingTree(tree, childId);
                MediaMetadataRetriever metadata = new MediaMetadataRetriever();
                try {
                    metadata.setDataSource(activity, uri);
                    String audioMime = text(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE));
                    if (!audioMime.startsWith("audio/") || "yes".equals(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO))) continue;
                    long duration = Long.parseLong(text(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)));
                    HashMap<String, Object> item = new HashMap<>();
                    item.put("uri", uri.toString()); item.put("name", name);
                    item.put("title", text(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)));
                    item.put("artist", text(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)));
                    item.put("album", text(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)));
                    item.put("durationMs", duration); item.put("size", cursor.getLong(3));
                    item.put("path", tree.toString() + path); item.put("selectedFolder", true); items.add(item);
                } catch (Exception e) { counters[1]++; }
                finally { try { metadata.release(); } catch (Exception ignored) {} }
            }
        }
    }
    private static String text(String value) { return value == null || value.equals("<unknown>") ? "" : value; }
    private void complete(HashMap<String, Object> data) { MethodChannel.Result result = pending; pending = null; if (result != null) result.success(data); }
    private void fail(String code) { MethodChannel.Result result = pending; pending = null; if (result != null) result.error(code, code, null); }
    void close() { worker.shutdownNow(); if (pending != null) fail("SCAN_INTERRUPTED"); }
}
