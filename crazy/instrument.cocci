// run with
//  spatch --sp-file crazy/instrument.cocci --dir stage0/stdlib/ --in-place

@@
identifier func;
@@
func(...) {
+   increment_call_count(__func__);
    ...
}
