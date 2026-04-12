import sys

filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

if '#include <cstdint>' not in content:
    content = '#include <cstdint>\n' + content
    with open(filepath, 'w') as f:
        f.write(content)
    print(f"Fixed: {filepath}")
