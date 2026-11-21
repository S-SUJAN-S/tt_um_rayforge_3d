# Leave two loads of headroom for antenna diodes added during routing.
# Extracted STA reads signoff.sdc and uses MAX_FANOUT_CONSTRAINT = 9.
source [file join $::env(SCRIPTS_DIR) base.sdc]
set_max_fanout 7 [current_design]
