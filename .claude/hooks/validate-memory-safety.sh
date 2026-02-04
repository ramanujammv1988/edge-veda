#!/bin/bash
# .claude/hooks/validate-memory-safety.sh
# Check for memory safety issues in C++ code
# This hook runs on Edit operations for C++ files

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Exit early if not a C++ file
if [[ ! "$FILE_PATH" =~ \.(cpp|cc|c|h|hpp)$ ]]; then
    exit 0
fi

# Exit if file doesn't exist yet
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

WARNINGS=0

# Check for raw new/delete (prefer smart pointers)
if grep -n '\bnew\b' "$FILE_PATH" 2>/dev/null | grep -v "placement new" | grep -v "// NOLINT" | grep -v "operator new" > /dev/null; then
    echo "WARNING: Raw 'new' detected in $FILE_PATH" >&2
    echo "  Consider using std::unique_ptr or std::shared_ptr" >&2
    grep -n '\bnew\b' "$FILE_PATH" | grep -v "placement new" | grep -v "// NOLINT" | head -3 >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Check for raw delete
if grep -n '\bdelete\b' "$FILE_PATH" 2>/dev/null | grep -v "// NOLINT" > /dev/null; then
    echo "WARNING: Raw 'delete' detected in $FILE_PATH" >&2
    echo "  Consider using RAII or smart pointers" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Check for malloc/free (prefer C++ allocation)
if grep -n '\bmalloc\b\|\bfree\b\|\bcalloc\b\|\brealloc\b' "$FILE_PATH" 2>/dev/null | grep -v "// NOLINT" > /dev/null; then
    echo "WARNING: C-style memory allocation detected in $FILE_PATH" >&2
    echo "  Consider using std::vector or smart pointers" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Check for unchecked pointer dereference patterns
if grep -n '\*[a-zA-Z_][a-zA-Z0-9_]*[^=]' "$FILE_PATH" 2>/dev/null | grep -v "nullptr" | grep -v "// NOLINT" > /dev/null; then
    # This is a heuristic - just a reminder
    echo "INFO: Pointer dereferences found - ensure null checks exist" >&2
fi

if [ $WARNINGS -gt 0 ]; then
    echo "" >&2
    echo "Found $WARNINGS memory safety warning(s). Add '// NOLINT' to suppress if intentional." >&2
fi

# Always exit 0 - these are warnings, not blockers
exit 0
