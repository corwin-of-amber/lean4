import sys
import csv
from collections import defaultdict

def main():
    # 1. Read the target locations from Coccinelle (via Standard Input)
    # Format: filename,line_number,func_name
    targets = defaultdict(list)
    for row in csv.reader(sys.stdin):
        if row and len(row) >= 2:
            filename, start_line = row[:2]
            targets[filename].append(int(start_line) - 1)

    # 2. Process each file
    for filename, lines in targets.items():
        with open(filename, 'r') as f:
            text = f.read()

        file_lines = text.splitlines(keepends=True)
        bounds_to_remove = []

        # 3. Find exact character boundaries for the '{' and '}'
        for line_idx in lines:
            if line_idx >= len(file_lines): continue

            # Calculate the raw character offset for the start of the line
            char_idx = sum(len(l) for l in file_lines[:line_idx])

            # Scan forward to find the function's opening brace
            start_brace = text.find('{', char_idx)
            if start_brace == -1: continue

            # Count braces to find the exact matching closing brace
            count = 0
            end_brace = -1
            for i in range(start_brace, len(text)):
                if text[i] == '{': count += 1
                elif text[i] == '}': count -= 1

                if count == 0:
                    end_brace = i
                    break

            if end_brace != -1:
                bounds_to_remove.append((start_brace, end_brace))

        # Slice out the bodies
        if bounds_to_remove:
            for start_b, end_b in sorted(bounds_to_remove, reverse=True):
                text = text[:start_b + 1] + "\n" + text[end_b:]

            with open(filename, 'w') as f:
                f.write(text)

            print(f"Processed {filename} (Emptied {len(bounds_to_remove)} functions)")

if __name__ == "__main__":
    main()
