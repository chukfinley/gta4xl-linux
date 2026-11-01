// A swipe from the bottom edge toggles the overview. GNOME uses this edge for the on-screen
// keyboard, which also opens by itself in text fields, so its action is taken off the stage.
//
// Night Light: the kernel offers a gamma LUT only so that mutter and Settings accept Night Light.
// DECON ignores the LUT, a shader on the whole UI multiplies the colours instead.
//
// Swipe down from the top edge, by position: right quick settings, middle calendar, left leaves
// full screen.
// Windows have the iPadOS grabbers: an arc at the bottom right corner and a bar at the top, see
// WindowHandles. Long press and two finger tap give a secondary click, see TouchGestures.
// GJS OSK runs only while no physical keyboard is connected, see _syncOsk.
import Cairo from 'cairo';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as BoxPointer from 'resource:///org/gnome/shell/ui/boxpointer.js';
import * as EdgeDragAction from 'resource:///org/gnome/shell/ui/edgeDragAction.js';
import * as Keyboard from 'resource:///org/gnome/shell/ui/keyboard.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as UnlockDialog from 'resource:///org/gnome/shell/ui/unlockDialog.js';

const NightEffect = GObject.registerClass(
class NightEffect extends Clutter.ShaderEffect {
    _init() {
        super._init({shader_type: Clutter.ShaderType.FRAGMENT_SHADER});
        this.set_shader_source(`
            uniform sampler2D tex;
            uniform float green;
            uniform float blue;
            void main() {
                vec4 c = texture2D(tex, cogl_tex_coord_in[0].st);
                cogl_color_out = vec4(c.r, c.g * green, c.b * blue, c.a) * cogl_color_in;
            }`);
        this.set_uniform_value('tex', 0);
    }

    setTemperature(kelvin) {
        // Tanner Helland blackbody fit, red stays 1 below 6600 K
        const t = kelvin / 100;
        const green = (99.47 * Math.log(t) - 161.12) / 255;
        const blue = t <= 19 ? 0 : (138.52 * Math.log(t - 10) - 305.04) / 255;
        this.set_uniform_value('green', Math.min(1, Math.max(0, green)) + 0.0);
        this.set_uniform_value('blue', Math.min(1, Math.max(0, blue)) + 0.0);
    }
});

// iPadOS window grabbers for the focused window. They only draw, so a tap still reaches the app.
// TouchGestures takes the touch when it moves in a grab zone. A corner drag moves only an outline
// in the compositor, the client gets one resize at the end: apps redraw too slowly to follow.
const CHROME = {affectsInputRegion: false};
const MIN_WIDTH = 360;
const MIN_HEIGHT = 300;
const SNAP_EDGE = 32;
const CORNER_RADIUS = 14; // of a GTK window
const ARC_GAP = 5;
const ARC_SIZE = 30;
const ARC_CORNER = 20; // the window corner, inside the arc actor
const ARC_MAX_INSET = 8;
const CORNER_ZONE_IN = 56;
const CORNER_ZONE_OUT = 28;
const BAR_WIDTH = 44;
const BAR_ZONE_WIDTH = 140;
const BAR_ZONE_HEIGHT = 34;

function drawArc(area) {
    const cr = area.get_context();
    const center = ARC_CORNER - CORNER_RADIUS;
    cr.setLineCap(Cairo.LineCap.ROUND);
    // The dark line keeps the arc visible over a light window
    [[6, 0, 0.3], [3.5, 1, 0.95]].forEach(([width, grey, alpha]) => {
        cr.setLineWidth(width);
        cr.setSourceRGBA(grey, grey, grey, alpha);
        cr.arc(center, center, CORNER_RADIUS + ARC_GAP, 0.03 * Math.PI, 0.47 * Math.PI);
        cr.stroke();
    });
    cr.$dispose();
}

class WindowHandles {
    constructor() {
        this._arc = new St.DrawingArea({width: ARC_SIZE, height: ARC_SIZE, visible: false});
        this._arc.connect('repaint', drawArc);
        this._bar = new St.Widget({style_class: 'gta4xl-window-bar', visible: false});
        this._preview = new St.Widget({style_class: 'gta4xl-snap-preview', visible: false});
        this._actors = [this._preview, this._arc, this._bar];
        this._actors.forEach(actor => Main.layoutManager.addTopChrome(actor, CHROME));
        this._halves = new WeakMap(); // size of a window before it filled half of the screen
        this._focusId = global.display.connect('notify::focus-window', () => this._track());
        this._overviewIds = [
            Main.overview.connect('showing', () => this._sync()),
            Main.overview.connect('hidden', () => this._sync()),
        ];
        this._track();
    }

