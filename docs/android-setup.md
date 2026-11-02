# LineageOS setup on the tablet

Device: Galaxy Tab S6 Lite LTE (SM-P615, gta4xl). LineageOS 23.2 (Android 16), userdebug, Magisk 31.1, no Google apps. Done on 2026-11-02.

For the install of LineageOS and Magisk, see `android-reinstall.md`.

## Access

- `adb root` works (userdebug build). `adb shell su -c <cmd>` works (Magisk).
- Root SSH: the dropbear Magisk module in `tools/android/rootssh`.

  ```sh
  adb forward tcp:2222 tcp:22
  ssh -p 2222 -o StrictHostKeyChecking=no root@127.0.0.1
  ```

- Screen PIN: 1234. The screen does not go off and does not lock by itself:

  ```sh
  settings put system screen_off_timeout 2147483647
  settings put secure lock_screen_lock_after_timeout 2147483647
  ```

- Unlock from the PC: `input keyevent WAKEUP; wm dismiss-keyguard; input text 1234; input keyevent ENTER`.

## Files on the PC

- APKs: `/mnt/data/android-linux/tools/lineage/apks/`.
- Morphe files: `/mnt/data/android-linux/tools/lineage/apks/morphe/` (CLI, patch bundles, `base/` original APKs, `out/` patched APKs, patch logs and JSON reports).
- Morphe signing key: `/mnt/data/android-linux/tools/lineage/apks/morphe/morphe-data/morphe.keystore`. Keep this file. An update of a patched app must have the same key, or Android refuses the update.
- Temporary files: `/mnt/data/android-linux/tmp/setup/`, `/mnt/data/android-linux/tmp/morphe/`.

## Installed apps

| App | Package | Version | Source |
|---|---|---|---|
| Tailscale | `com.tailscale.ipn` | 1.104.4 | before |
| F-Droid | `org.fdroid.fdroid` | | before |
| Termux | `com.termux` | | before |
| Brave | `com.brave.browser` | | before |
| Signal | `org.thoughtcrime.securesms` | | before |
| Magisk | `com.topjohnwu.magisk` | 31.1 | before |
| Fossify Gallery | `org.fossify.gallery` | 1.14.1 (30) | F-Droid |
| Fossify File Manager | `org.fossify.filemanager` | 1.6.3 (15) | F-Droid |
| Aurora Store | `com.aurora.store` | 4.8.4 (76) | F-Droid |
| T3 Code | `com.t3tools.t3code` | 2.2.0 (735) | APKMirror |
| Morphe Manager | `app.morphe.manager` | 2.3.0 | GitHub MorpheApp |
| microG (MicroG-RE) | `app.revanced.android.gms` | 7.3.0 | GitHub MorpheApp |
| YouTube (Morphe) | `app.morphe.android.youtube` | 21.30.216 | patched on the PC |
| Reddit (Morphe) | `com.reddit.frontpage` | 2026.40.0 | patched on the PC |
| X (piko) | `com.twitter.android` | 12.19.1-release.0 | patched on the PC |

Disabled system apps (`pm disable-user --user 0`): `org.lineageos.jelly` (browser), `org.lineageos.glimpse` (LineageOS gallery), `com.android.gallery3d`. To enable again: `pm enable <package>`.

## 1. Default browser: Brave

```sh
cmd role add-role-holder android.app.role.BROWSER com.brave.browser 0
pm disable-user --user 0 org.lineageos.jelly
cmd role get-role-holders android.app.role.BROWSER    # com.brave.browser
```

## 2. Gallery and file manager

F-Droid API for the suggested version: `https://f-droid.org/api/v1/packages/<package>` (field `suggestedVersionCode`). The APK is `https://f-droid.org/repo/<package>_<versionCode>.apk`.

The LineageOS gallery is `org.lineageos.glimpse`, not only `com.android.gallery3d`. Disable both. After that, Termux (`TermuxFileReceiverActivity`) is the second handler for images and videos, and Android shows a chooser. Android has no shell command to set a preferred activity. Thus a small root tool calls `IPackageManager.addPreferredActivity` with reflection. It sets Fossify Gallery as default for `image/*`, `image/jpeg`, `image/png`, `image/webp`, `image/gif`, `image/heic`, `image/heif` (`.activities.PhotoActivity`) and `video/*`, `video/mp4`, `video/webm`, `video/3gpp`, `video/x-matroska` (`.activities.VideoActivity`).

