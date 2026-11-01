#!/usr/bin/python3
# One window control: T3 Code and Mattermost ask Electron for caption buttons. Electron draws them as
# native views over the page, so page CSS cannot hide them, and no command line switch exists.
# This changes the window options inside app.asar. Each change has the same length, so the asar
# index stays correct. Run it again after an update of the app. Argument --undo restores the file.
import shutil
import sys

PAD = "/*{}*/"


def same_length(old, new):
    gap = len(old) - len(new)
    if gap < 4:
        raise SystemExit(f"no space in {old!r}")
    return (new + PAD.format(" " * (gap - 4))).encode()


T3_OLD = (
    "titleBarOverlay: {\n\t\t\tcolor: TITLEBAR_COLOR,\n\t\t\theight: TITLEBAR_HEIGHT,\n"
    "\t\t\tsymbolColor: shouldUseDarkColors ? TITLEBAR_DARK_SYMBOL_COLOR : "
    "TITLEBAR_LIGHT_SYMBOL_COLOR\n\t\t}"
)
MM_OVERLAY = "titleBarOverlay:n?void 0:this.getTitleBarOverlay()"
MM_SET = "this.win.setTitleBarOverlay(this.getTitleBarOverlay())"

APPS = {
    "/opt/T3 Code (Beta)/resources/app.asar": [(T3_OLD, "titleBarOverlay: false")],
    "/opt/Mattermost/resources/app.asar": [
        (MM_OVERLAY, "titleBarOverlay:!1"),
        (MM_SET, "0"),
    ],
}


def patch(path, changes):
    data = open(path, "rb").read()
    done = 0
    for old, new in changes:
        raw, fixed = old.encode(), same_length(old, new)
        count = data.count(raw)
        if count:
            data = data.replace(raw, fixed)
            done += count
        elif fixed not in data:
            print(f"{path}: text not found, the app changed: {old[:40]!r}")
    if done:
        shutil.copy2(path, path + ".orig")
        open(path, "r+b").write(data)
    print(f"{path}: {done} changes")


def main():
    for path, changes in APPS.items():
        try:
            if "--undo" in sys.argv:
                shutil.move(path + ".orig", path)
            else:
                patch(path, changes)
        except FileNotFoundError as error:
            print(f"{path}: {error}")


main()