    _disconnectWindow() {
        if (this._win)
            this._winIds.forEach(id => this._win.disconnect(id));
        this._win = null;
        this._winIds = [];
    }

    _track() {
        this._disconnectWindow();
        const win = global.display.focus_window;
        if (win && win.window_type === Meta.WindowType.NORMAL) {
            this._win = win;
            this._winIds = ['position-changed', 'size-changed', 'unmanaged',
                'notify::fullscreen', 'notify::maximized-vertically']
                .map(signal => win.connect(signal, () => {
                    if (signal === 'unmanaged')
                        this._track();
                    else
                        this._sync();
                }));
        }
        this._sync();
    }

    _sync() {
        const win = this._win;
        const show = !!win && !Main.overview.visible && !win.fullscreen;
        this._arc.visible = show && win.resizeable;
        this._bar.visible = show;
        if (!show)
            return;
        const r = win.get_frame_rect();
        // A maximized window has its corner at the screen edge, the arc must stay on the screen
        const inset = ARC_CORNER + (win.get_maximized() ? ARC_MAX_INSET : 0);
        this._arc.set_position(r.x + r.width - inset, r.y + r.height - inset);
        this._bar.set_position(r.x + Math.round((r.width - BAR_WIDTH) / 2), r.y + 4);
    }

    // The grab zone at this point, 'corner', 'bar' or null
    zoneAt(x, y) {
        if (!this._bar.visible)
            return null;
        const r = this._win.get_frame_rect();
        const right = r.x + r.width, bottom = r.y + r.height;
        if (this._arc.visible && x > right - CORNER_ZONE_IN && x < right + CORNER_ZONE_OUT &&
            y > bottom - CORNER_ZONE_IN && y < bottom + CORNER_ZONE_OUT)
            return 'corner';
        if (Math.abs(x - (r.x + r.width / 2)) < BAR_ZONE_WIDTH / 2 && y >= r.y &&
            y < r.y + BAR_ZONE_HEIGHT)
            return 'bar';
        return null;
    }

    begin(zone, x, y) {
        const win = this._win;
        this._drag = {zone, x, y, rect: win.get_frame_rect()};
        if (zone === 'bar' && win.get_maximized()) {
            win.unmaximize(Meta.MaximizeFlags.BOTH);
        } else if (zone === 'bar' && this._halves.has(win)) {
            const {width, height} = this._halves.get(win);
            win.move_resize_frame(true, x - width / 2, this._drag.rect.y, width, height);
        }
        this._halves.delete(win);
    }

    _area() {
        return Main.layoutManager.getWorkAreaForMonitor(this._win.get_monitor());
    }

    // Where a drop at this point puts the window: 'left', 'right', 'top' or null
    _snapAt(x, y) {
        const area = this._area();
        if (y < area.y + SNAP_EDGE)
            return 'top';
        if (x < area.x + SNAP_EDGE)
            return 'left';
        return x > area.x + area.width - SNAP_EDGE ? 'right' : null;
    }

    _place(x, y, width, height) {
        this._preview.set_position(x, y);
        this._preview.set_size(width, height);
        this._preview.visible = true;
    }

    _showPreview(snap) {
        this._preview.visible = false;
        if (!snap)
            return;
        const area = this._area();
        const half = Math.floor(area.width / 2);
        this._place(snap === 'right' ? area.x + half : area.x, area.y,
            snap === 'top' ? area.width : half, area.height);
    }

    _size(x, y) {
        const {rect, x: startX, y: startY} = this._drag;
        return [Math.max(MIN_WIDTH, rect.width + x - startX),
            Math.max(MIN_HEIGHT, rect.height + y - startY)];
    }

    update(x, y) {
        if (!this._win)
            return;
        if (this._drag.zone === 'corner') {
            const {rect} = this._drag;
            const [width, height] = this._size(x, y);
            this._place(rect.x, rect.y, width, height);
            this._arc.set_position(rect.x + width - ARC_CORNER, rect.y + height - ARC_CORNER);
            return;
        }
        const area = this._area();
        const {width, height} = this._win.get_frame_rect();
        // The window stays on the screen, the finger alone reaches the snap zones
        const keep = (value, start, length, size) =>
            Math.max(start, Math.min(value, start + length - size));
        this._win.move_frame(true, keep(x - width / 2, area.x, area.width, width),
            keep(y - BAR_ZONE_HEIGHT / 2, area.y, area.height, height));
        this._showPreview(this._snapAt(x, y));
    }

