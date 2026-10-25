import java.io.*;
import java.lang.reflect.*;
import java.util.*;

/** Read-only accessibility snapshot, including application-owned secondary displays.
 * Runs as Android's existing shell user; installs no APK and changes no settings.
 */
public final class ToolkitBridge {
    static Object automation;
    static Object call(Object o, String method) throws Exception {
        return o.getClass().getMethod(method).invoke(o);
    }
    static String esc(Object o) {
        if (o == null) return "";
        return o.toString().replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")
            .replace("\n", "&#10;").replace("\r", "&#13;").replace("\t", "&#9;")
            .replaceAll("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f]", "");
    }
    static void attr(StringBuilder b, String key, Object v) {
        b.append(' ').append(key).append("=\"").append(esc(v)).append('"');
    }
    static void node(Object n, StringBuilder b, int depth) throws Exception {
        if (n == null || depth > 80) return;
        if (!Boolean.TRUE.equals(call(n, "isVisibleToUser"))) return;
        b.append("<node");
        attr(b, "text", call(n,"getText"));
        attr(b, "content-desc", call(n,"getContentDescription"));
        attr(b, "resource-id", call(n,"getViewIdResourceName"));
        attr(b, "class", call(n,"getClassName"));
        attr(b, "package", call(n,"getPackageName"));
        attr(b, "clickable", call(n,"isClickable"));
        attr(b, "enabled", call(n,"isEnabled"));
        attr(b, "selected", call(n,"isSelected"));
        Class<?> rect = Class.forName("android.graphics.Rect");
        Object r = rect.getConstructor().newInstance();
        n.getClass().getMethod("getBoundsInScreen",rect).invoke(n,r);
        attr(b, "bounds", "["+rect.getField("left").getInt(r)+","+rect.getField("top").getInt(r)+"]["+
            rect.getField("right").getInt(r)+","+rect.getField("bottom").getInt(r)+"]");
        b.append('>');
        int count = (Integer)call(n,"getChildCount");
        for (int i=0;i<count;i++) {
            Object c=n.getClass().getMethod("getChild",int.class).invoke(n,i);
            try { node(c,b,depth+1); } finally { if(c!=null) call(c,"recycle"); }
        }
        b.append("</node>");
    }
    public static void main(String[] args) throws Exception {
        Class<?> looper = Class.forName("android.os.Looper");
        looper.getMethod("prepareMainLooper").invoke(null);
        Class<?> ht=Class.forName("android.os.HandlerThread");
        Object thread=ht.getConstructor(String.class).newInstance("xhs-toolkit-ui");
        ht.getMethod("start").invoke(thread);
        Object loop=ht.getMethod("getLooper").invoke(thread);
        Class<?> connection=Class.forName("android.app.IUiAutomationConnection");
        Object conn=Class.forName("android.app.UiAutomationConnection").getConstructor().newInstance();
        Class<?> ua=Class.forName("android.app.UiAutomation");
        automation=ua.getConstructor(looper,connection).newInstance(loop,conn);
        int keepServices=ua.getField("FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES").getInt(null);
        ua.getMethod("connect",int.class).invoke(automation,keepServices);
        try {
            Object info=ua.getMethod("getServiceInfo").invoke(automation);
            Field flags=info.getClass().getField("flags");
            flags.setInt(info,flags.getInt(info)|64|16); // interactive windows + resource IDs
            ua.getMethod("setServiceInfo",info.getClass()).invoke(automation,info);
            Thread.sleep(150);
            if(args.length>0 && "--server".equals(args[0])) {
                System.out.println("READY"); System.out.flush();
                BufferedReader reader=new BufferedReader(new InputStreamReader(System.in,"UTF-8"));
                String line;
                while((line=reader.readLine())!=null && !"quit".equals(line)) {
                    if("dump".equals(line)) { snapshot(ua); System.out.flush(); }
                    if("copy".equals(line) || "copy-exists".equals(line)) {
                        System.out.println("COPY_RESULT "+copyLink(ua,"copy".equals(line))); System.out.flush();
                    }
                }
            } else snapshot(ua);
        } finally {
            ua.getMethod("disconnect").invoke(automation);
            ht.getMethod("quitSafely").invoke(thread);
        }
    }
    static void snapshot(Class<?> ua) throws Exception {
            Object client=Class.forName("android.view.accessibility.AccessibilityInteractionClient").getMethod("getInstance").invoke(null);
            client.getClass().getMethod("clearCache").invoke(client);
            StringBuilder b=new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?><hierarchy>");
            Object displays=ua.getMethod("getWindowsOnAllDisplays").invoke(automation);
            int size=(Integer)call(displays,"size");
            for(int i=0;i<size;i++) {
                int display=(Integer)displays.getClass().getMethod("keyAt",int.class).invoke(displays,i);
                List<?> windows=(List<?>)displays.getClass().getMethod("valueAt",int.class).invoke(displays,i);
                for(Object window:windows) {
                    Object root=call(window,"getRoot");
                    if(root==null)continue;
                    if(!"com.xingin.xhs".equals(String.valueOf(call(root,"getPackageName")))) { call(root,"recycle");continue; }
                    b.append("<window display=\"").append(display).append("\">");
                    try { node(root,b,0); } finally { call(root,"recycle"); }
                    b.append("</window>");
                }
            }
            System.out.println(b.append("</hierarchy>"));
    }
    static boolean hasTitle(Object n) throws Exception {
        String text=String.valueOf(call(n,"getText"));
        if("分享至".equals(text)||"分享到".equals(text)) return true;
        int count=(Integer)call(n,"getChildCount");
        for(int i=0;i<count;i++) {
            Object c=n.getClass().getMethod("getChild",int.class).invoke(n,i);
            if(c==null)continue;
            try { if(hasTitle(c))return true; } finally { call(c,"recycle"); }
        }
        return false;
    }
    static boolean copyNode(Object n, boolean perform, int depth) throws Exception {
        if(n==null || depth>80)return false;
        if("复制链接".equals(String.valueOf(call(n,"getText"))) || "复制链接".equals(String.valueOf(call(n,"getContentDescription")))) {
            if(!perform)return true;
            Object target=n;
            boolean owned=false;
            try {
                for(int i=0;i<4 && !Boolean.TRUE.equals(call(target,"isClickable"));i++) {
                    Object parent=call(target,"getParent");
                    if(parent==null)break;
                    if(owned)call(target,"recycle");
                    target=parent;owned=true;
                }
                if(Boolean.TRUE.equals(call(target,"isClickable")) && Boolean.TRUE.equals(call(target,"isEnabled")))
                    return Boolean.TRUE.equals(target.getClass().getMethod("performAction",int.class).invoke(target,16));
            } finally { if(owned)call(target,"recycle"); }
        }
        int count=(Integer)call(n,"getChildCount");
        for(int i=0;i<count;i++) {
            Object c=n.getClass().getMethod("getChild",int.class).invoke(n,i);
            if(c==null)continue;
            try { if(copyNode(c,perform,depth+1))return true; } finally { call(c,"recycle"); }
        }
        return false;
    }
    static boolean copyLink(Class<?> ua, boolean perform) throws Exception {
        Object displays=ua.getMethod("getWindowsOnAllDisplays").invoke(automation);
        int size=(Integer)call(displays,"size");
        for(int i=0;i<size;i++) {
            List<?> windows=(List<?>)displays.getClass().getMethod("valueAt",int.class).invoke(displays,i);
            for(Object window:windows) {
                Object root=call(window,"getRoot");
                if(root==null)continue;
                try {
                    if("com.xingin.xhs".equals(String.valueOf(call(root,"getPackageName"))) && hasTitle(root) && copyNode(root,perform,0)) return true;
                } finally { call(root,"recycle"); }
            }
        }
        return false;
    }
}