Source of the tool (`PrefAct.java`):

```java
import android.content.ComponentName;
import android.content.IntentFilter;
import android.os.IBinder;
import java.lang.reflect.Method;

/* app_process / PrefAct <action> <mimeType> <match-hex> <preferred comp> <comp1,comp2,...> */
public class PrefAct {
    public static void main(String[] a) throws Exception {
        String action = a[0], type = a[1];
        int match = Integer.parseInt(a[2], 16);
        ComponentName pref = ComponentName.unflattenFromString(a[3]);
        String[] parts = a[4].split(",");
        ComponentName[] set = new ComponentName[parts.length];
        for (int i = 0; i < parts.length; i++) set[i] = ComponentName.unflattenFromString(parts[i]);
        IntentFilter f = new IntentFilter(action);
        f.addCategory("android.intent.category.DEFAULT");
        f.addDataType(type);
        Class<?> sm = Class.forName("android.os.ServiceManager");
        IBinder b = (IBinder) sm.getMethod("getService", String.class).invoke(null, "package");
        Object pm = Class.forName("android.content.pm.IPackageManager$Stub")
            .getMethod("asInterface", IBinder.class).invoke(null, b);
        for (Method m : pm.getClass().getMethods()) {
            if (m.getName().equals("addPreferredActivity")) {
                Object[] args = m.getParameterCount() == 6
                    ? new Object[]{f, match, set, pref, 0, true}
                    : new Object[]{f, match, set, pref, 0};
                m.invoke(pm, args);
                System.out.println("ok " + type + " -> " + pref.flattenToShortString());
                return;
            }
        }
    }
}
```

Build and run:

```sh
javac -source 11 -target 11 -cp ~/Android/Sdk/platforms/android-36/android.jar -d cls PrefAct.java
d8 --output . cls/PrefAct.class && mv classes.dex prefact.dex
adb push prefact.dex /data/local/tmp/
adb shell su -c 'CLASSPATH=/data/local/tmp/prefact.dex app_process / PrefAct \
  android.intent.action.VIEW image/jpeg 600000 \
  org.fossify.gallery/.activities.PhotoActivity \
  org.fossify.gallery/.activities.PhotoActivity,com.termux/.filepicker.TermuxFileReceiverActivity'
```

The match value `600000` is `MATCH_CATEGORY_TYPE`. The component list must be the full set of handlers. If you install a new app that also opens images, Android shows the chooser again. Then select Fossify Gallery and "Always", or run the tool again with the new set.

Check: `dumpsys package preferred` and
`pm resolve-activity --brief -a android.intent.action.VIEW -d content://media/external/images/media/32 -t image/jpeg`.

File manager: the stock app is DocumentsUI ("Files"). It is weak, thus Fossify File Manager is installed. Do not disable DocumentsUI. Android needs it for the system file picker.

## 3. Material You and dark mode

The wallpaper is `/sdcard/Pictures/wallhaven-2166q9.jpg` (media id 32). It was already set (on home and lock screen) through the dialog on the tablet. `/data/system/users/0/wallpaper_orig` is the same picture (3840 x 2604).

```sh
settings put secure theme_customization_overlay_packages '{"android.theme.customization.color_source":"home_wallpaper","android.theme.customization.theme_style":"TONAL_SPOT","android.theme.customization.color_both":"1","_applied_timestamp":<now in ms>}'
cmd uimode night yes
cmd overlay list | grep -E 'neutral|accent|dynamic'    # all [x]
```

A new `_applied_timestamp` makes SystemUI apply the colors again.

## 4. Desktop mode (desktop windowing)