    end(x, y) {
        const win = this._win;
        this._preview.visible = false;
        if (win && this._drag.zone === 'corner') {
            const {rect} = this._drag;
            const [width, height] = this._size(x, y);
            if (win.get_maximized())
                win.unmaximize(Meta.MaximizeFlags.BOTH);
            win.move_resize_frame(true, rect.x, rect.y, width, height);
        } else if (win) {
            const snap = this._snapAt(x, y);
            if (snap === 'top') {
                win.maximize(Meta.MaximizeFlags.BOTH);
            } else if (snap) {
                const {width, height} = win.get_frame_rect();
                const area = this._area();
                const half = Math.floor(area.width / 2);
                this._halves.set(win, {width, height});
                win.move_resize_frame(true, snap === 'right' ? area.x + half : area.x, area.y,
                    half, area.height);
            }
        }
        this._drag = null;
    }

    destroy() {
        this._disconnectWindow();
        global.display.disconnect(this._focusId);
        this._overviewIds.forEach(id => Main.overview.disconnect(id));
        this._actors.forEach(actor => {
            Main.layoutManager.removeChrome(actor);
            actor.destroy();
        });
    }
}

// Touch rules for all apps. They work in the compositor because few Wayland apps have their own
// long press, and none has a two finger tap. A gesture ends the touch of the client.
const LONG_PRESS_MS = 450; // before the 500 ms timers of GTK and Chromium
const TWO_FINGER_TAP_MS = 350;
const TOUCH_SLOP = 16;
const GRAB_SLOP = 4; // before the 8 px at which GTK starts its own title bar drag
const SCREEN_EDGE = 24; // EdgeDragAction starts here
const CLICK_STEP_MS = 30;

function inAppWindow(event) {
    for (let a = global.stage.get_event_actor(event); a; a = a.get_parent()) {
        if (a instanceof Meta.WindowActor)
            return true;
    }
    return false;
}

