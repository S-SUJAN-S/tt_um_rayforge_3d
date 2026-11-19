# Leave up to three loads of headroom for antenna diodes added during routing.
# Sign-off uses LibreLane's default SDC and MAX_FANOUT_CONSTRAINT = 9.
source [file join $::env(SCRIPTS_DIR) base.sdc]
set_max_fanout 6 [current_design]
