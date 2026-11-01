// A swipe from the bottom edge toggles the overview. GNOME uses this edge for the on-screen
// keyboard, which also opens by itself in text fields, so its action is taken off the stage.
//
// Night Light: DECON has no gamma LUT in this kernel, so mutter cannot apply the temperature
// that gsd-color computes. A shader on the whole UI multiplies the colours instead.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as EdgeDragAction from 'resource:///org/gnome/shell/ui/edgeDragAction.js';
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

// PIN pad on the lock screen. The user password is the PIN, PAM stays unchanged.
const PIN_LENGTH = 4;

function addPinPad(dialog) {
    const prompt = dialog._authPrompt;
    if (!prompt || prompt._gta4xlPad)
        return;
    const entryText = () => prompt._entry.clutter_text;
    prompt._passwordEntry.clutter_text.input_hints |= Clutter.InputContentHintFlags.INHIBIT_OSK;

    const layout = new Clutter.GridLayout({column_spacing: 18, row_spacing: 18});
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

        // Auto login starts the session, the PIN protects it
        if (Main.sessionMode.currentMode === 'user' && !TabletGestures._lockedOnce) {
            TabletGestures._lockedOnce = true;
            GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, () => {
                Main.screenShield.lock(false);
                return GLib.SOURCE_REMOVE;
            });
        }

        this._handle = new ResizeHandle();
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

        this._osk = global.stage.get_action('osk');
        if (this._osk)
            global.stage.remove_action_by_name('osk');
        const modes = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;
        this._action = new EdgeDragAction.EdgeDragAction(St.Side.BOTTOM, modes);
        this._action.connect('activated', () => Main.overview.toggle());
        global.stage.add_action_full('gta4xl-overview', Clutter.EventPhase.CAPTURE, this._action);
    }

    disable() {
        UnlockDialog.UnlockDialog.prototype._ensureAuthPrompt = this._ensureAuthPrompt;
        global.display.disconnect(this._windowId);
        this._handle.destroy();
        this._handle = null;
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