class TouchGestures {
    constructor(handles) {
        this._handles = handles;
        const seat = Clutter.get_default_backend().get_default_seat();
        this._pointer = seat.create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE);
        // Mutter has no API to cancel touch points. It sends wl_touch.cancel when a stage gesture
        // begins, so this action only exists to emit gesture-begin. With 9 points Clutter never
        // starts it. The tracker resets itself when the last finger goes up.
        this._canceller = new Clutter.GestureAction({n_touch_points: 9});
        global.stage.add_action_full('gta4xl-touch-cancel', Clutter.EventPhase.CAPTURE,
            this._canceller);
        this._touches = new Map();
        this._sources = new Set();
        this._eventId = global.stage.connect('captured-event', (_s, event) => {
            this._onEvent(event);
            return Clutter.EVENT_PROPAGATE;
        });
    }

    _allowed() {
        return this._inApp && !Main.overview.visible && !Main.sessionMode.isLocked &&
            Main.modalCount === 0;
    }

    _zoneFor(event, x, y) {
        const actor = global.stage.get_event_actor(event);
        if (Main.overview.visible || Main.sessionMode.isLocked || Main.modalCount > 0 ||
            !actor || !global.window_group.contains(actor) ||
            y > global.stage.height - SCREEN_EDGE)
            return null;
        return this._handles.zoneAt(x, y);
    }

    _later(ms, callback) {
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._sources.delete(id);
            callback();
            return GLib.SOURCE_REMOVE;
        });
        this._sources.add(id);
        return id;
    }

    _clearTimer() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._sources.delete(this._timer);
        }
        this._timer = 0;
    }

    _click(x, y) {
        // The pointer must enter the surface first, the client needs the serial of the press
        this._pointer.notify_absolute_motion(Clutter.CURRENT_TIME, x, y);
        this._later(CLICK_STEP_MS, () => {
            this._pointer.notify_button(Clutter.CURRENT_TIME, Clutter.BUTTON_SECONDARY,
                Clutter.ButtonState.PRESSED);
            this._later(CLICK_STEP_MS, () => {
                this._pointer.notify_button(Clutter.CURRENT_TIME, Clutter.BUTTON_SECONDARY,
                    Clutter.ButtonState.RELEASED);
                // A touch user has no use for the arrow
                Meta.CursorTracker.get_for_display(global.display).set_pointer_visible(false);
            });
        });
    }

    _onLongPress() {
        this._timer = 0;
        if (this._touches.size !== 1 || !this._allowed())
            return;
        const [touch] = this._touches.values();
        this._pendingClick = [touch.x, touch.y];
        this._canceller.emit('gesture-begin', global.stage);
    }

    _onEvent(event) {
        const type = event.type();
        if (type !== Clutter.EventType.TOUCH_BEGIN && type !== Clutter.EventType.TOUCH_UPDATE &&
            type !== Clutter.EventType.TOUCH_END && type !== Clutter.EventType.TOUCH_CANCEL)
            return;
        const slot = event.get_event_sequence()?.get_slot();
        if (slot === undefined)
            return;
        const [x, y] = event.get_coords();
        const now = GLib.get_monotonic_time() / 1000;

        if (type === Clutter.EventType.TOUCH_BEGIN) {
            // A window drag of the client takes the touch and the end never arrives here
            if (this._touches.has(slot))
                this._touches.clear();
            if (this._touches.size === 0) {
                this._start = now;
                this._inApp = inAppWindow(event);
                this._pendingClick = null;
                this._tapOk = true;
                this._peak = 0;
                this._grabbing = false;
                this._zone = this._zoneFor(event, x, y);
            }
            this._touches.set(slot, {x, y, startX: x, startY: y});
            this._peak = Math.max(this._peak, this._touches.size);
            if (this._touches.size === 1) {
                if (this._allowed() && !this._zone && y > SCREEN_EDGE &&
                    y < global.stage.height - SCREEN_EDGE)
                    this._timer = this._later(LONG_PRESS_MS, () => this._onLongPress());
            } else {
                this._clearTimer();
                this._zone = null;
                if (this._touches.size > 2 || now - this._start > TWO_FINGER_TAP_MS)
                    this._tapOk = false;
                const [a, b] = this._touches.values();
                this._middle = [(a.x + b.x) / 2, (a.y + b.y) / 2];
            }
            return;
        }

        const touch = this._touches.get(slot);
        if (!touch)
            return;
        if (type === Clutter.EventType.TOUCH_UPDATE) {
            touch.x = x;
            touch.y = y;
            const moved = Math.max(Math.abs(x - touch.startX), Math.abs(y - touch.startY));
            if (this._grabbing) {
                this._handles.update(x, y);
            } else if (this._zone && moved > GRAB_SLOP) {
                this._tapOk = false;
                this._grabbing = true;
                this._canceller.emit('gesture-begin', global.stage);
                this._handles.begin(this._zone, touch.startX, touch.startY);
            } else if (moved > TOUCH_SLOP) {
                this._clearTimer();
                this._tapOk = false;
            }
            return;
        }

        this._touches.delete(slot);
        this._clearTimer();
        if (this._grabbing) {
            this._grabbing = false;
            this._handles.end(x, y);
            return;
        }
        if (type === Clutter.EventType.TOUCH_CANCEL)
            this._tapOk = false;
        if (this._touches.size > 0 || !this._allowed())
            return;
        // With a finger still down mutter drops the pointer focus and the press gets lost, so the
        // long press clicks when the finger goes up. The client already got wl_touch.cancel.
        if (this._pendingClick)
            this._click(...this._pendingClick);
        else if (this._peak === 2 && this._tapOk && now - this._start <= TWO_FINGER_TAP_MS)
            this._click(...this._middle);
    }

    destroy() {
        global.stage.disconnect(this._eventId);
        this._sources.forEach(id => GLib.source_remove(id));
        this._sources.clear();
        global.stage.remove_action_by_name('gta4xl-touch-cancel');
        this._canceller = null;
        this._pointer = null;
    }
}

// PIN pad on the lock screen. The user password is the PIN, PAM stays unchanged.
const PIN_LENGTH = 4;

