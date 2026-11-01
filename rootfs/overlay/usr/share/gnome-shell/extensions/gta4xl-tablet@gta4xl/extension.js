// A swipe from the bottom edge toggles the overview. GNOME uses this edge for the on-screen
// keyboard, which also opens by itself in text fields, so its action is taken off the stage.
import Clutter from 'gi://Clutter';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as EdgeDragAction from 'resource:///org/gnome/shell/ui/edgeDragAction.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class TabletGestures {
    enable() {
        this._osk = global.stage.get_action('osk');
        if (this._osk) {
            this._osk.ref?.();
            global.stage.remove_action_by_name('osk');
        }
        const modes = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;
        this._action = new EdgeDragAction.EdgeDragAction(St.Side.BOTTOM, modes);
        this._action.connect('activated', () => Main.overview.toggle());
        global.stage.add_action_full('gta4xl-overview', Clutter.EventPhase.CAPTURE, this._action);
    }

    disable() {
        global.stage.remove_action_by_name('gta4xl-overview');
        this._action = null;
        if (this._osk)
            global.stage.add_action_full('osk', Clutter.EventPhase.CAPTURE, this._osk);
        this._osk = null;
    }
}
