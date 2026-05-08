#!/bin/bash
# CUCO-OP Fresh Context Message Generator
# Usage: ./tools/fresh_context_message.sh

echo "=== CUCO-OP FRESH CONTEXT HANDOFF MESSAGE ==="
echo ""
echo "Copy and paste this message to the new context:"
echo ""
echo "---"
echo ""
echo "Hi! Welcome to CUCO-OP. This is a fresh context, so please follow our mandatory workspace familiarization protocol first."
echo ""
echo "CRITICAL: Before any work, you MUST complete the full workspace exploration process documented in START_HERE.md. This prevents dangerous oversights like missing the 40+ algorithm directories in docs/System\ Functions/ or other critical components."
echo ""
echo "Quick start:"
echo "1. Read START_HERE.md completely - it has mandatory workspace familiarization steps"
echo "2. Execute the workspace scan commands listed there to see ALL directories"
echo "3. Complete the workspace acknowledgment checklist"
echo "4. Review current status in ai_workflows/project_status.md"
echo ""

# Get current status from project_status.md
echo "Current context (auto-generated from project_status.md):"
if [ -f "ai_workflows/project_status.md" ]; then
    # Extract just a few key lines from status
    echo "$(grep -A 3 "## Current Status" ai_workflows/project_status.md 2>/dev/null || echo "Status: Check ai_workflows/project_status.md for current priorities")"
else
    echo "Status: Check ai_workflows/project_status.md for current priorities"
fi

echo ""
echo "Key systems now available:"
echo "- Knowledge base (ai_workflows/knowledge_base/) - check before any debugging"
echo "- Research framework (ai_workflows/research/) - use for complex mathematical concepts"
echo "- Complete development workflow with safeguards"
echo ""
echo "Don't skip the workspace familiarization - it's designed to prevent context loss. Take 5-10 minutes to properly orient yourself first."
echo ""
echo "---"
echo ""
echo "Message generated on: $(date)"