function addPinPad(dialog) {
    const prompt = dialog._authPrompt;
    if (!prompt || prompt._gta4xlPad)
        return;
    const entryText = () => prompt._entry.clutter_text;
    prompt._passwordEntry.clutter_text.input_hints |= Clutter.InputContentHintFlags.INHIBIT_OSK;
    prompt._passwordEntry.hint_text = 'PIN';

    const layout = new Clutter.GridLayout({column_spacing: 14, row_spacing: 10});
    const pad = new St.Widget({
        layout_manager: layout,
        x_align: Clutter.ActorAlign.CENTER,
        style_class: 'gta4xl-pin-pad',
    });
    const press = key => {
        const text = entryText();
        if (key === 'del') {
            text.text = text.text.slice(0, -1);
        } else if (key === 'ok') {
            text.emit('activate');
        } else {
            text.text += key;
            if (text.text.length >= PIN_LENGTH)
                text.emit('activate');
        }
    };
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'ok'].forEach((key, i) => {
        const params = {style_class: 'gta4xl-pin-key', can_focus: false, reactive: true};
        const button = key === 'del' || key === 'ok'
            ? new St.Button({...params, child: new St.Icon({
                icon_name: key === 'del' ? 'edit-clear-symbolic' : 'object-select-symbolic',
                icon_size: 30,
            })})
            : new St.Button({...params, label: key});
        button.connect('clicked', () => press(key));
        layout.attach(button, i % 3, Math.floor(i / 3), 1, 1);
    });
    dialog._promptBox.add_child(pad);
    prompt._gta4xlPad = pad;
}

// GJS OSK replaces the GNOME keyboard. It has no rule for a physical keyboard, its setting
// "never" still opens it for a touch on a shell text field, so it is turned off completely.
const OSK_UUID = 'gjsosk@vishram1123.com';
const OSK_SYNC_MS = 1000;
const NOT_A_KEYBOARD = /^(gpio_keys|sec_touchscreen|sec_e-pen|hall|.*Headset Jack|.*\(AVRCP\))$/;

function physicalKeyboard(seat) {
    return seat.list_devices().some(device =>
        device.get_device_type() === Clutter.InputDeviceType.KEYBOARD_DEVICE &&
        device.get_device_mode() !== Clutter.InputMode.LOGICAL &&
        device.get_device_node() && !NOT_A_KEYBOARD.test(device.get_device_name()));
}

const COLOR_NAME = 'org.gnome.SettingsDaemon.Color';
const COLOR_PATH = '/org/gnome/SettingsDaemon/Color';

export default class TabletGestures {
    _syncNightLight() {
        const active = this._color?.get_cached_property('NightLightActive')?.unpack();
        const temp = this._color?.get_cached_property('Temperature')?.unpack();
        const on = active && temp > 1000 && temp < 6400;
        if (on) {
            this._night.setTemperature(temp);
            if (!this._nightOn)
                Main.layoutManager.uiGroup.add_effect_with_name('gta4xl-night', this._night);
        } else if (this._nightOn) {
            Main.layoutManager.uiGroup.remove_effect_by_name('gta4xl-night');
        }
        this._nightOn = on;
    }

    // The GNOME action comes back when GJS OSK stops, it must not compete with the overview swipe
    _dropOskAction() {
        const action = global.stage.get_action('osk');
        if (action) {
            this._osk ??= action;
            global.stage.remove_action_by_name('osk');
        }
    }

    _syncOsk() {
        const manager = Main.extensionManager;
        if (!manager.lookup(OSK_UUID) || Main.sessionMode.isLocked)
            return;
        const wanted = !physicalKeyboard(this._seat);
        const enabled = global.settings.get_strv('enabled-extensions').includes(OSK_UUID);
        if (wanted && !enabled)
            manager.enableExtension(OSK_UUID);
        else if (!wanted && enabled)
            manager.disableExtension(OSK_UUID);
    }

