// A swipe from the bottom edge toggles the overview. GNOME uses this edge for the on-screen
// keyboard, which also opens by itself in text fields, so its action is taken off the stage.
//
// Night Light: DECON has no gamma LUT in this kernel, so mutter cannot apply the temperature
// that gsd-color computes. A shader on the whole UI multiplies the colours instead.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as EdgeDragAction from 'resource:///org/gnome/shell/ui/edgeDragAction.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

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

    enable() {
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
