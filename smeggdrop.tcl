# smeggdrop.tcl
encoding system utf-8
set SMEGGDROP_ROOT [file dirname [info script]]

if [file exists smeggdrop.conf] {source smeggdrop.conf}
source $SMEGGDROP_ROOT/smeggdrop/smeggdrop.tcl
