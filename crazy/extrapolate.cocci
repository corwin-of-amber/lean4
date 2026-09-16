@initialize:python@
@@
try:
    with open('keep.txt', 'r') as f:
        keep_set = set(f.read().split())
except FileNotFoundError:
    print("ERROR: keep.txt not found.")
    import sys
    sys.exit(1)

@find_func@
type T;
identifier func;
position p;
@@
// Only match the function name and capture its line number
T func(...) {@p ... }

@script:python@
func << find_func.func;
p << find_func.p;
@@
if func not in keep_set:
    print(f"{p[0].file},{p[0].line},{func}")