```sh
adb shell su -c '
settings put global development_settings_enabled 1
settings put global enable_freeform_support 1
settings put global force_resizable_activities 1
settings put global enable_non_resizable_multi_window 1
settings put global override_desktop_mode_features 1
setprop persist.wm.debug.desktop_mode_enforce_device_restrictions false
setprop persist.wm.debug.desktop_use_rounded_corners true
setprop persist.wm.debug.desktop_use_window_shadows true
setprop persist.wm.debug.desktop_mode true
setprop persist.wm.debug.desktop_mode_2 true'
adb reboot
```

The device config `config_isDesktopModeSupported` is false on this tablet. `persist.wm.debug.desktop_mode_enforce_device_restrictions=false` removes this check. `persist.wm.debug.desktop_mode` and `desktop_mode_2` are the old names (Android 14 and 15). Android 16 does not read them, but they do no harm.

Do not turn on the "desktop experience" features (`settings put global override_desktop_experience_features 1`, `persist.wm.debug.desktop_experience_devopts 1`). With them, SystemUI crashes when an app opens in a window: `IllegalStateException: Expected desk in display: 0` in `DesktopRepository.addTask`. They are set to 0 now.

Check after the reboot:

```sh
dumpsys activity activities | grep -E 'name=Desk|mode=freeform'
am start --windowingMode 5 -n com.termux/.app.TermuxActivity    # opens in a window
```

Result: a `Desk` root task exists. Apps open in windows with a title bar (minimize, maximize, close). The taskbar is at the bottom and shows the open apps. To start an app in a window: drag the app handle at the top of the app down, or use the app handle menu, or `am start --windowingMode 5`.

## 5. Aurora Store

`com.aurora.store` 4.8.4 from F-Droid, installed with `adb install`. It needs a first start on the tablet (anonymous login).

## 6. T3 Code

Android app: `com.t3tools.t3code` 2.2.0 from APKMirror (bundle `.apkm`, developer "T3 Tools"). Install of the needed splits:

```sh
unzip com.t3tools.t3code_2.2.0-*.apkm -d x
adb install-multiple -r x/base.apk x/split_config.arm64_v8a.apk x/split_config.xxhdpi.apk x/split_config.en.apk x/split_config.de.apk
```

The app starts and shows "No environments connected".

Web app: the T3 server is `http://claudecode:3773`. It is only on the tailnet. Log in to the Tailscale app first.

## 7. Morphe (patched YouTube, Reddit and X)

Morphe is the patch manager after ReVanced. Releases: https://github.com/MorpheApp. All patching was done on the PC with the Morphe CLI.

| Part | File | Release |
|---|---|---|
| CLI | `morphe-desktop-1.20.0-all.jar` | MorpheApp/morphe-desktop v1.20.0 |
| Patches (YouTube, YouTube Music, Reddit) | `patches-2.0.0.mpp` | MorpheApp/morphe-patches v2.0.0 |
| Patches for X and Instagram | `piko-patches-3.10.0.mpp` | crimera/piko v3.10.0 |
| Manager | `morphe-manager-2.3.0.apk` | MorpheApp/morphe-manager v2.3.0 |
| microG | `microg-7.3.0.apk` | MorpheApp/MicroG-RE 7.3.0 |

The official Morphe patches do not include X. The piko bundle has X patches in the Morphe format (`.mpp`).

Supported versions (`java -jar morphe-desktop-1.20.0-all.jar list-versions --patches=<mpp>`):

- YouTube: 21.30.216, 21.28.208, 21.23.492, 20.51.39, 20.26.46 (108 patches). Experimental (`-x`): 21.43.523, 21.42.241.
- Reddit: 2026.40.0, 2026.24.0, 2026.10.0 (29 patches). Experimental: 2026.44.0, 2026.43.0, 2026.42.0.
- X: 12.19.1-release.0 (72 patches).

Base APKs from APKMirror (with `apkmirror-dl`), in `base/`:

- `youtube-21.30.216.apk` (APK, nodpi, all architectures). Google certificate SHA-256 `3d7a1223…8f994a` (old key) and `5aad2bee…9cb0c6` (rotated key). Note: `apksigner` from `/usr/bin` is too old for this APK. Use `~/Android/Sdk/build-tools/36.1.0-rc1/apksigner`.
- `reddit-2026.40.0.apkm` (bundle). Certificate "reddit Inc." `970b9114…69736f`.
- `x-12.19.1.apkm` (bundle). Certificate "Twitter, Inc." `0fd9a0cf…ce2fe9`.

