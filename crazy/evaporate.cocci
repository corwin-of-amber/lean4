// run with
//  cp -r stage0/stdlib tmp/stage0
//  spatch --sp-file crazy/evaporate.cocci --dir tmp/stage0/stdlib/ --in-place

@initialize:python@
@@
# 1. Read the list of functions to keep into a fast-lookup set
keep_set = set()
try:
    with open('keep.txt', 'r') as f:
        keep_set = set(f.read().split())
except FileNotFoundError:
    print("ERROR: keep.txt not found. Aborting to prevent accidental deletion.")
    import sys
    sys.exit(1)

@find_func@
identifier func;
position p;
@@
// 2. Find every function definition and save its position
func@p(...) { ... }

@script:python filter_func@
func_name << find_func.func;
p << find_func.p;
@@
# 3. If the function IS in the keep list, abort this match
print(func_name)
if func_name in keep_set:
    cocci.include_match(False)

@empty_body@
identifier find_func.func;
position find_func.p;
@@
// 4. For any match that survived the filter, strip the body
func@p(...)
{
+ return 0;
...
}
