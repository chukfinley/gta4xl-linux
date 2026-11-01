// Window actions for Dash to Dock. Our patch of Dash to Dock calls extendMenu through
// Main.layoutManager.gta4xlDock, the same way that Dash to Dock publishes its struts.
//
// Long press and right click on an icon open the menu of Dash to Dock. The menu has the two halves.
// Drag an icon from the dock to the left or right part of the screen: the app fills that half, and
// a closed app starts there.
//
// The swipe from the bottom edge over the dock needs its own code. St.Button stops the touch begin,
// then Clutter drops all stage actions for this touch, also the EdgeDragAction of the extension.
// A captured-event handler still sees the touch, but the drag code would take it with a grab. So a
// touch in the edge zone gets no grab.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as DND from 'resource:///org/gnome/shell/ui/dnd.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const SNAP_PART = 0.25; // of the work area, at each side
const AFTER_MAXIMIZE_MS = 300; // a new window maximizes itself after 150 ms, see _onWindowCreated
const START_TIMEOUT_S = 30;
// The values of EdgeDragAction
const EDGE_ZONE = 20;
const DRAG_DISTANCE = 80;
const SWIPE_MODES = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;

// The button of the dock at the event, or null
function dockButton(event) {
    let button = null;
    for (let a = global.stage.get_event_actor(event); a; a = a.get_parent()) {
        button ??= a instanceof St.Button ? a : null;
        if (a.name === 'dashtodockContainer')
            return button;
    }
    return null;
}

export class DockActions {
    constructor(handles) {
        this._handles = handles;
        this._waiting = new Map(); // app to {id, timeoutId}
        this._later = new Set();
        // The class is private, a dummy object gives its prototype
        this._dragProto = Object.getPrototypeOf(DND.makeDraggable(new Clutter.Actor()));
        const grabActor = this._dragProto._grabActor;
        this._grabActor = grabActor;
        this._dragProto._grabActor = function (device, sequence) {
            const event = Clutter.get_current_event();
            if (!sequence || !event || event.get_coords()[1] < global.stage.height - EDGE_ZONE)
                grabActor.call(this, device, sequence);
        };
        this._monitor = {
            dragMotion: event => this._onDragMotion(event),
            dragDrop: event => this._onDrop(event),
        };
        DND.addDragMonitor(this._monitor);
        this._dragEnds = ['item-drag-end', 'item-drag-cancelled'].map(signal =>
            Main.overview.connect(signal, () => this._clearDrag()));
        this._eventId = global.stage.connect('captured-event', (_s, event) => {
            this._trackSwipe(event);
            return Clutter.EVENT_PROPAGATE;
        });
        Main.layoutManager.gta4xlDock = this;
    }

    _trackSwipe(event) {
        const type = event.type();
        if (type === Clutter.EventType.TOUCH_BEGIN) {
            if (this._swipe) {
                this._swipe = null; // the second finger is no edge swipe
                return;
            }
            const [x, y] = event.get_coords();
            if (y >= global.stage.height - EDGE_ZONE && Main.actionMode & SWIPE_MODES) {
                const button = dockButton(event);
                if (button)
                    this._swipe = {button, slot: event.get_event_sequence().get_slot(), x, y};
            }
            return;
        }
        if (!this._swipe || event.get_event_sequence()?.get_slot() !== this._swipe.slot)
            return;
        if (type === Clutter.EventType.TOUCH_UPDATE) {
            const [x, y] = event.get_coords();
            const up = this._swipe.y - y, side = Math.abs(x - this._swipe.x);
            if (side > up && side >= EDGE_ZONE) {
                this._swipe = null;
            } else if (up >= EDGE_ZONE && !this._swipe.up) {
                this._swipe.up = true;
                this._swipe.button.fake_release();
                this._swipe.button._delegate?._removeMenuTimeout?.();
            }
        } else if (type === Clutter.EventType.TOUCH_END) {
            const [, y] = event.get_coords();
            if (this._swipe.up && y < global.stage.height - DRAG_DISTANCE)
                Main.overview.toggle();
            this._swipe = null;
        } else if (type === Clutter.EventType.TOUCH_CANCEL) {
            this._swipe = null;
        }
    }

