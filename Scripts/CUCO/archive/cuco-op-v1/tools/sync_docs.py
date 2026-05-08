#!/usr/bin/env python3
"""
Sync documentation between markdown and CSV formats
Keeps both formats in sync to avoid inconsistencies
Usage: python3 tools/sync_docs.py [--csv-to-md | --md-to-csv]
"""

import csv
import sys
import os
import argparse
from pathlib import Path

def read_csv_to_dict(csv_path):
    """Read CSV file and return list of dictionaries"""
    data = []
    with open(csv_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)
    return data

def update_coverage_md_from_csv(csv_path, md_path):
    """Update coverage.md from coverage.csv"""
    data = read_csv_to_dict(csv_path)
    
    # Group by tier
    tiers = {}
    for row in data:
        tier = row['Tier']
        if tier not in tiers:
            tiers[tier] = []
        tiers[tier].append(row)
    
    # Generate markdown
    md_content = """# System Functions Coverage

This tracks implementation status of CUCO-OP System Functions based on `docs/System Functions/` documentation and their exposure through the DSL and library APIs.

**Status Legend:** Planned | In-Progress | Done

Functions are ordered by implementation priority: highest-value, clearest wins first; niche or complex features last.

"""
    
    tier_names = {
        'Tier 0': 'Tier 0 — Foundations (Core Infrastructure)',
        'Tier 1': 'Tier 1 — Core Musical Functions (High-Impact)',
        'Tier 2': 'Tier 2 — Expressive Processing',
        'Tier 3': 'Tier 3 — Analysis and Theory',
        'Tier 4': 'Tier 4 — Structure and Development',
        'Tier 5': 'Tier 5 — External and Advanced'
    }
    
    for tier in ['Tier 0', 'Tier 1', 'Tier 2', 'Tier 3', 'Tier 4', 'Tier 5']:
        if tier in tiers:
            md_content += f"## {tier_names[tier]}\n\n"
            md_content += "| Function | Status | DSL Syntax | API | Notes |\n"
            md_content += "|----------|--------|------------|-----|-------|\n"
            
            for row in tiers[tier]:
                function = row['Function']
                status = row['Status']
                dsl = row['DSL Syntax']
                api = row['API']
                notes = row['Notes']
                
                # Handle special formatting for completed items
                if status == 'Done':
                    if 'VALIDATED' in notes:
                        function = f"**{function}**"
                        status = f"**{status}**"
                        dsl = f"**`{dsl}`**"
                        api = f"**`{api}`**"
                        notes = f"**{notes}**"
                
                md_content += f"| {function} | {status} | `{dsl}` | `{api}` | {notes} |\n"
            
            md_content += "\n"
    
    # Add footer
    completed_count = sum(1 for row in data if row['Status'] == 'Done')
    total_count = len(data)
    
    md_content += f"""## Implementation Progress

**Current Status:** {completed_count} of {total_count}+ functions complete
- **Completed Tier 0:** {len([r for r in tiers.get('Tier 0', []) if r['Status'] == 'Done'])} of {len(tiers.get('Tier 0', []))} functions
- **Completed Tier 1:** {len([r for r in tiers.get('Tier 1', []) if r['Status'] == 'Done'])} of {len(tiers.get('Tier 1', []))} functions
- **Completed Tier 2:** {len([r for r in tiers.get('Tier 2', []) if r['Status'] == 'Done'])} of {len(tiers.get('Tier 2', []))} functions
- **Next Priority:** Next highest priority planned function
"""
    
    # Write updated markdown
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write(md_content)
    
    print(f"✅ Updated {md_path} from {csv_path}")

def main():
    parser = argparse.ArgumentParser(description='Sync documentation between markdown and CSV formats')
    parser.add_argument('--csv-to-md', action='store_true', help='Update markdown from CSV')
    parser.add_argument('--md-to-csv', action='store_true', help='Update CSV from markdown (not implemented)')
    args = parser.parse_args()
    
    root_dir = Path(__file__).parent.parent
    
    if args.csv_to_md or not args.md_to_csv:
        # Default: update markdown from CSV
        csv_path = root_dir / 'docs/system_functions/coverage.csv'
        md_path = root_dir / 'docs/system_functions/coverage.md'
        
        if csv_path.exists() and md_path.exists():
            update_coverage_md_from_csv(csv_path, md_path)
        else:
            print(f"❌ Missing files: {csv_path} or {md_path}")
            return 1
    
    elif args.md_to_csv:
        print("❌ MD to CSV conversion not yet implemented")
        return 1
    
    return 0

if __name__ == '__main__':
    sys.exit(main())