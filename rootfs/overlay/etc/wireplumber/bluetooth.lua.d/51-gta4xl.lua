-- Music only. The controller has no SCO path over HCI (SCO MTU 0:0) and the tablet has no
-- microphone, so HFP gives no audio here.
bluez_monitor.properties["bluez5.roles"] = "[ a2dp_sink a2dp_source ]"
bluez_monitor.properties["bluez5.hfphsp-backend"] = "none"

-- Headphones become the default sink when they connect, the speaker takes over when they go.
-- This needs no configured default sink: see tools/tablet/tune.sh.
table.insert(bluez_monitor.rules, {
  matches = { { { "node.name", "matches", "bluez_output.*" } } },
  apply_properties = { ["priority.session"] = 2000, ["priority.driver"] = 2000 },
})
