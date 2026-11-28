package dev.benz.mirror;

import android.content.ClipData;
import android.content.ClipDescription;
import android.net.Uri;
import android.os.IBinder;

import java.lang.reflect.Method;

/** Puts a file reference on the phone's clipboard so an app can paste it. Run by `app_process` as the shell user. */
public final class ClipHelper {
    public static void main(String[] args) throws Exception {
        if (args.length == 1 && args[0].equals("get")) { printClip(); return; }
        if (args.length < 2 || args.length % 2 != 0) { System.err.println("usage: ClipHelper <uri> <mime> [<uri> <mime> ...] | get"); System.exit(2); }
        ClipData clip = new ClipData(new ClipDescription("Benz Mirror file", new String[] {args[1]}), new ClipData.Item(Uri.parse(args[0])));
        for (int i = 2; i < args.length; i += 2) clip.addItem(new ClipData.Item(Uri.parse(args[i])));

        IBinder binder = (IBinder) Class.forName("android.os.ServiceManager").getMethod("getService", String.class).invoke(null, "clipboard");
        Object manager = Class.forName("android.content.IClipboard$Stub").getMethod("asInterface", IBinder.class).invoke(null, binder);

        for (Method method : manager.getClass().getMethods()) {
            if (!method.getName().equals("setPrimaryClip")) continue;
            Class<?>[] types = method.getParameterTypes();
            Object[] values = new Object[types.length];
            int strings = 0;
            for (int i = 0; i < types.length; i++) {
                if (types[i] == ClipData.class) values[i] = clip;
                else if (types[i] == String.class) values[i] = strings++ == 0 ? "com.android.shell" : null;
                else if (types[i] == int.class) values[i] = 0;
                else if (types[i] == boolean.class) values[i] = false;
            }
            method.invoke(manager, values);
            System.out.println("ok " + types.length);
            return;
        }
        System.err.println("no setPrimaryClip");
        System.exit(3);
    }

    /** Prints what the clipboard holds (mime types and uris), so the Mac can check that a file really is there. */
    private static void printClip() throws Exception {
        IBinder binder = (IBinder) Class.forName("android.os.ServiceManager").getMethod("getService", String.class).invoke(null, "clipboard");
        Object manager = Class.forName("android.content.IClipboard$Stub").getMethod("asInterface", IBinder.class).invoke(null, binder);
        for (Method method : manager.getClass().getMethods()) {
            if (!method.getName().equals("getPrimaryClip")) continue;
            Class<?>[] types = method.getParameterTypes();
            Object[] values = new Object[types.length];
            int strings = 0;
            for (int i = 0; i < types.length; i++) {
                if (types[i] == String.class) values[i] = strings++ == 0 ? "com.android.shell" : null;
                else if (types[i] == int.class) values[i] = 0;
                else if (types[i] == boolean.class) values[i] = false;
            }
            ClipData clip = (ClipData) method.invoke(manager, values);
            if (clip == null) { System.out.println("empty"); return; }
            StringBuilder out = new StringBuilder("clip");
            for (int i = 0; i < clip.getDescription().getMimeTypeCount(); i++) out.append(" ").append(clip.getDescription().getMimeType(i));
            for (int i = 0; i < clip.getItemCount(); i++) { Uri uri = clip.getItemAt(i).getUri(); out.append(" uri=").append(uri); }
            System.out.println(out);
            return;
        }
        System.out.println("no getPrimaryClip");
    }
}