    _queueSyncOsk() {
        if (this._oskSyncId)
            GLib.source_remove(this._oskSyncId);
        this._oskSyncId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, OSK_SYNC_MS, () => {
            this._oskSyncId = 0;
            this._syncOsk();
            return GLib.SOURCE_REMOVE;
        });
    }

    _onTopSwipe(action) {
        const [x] = action.get_press_coords(0);
        const monitor = Main.layoutManager.primaryMonitor;
        const part = (x - monitor.x) / monitor.width;
        const {quickSettings, dateMenu} = Main.panel.statusArea;
        if (part > 2 / 3) {
            quickSettings.menu.open(BoxPointer.PopupAnimation.FULL);
        } else if (part > 1 / 3) {
            dateMenu.menu.open(BoxPointer.PopupAnimation.FULL);
        } else {
            const win = global.display.focus_window;
            if (win?.is_fullscreen())
                win.unmake_fullscreen();
        }
    }

    _onWindowCreated(win) {
        if (win.window_type !== Meta.WindowType.NORMAL || !win.can_maximize())
            return;
        // New windows fill the screen as on a tablet. A double tap on the title restores them.
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
            win.maximize(Meta.MaximizeFlags.BOTH);
            return GLib.SOURCE_REMOVE;
        });
    }

    enable() {
        const proto = UnlockDialog.UnlockDialog.prototype;
        const ensure = proto._ensureAuthPrompt;
        this._ensureAuthPrompt = ensure;
        proto._ensureAuthPrompt = function () {
            ensure.call(this);
            addPinPad(this);
        };

        // The PIN pad replaces the on-screen keyboard on the lock screen, GJS OSK the rest
        const keyboard = Keyboard.Keyboard.prototype;
        const open = keyboard.open;
        this._keyboardOpen = open;
        keyboard.open = function (...args) {
            if (!Main.sessionMode.isLocked && !Main.extensionManager.lookup(OSK_UUID))
                open.apply(this, args);
        };

        // Auto login starts the session, the PIN protects it
        if (Main.sessionMode.currentMode === 'user' && !TabletGestures._lockedOnce) {
            TabletGestures._lockedOnce = true;
            GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, () => {
                Main.screenShield.lock(false);
                return GLib.SOURCE_REMOVE;
            });
        }

        this._handles = new WindowHandles();
        this._gestures = new TouchGestures(this._handles);
        this._windowId = global.display.connect('window-created',
            (_d, win) => this._onWindowCreated(win));
        this._night = new NightEffect();
        this._nightOn = false;
        Gio.DBusProxy.new_for_bus(Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, null,
            COLOR_NAME, COLOR_PATH, COLOR_NAME, null, (_o, res) => {
                this._color = Gio.DBusProxy.new_for_bus_finish(res);
                this._colorId = this._color.connect('g-properties-changed',
                    () => this._syncNightLight());
                this._syncNightLight();
            });

        this._osk = null;
        this._dropOskAction();
        const modes = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;
        this._action = new EdgeDragAction.EdgeDragAction(St.Side.BOTTOM, modes);
        this._action.connect('activated', () => Main.overview.toggle());
        global.stage.add_action_full('gta4xl-overview', Clutter.EventPhase.CAPTURE, this._action);

        // GNOME leaves full screen on a swipe from any point of the top edge. That would fire
        // together with the panels, so the left part of this action does its work.
        this._unfullscreen = global.stage.get_action('unfullscreen');
        global.stage.remove_action_by_name('unfullscreen');
        this._topAction = new EdgeDragAction.EdgeDragAction(St.Side.TOP, modes);
        this._topAction.connect('activated', action => this._onTopSwipe(action));
        global.stage.add_action_full('gta4xl-top', Clutter.EventPhase.CAPTURE, this._topAction);

        this._seat = Clutter.get_default_backend().get_default_seat();
        this._seatIds = ['device-added', 'device-removed']
            .map(signal => this._seat.connect(signal, () => this._queueSyncOsk()));
        this._extensionId = Main.extensionManager.connect('extension-state-changed',
            () => this._dropOskAction());
        this._queueSyncOsk();
    }

    disable() {
        UnlockDialog.UnlockDialog.prototype._ensureAuthPrompt = this._ensureAuthPrompt;
        Keyboard.Keyboard.prototype.open = this._keyboardOpen;
        global.display.disconnect(this._windowId);
        this._gestures.destroy();
        this._gestures = null;
        this._handles.destroy();
        this._handles = null;
        this._seatIds.forEach(id => this._seat.disconnect(id));
        this._seat = null;
        Main.extensionManager.disconnect(this._extensionId);
        if (this._oskSyncId)
            GLib.source_remove(this._oskSyncId);
        this._oskSyncId = 0;
        if (this._color)
            this._color.disconnect(this._colorId);
        this._color = null;
        this._nightOn = true;
        this._syncNightLight();
        this._night = null;

        global.stage.remove_action_by_name('gta4xl-overview');
        this._action = null;
        global.stage.remove_action_by_name('gta4xl-top');
        this._topAction = null;
        global.stage.add_action_full('unfullscreen', Clutter.EventPhase.CAPTURE,
            this._unfullscreen);
        if (this._osk)
            global.stage.add_action_full('osk', Clutter.EventPhase.CAPTURE, this._osk);
        this._osk = null;
    }
}
