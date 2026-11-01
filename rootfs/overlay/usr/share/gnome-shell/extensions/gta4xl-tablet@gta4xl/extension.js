// A swipe from the bottom edge toggles the overview. GNOME uses this edge for the on-screen
// keyboard, which also opens by itself in text fields, so its action is taken off the stage.
//
// Night Light: the kernel offers a gamma LUT only so that mutter and Settings accept Night Light.
// DECON ignores the LUT, a shader on the whole UI multiplies the colours instead.
//
// Long press and two finger tap give a secondary click in app windows, see TouchSecondary.
// GJS OSK runs only while no physical keyboard is connected, see _syncOsk.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

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

// A window corner is too small for a finger: this handle follows the focused window.
const HANDLE_SIZE = 72;
const MIN_WIDTH = 480;
const MIN_HEIGHT = 360;

class ResizeHandle {
    constructor() {
        this.actor = new St.Button({
            style_class: 'gta4xl-resize-handle',
            child: new St.Icon({icon_name: 'object-flip-vertical-symbolic', icon_size: 28}),
            width: HANDLE_SIZE,
            height: HANDLE_SIZE,
            reactive: true,
            can_focus: false,
            visible: false,
        });
        this.actor.child.rotation_angle_z = -45;
        this.actor.child.set_pivot_point(0.5, 0.5);
        Main.layoutManager.addTopChrome(this.actor);
        this.actor.connect('captured-event', (_a, event) => this._onEvent(event));
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
        const show = win && !Main.overview.visible && !win.fullscreen &&
            !win.get_maximized() && win.allows_resize();
        this.actor.visible = !!show;
        if (show) {
            const r = win.get_frame_rect();
            this.actor.set_position(r.x + r.width - HANDLE_SIZE * 0.7,
                r.y + r.height - HANDLE_SIZE * 0.7);
        }
    }

    _onEvent(event) {
        const type = event.type();
        const [x, y] = event.get_coords();
        if (type === Clutter.EventType.TOUCH_BEGIN || type === Clutter.EventType.BUTTON_PRESS) {
            if (!this._win)
                return Clutter.EVENT_PROPAGATE;
            this._start = {x, y, rect: this._win.get_frame_rect()};
            this._grab = global.stage.grab(this.actor);
            return Clutter.EVENT_STOP;
        }
        if (!this._start)
            return Clutter.EVENT_PROPAGATE;
        if (type === Clutter.EventType.TOUCH_UPDATE || type === Clutter.EventType.MOTION) {
            const now = GLib.get_monotonic_time();
            if (now - (this._last ?? 0) > 66000) {
                this._last = now;
                const {rect} = this._start;
                this._win?.move_resize_frame(true, rect.x, rect.y,
                    Math.max(MIN_WIDTH, rect.width + x - this._start.x),
                    Math.max(MIN_HEIGHT, rect.height + y - this._start.y));
            }
            return Clutter.EVENT_STOP;
        }
        if (type === Clutter.EventType.TOUCH_END || type === Clutter.EventType.TOUCH_CANCEL ||
            type === Clutter.EventType.BUTTON_RELEASE) {
            this._grab?.dismiss();
            this._grab = null;
            this._start = null;
            this._sync();
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    destroy() {
        this._grab?.dismiss();
        this._disconnectWindow();
        global.display.disconnect(this._focusId);
        this._overviewIds.forEach(id => Main.overview.disconnect(id));
        Main.layoutManager.removeChrome(this.actor);
        this.actor.destroy();
    }
}

// A secondary click from touch, for all apps. It works in the compositor because few Wayland apps
// have their own long press, and none has a two finger tap.
const LONG_PRESS_MS = 450; // before the 500 ms timers of GTK and Chromium
const TWO_FINGER_TAP_MS = 350;
const TOUCH_SLOP = 16;
const BOTTOM_EDGE = 24; // EdgeDragAction starts here
const CLICK_STEP_MS = 30;

function inAppWindow(event) {
    for (let a = global.stage.get_event_actor(event); a; a = a.get_parent()) {
        if (a instanceof Meta.WindowActor)
            return true;
    }
    return false;
}

class TouchSecondary {
    constructor() {
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
            if (this._touches.size === 0) {
                this._start = now;
                this._inApp = inAppWindow(event);
                this._pendingClick = null;
                this._tapOk = true;
                this._peak = 0;
            }
            this._touches.set(slot, {x, y, startX: x, startY: y});
            this._peak = Math.max(this._peak, this._touches.size);
            if (this._touches.size === 1) {
                if (this._allowed() && y < global.stage.height - BOTTOM_EDGE)
                    this._timer = this._later(LONG_PRESS_MS, () => this._onLongPress());
            } else {
                this._clearTimer();
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
            if (Math.abs(x - touch.startX) > TOUCH_SLOP ||
                Math.abs(y - touch.startY) > TOUCH_SLOP) {
                this._clearTimer();
                this._tapOk = false;
            }
            return;
        }

        this._touches.delete(slot);
        this._clearTimer();
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

        this._handle = new ResizeHandle();
        this._secondary = new TouchSecondary();
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
        this._handle.destroy();
        this._handle = null;
        this._secondary.destroy();
        this._secondary = null;
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
        if (this._osk)
            global.stage.add_action_full('osk', Clutter.EventPhase.CAPTURE, this._osk);
        this._osk = null;
    }
}