The CLI accepts `.apkm` bundles directly and merges the splits.

```sh
cd /mnt/data/android-linux/tools/lineage/apks/morphe
J="java -jar morphe-desktop-1.20.0-all.jar patch -t /mnt/data/android-linux/tmp/morphe/work"
$J -p patches-2.0.0.mpp -o out/youtube-morphe-21.30.216.apk -r out/youtube.json base/youtube-21.30.216.apk
$J -p patches-2.0.0.mpp -o out/reddit-morphe-2026.40.0.apk -r out/reddit.json base/reddit-2026.40.0.apkm
$J -p piko-patches-3.10.0.mpp -o out/x-piko-12.19.1.apk -r out/x.json base/x-12.19.1.apkm
adb install -r morphe-manager-2.3.0.apk
adb install -r microg-7.3.0.apk
adb install -r out/youtube-morphe-21.30.216.apk
adb install -r out/reddit-morphe-2026.40.0.apk
adb install -r out/x-piko-12.19.1.apk
```

Do not give `--keystore=<file>` for a file that does not exist: the CLI stops with "Keystore file not found". Without the option, the CLI makes `morphe-data/morphe.keystore` next to the JAR.

Results: YouTube 108 patches, Reddit 29 patches, X 72 patches, no failed patch. Each patch takes about 25 seconds. YouTube gets the package name `app.morphe.android.youtube` and uses microG with the vendor `app.revanced.android.gms` (MicroG-RE). Reddit and X keep their package names and get the version code 2147483647, so that the stores do not update them.

To make the X APK smaller next time, add `--striplibs=arm64-v8a` (now 314 MB with all architectures).

After the install:

```sh
for p in com.twitter.android com.reddit.frontpage app.morphe.android.youtube com.t3tools.t3code app.revanced.android.gms app.morphe.manager; do
  pm grant $p android.permission.POST_NOTIFICATIONS
done
dumpsys deviceidle whitelist +app.revanced.android.gms
```

All three apps start without a crash.

## 8. Checks after the reboot

- Root SSH: `ssh -p 2222 root@127.0.0.1 id` gives `uid=0(root)`, context `u:r:magisk:s0`.
- Magisk: `su -v` gives `31.1:MAGISKSU`. Module `rootssh` is in `/data/adb/modules`.
- Tailscale: the app starts and shows "Get Started" (not logged in).

## Steps for the user on the tablet

1. Tailscale: open the app, tap "Get Started", log in. Allow the VPN connection.
2. T3 Code web app in Brave (after step 1): open `http://claudecode:3773` in Brave. Tap the menu (three dots), then "Add to Home screen", then "Install" or "Add". Android has no command to add a pinned shortcut without a tap.
3. T3 Code app: tap "Add environment" and connect the T3 server (`http://claudecode:3773` over Tailscale). The pairing token is in `journalctl -u t3code` on the server.
4. microG: open "microG Settings" and add the Google account ("Accounts"), if you want to log in to YouTube.
5. YouTube: tap "Reject all" on the cookie dialog.
6. Aurora Store: open it once and select the anonymous login.

## Extra apps (2026-11-02)

- Vielstimmig: own build `~/git/vielstimmig-app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (local key, not the Play build).
- Chuk Chat: GitHub release `v1.0.113-pre.2` of `chuk-development/chuk_chat`, arm64 APK.
- Bitwarden: `com.x8bit.bitwarden-fdroid.apk` from the GitHub releases of `bitwarden/android`.
- Grok (`ai.x.grok`), Whoop (`com.whoop.android`), Plane (`com.plane.so`): XAPK from APKPure with `apkmirror-dl`. Install with `adb install-multiple -r <dir>/*.apk`. A selection of splits gives `INSTALL_FAILED_MISSING_SPLIT`. These XAPKs bring only `armeabi_v7a` splits, so the apps run as 32-bit.

Files: `/mnt/data/android-linux/tools/lineage/apks/own` and `.../more`.