    _window(app) {
        return app.get_windows().find(win => !win.skip_taskbar && win.allows_move());
    }

    _snapApp(app, side) {
        const win = this._window(app);
        if (win) {
            Main.activateWindow(win);
            this._handles.snap(win, side);
        } else if (app.state === Shell.AppState.STOPPED) {
            this._startAt(app, side);
        }
    }

    _startAt(app, side) {
        this._stopWaiting(app);
        const id = app.connect('windows-changed', () => {
            const win = this._window(app);
            if (!win)
                return;
            this._stopWaiting(app);
            // Before its first frame a window has no size that a move can change
            const actor = win.get_compositor_private();
            const frameId = actor.connect('first-frame', () => {
                actor.disconnect(frameId);
                const later = GLib.timeout_add(GLib.PRIORITY_DEFAULT, AFTER_MAXIMIZE_MS, () => {
                    this._later.delete(later);
                    if (win.get_compositor_private())
                        this._handles.snap(win, side);
                    return GLib.SOURCE_REMOVE;
                });
                this._later.add(later);
            });
        });
        const timeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, START_TIMEOUT_S, () => {
            this._waiting.get(app).timeoutId = 0;
            this._stopWaiting(app);
            return GLib.SOURCE_REMOVE;
        });
        this._waiting.set(app, {id, timeoutId});
        app.activate();
    }

    _stopWaiting(app) {
        const wait = this._waiting.get(app);
        if (!wait)
            return;
        app.disconnect(wait.id);
        if (wait.timeoutId)
            GLib.source_remove(wait.timeoutId);
        this._waiting.delete(app);
    }

    extendMenu(menu, icon) {
        const {app} = icon;
        const win = this._window(app);
        if (!win)
            return;
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        [['left', 'Linke Hälfte'], ['right', 'Rechte Hälfte']].forEach(([side, label]) => {
            const item = new PopupMenu.PopupMenuItem(label);
            item.connect('activate', () => this._snapApp(app, side));
            menu.addMenuItem(item);
        });
    }

    _sideAt(x, y) {
        const monitor = Main.layoutManager.primaryIndex;
        const area = Main.layoutManager.getWorkAreaForMonitor(monitor);
        if (y < area.y || y >= area.y + area.height)
            return null;
        if (x < area.x + area.width * SNAP_PART)
            return 'left';
        return x > area.x + area.width * (1 - SNAP_PART) ? 'right' : null;
    }

    _onDragMotion({x, y, source}) {
        const app = source?.app;
        if (!app || Main.overview.visible) {
            this._clearDrag();
            return DND.DragMotionResult.CONTINUE;
        }
        this._drag = {app, side: this._sideAt(x, y)};
        this._handles.showPreview(this._drag.side, this._window(app) ??
            global.display.focus_window);
        return DND.DragMotionResult.CONTINUE;
    }

    // Returns CONTINUE, so the drag code ends the drag and the icon goes back to the dock
    _onDrop({clutterEvent}) {
        const app = this._drag?.app;
        this._clearDrag();
        // The last motion callback can be older than the release
        const side = app && this._sideAt(...clutterEvent.get_coords());
        if (side)
            this._snapApp(app, side);
        return DND.DragDropResult.CONTINUE;
    }

    _clearDrag() {
        if (this._drag)
            this._handles.showPreview(null);
        this._drag = null;
    }

    destroy() {
        delete Main.layoutManager.gta4xlDock;
        global.stage.disconnect(this._eventId);
        this._dragProto._grabActor = this._grabActor;
        DND.removeDragMonitor(this._monitor);
        this._dragEnds.forEach(id => Main.overview.disconnect(id));
        [...this._waiting.keys()].forEach(app => this._stopWaiting(app));
        this._later.forEach(id => GLib.source_remove(id));
        this._later.clear();
    }
}
