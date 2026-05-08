# CUCO-OP IDE Interface Research

**Date:** September 29, 2025  
**Status:** In Progress - Research Phase  
**System Function Category:** UI/UX - Primary Interface  
**Priority:** Core Development - Main User Interface  

## Research Objective

Design and implement a comprehensive IDE-style interface for CUCO-OP within REAPER using ImGui, based on the established AIMS requirements and analysis of three reference IDE implementations.

## Interface Requirements Analysis (from AIMS.md)

### Primary Features Required
1. **GUI Text Editor**: Syntax highlighting, code completion, error highlighting
2. **Execution Engine**: Run code with real-time feedback
3. **MIDI Integration**: Seamless connection to REAPER's MIDI system
4. **Template Library**: Pre-built examples and starting points
5. **Documentation Browser**: Integrated access to function reference

### Current State Assessment
- **Existing skeleton**: Basic ImGui/gfx fallback with click counter
- **Working engine**: Full tokenizer/parser/executor pipeline operational
- **Test system**: OSC automation with MIDI generation/validation working
- **5 of 11 Tier 1 system functions implemented and tested**

## Reference Architecture Analysis

### 1. ImGui-Text-Editor-main
**Architecture Pattern**: Simple file-based editor
- **File management**: Multi-tab interface with file hierarchy
- **Text editing**: Basic ImGui InputTextMultiline with syntax highlighting
- **UI structure**: Menu bar, file tree, tab system, editor pane

**Key Components Identified:**
```cpp
struct OpenedFile {
    std::string name;
    std::vector<char> content;
    bool isOpen = false;
    bool showEdit = true;
};
std::vector<OpenedFile> openedFiles;
```

**Strengths**: Simple, lightweight, direct file operations
**Limitations**: Basic editing features, no advanced IDE functionality

### 2. Zep Editor
**Architecture Pattern**: Embeddable modal editor engine
- **Layer architecture**: Text → Display → Mode plugins (Vim/Standard)
- **Buffer management**: Gap buffer with UTF8 support
- **Syntax highlighting**: Pluggable syntax engine
- **Modal editing**: Full Vim emulation + standard editing

**Key Architecture:**
- **Text Layer**: Buffer manipulation, undo/redo, search
- **Display Layer**: Rendering abstraction (Qt/ImGui backends)  
- **Mode Layer**: Vim/Standard editing behaviors
- **Tab/Split system**: Multi-window workspace management

**Strengths**: Professional-grade editor, modal editing, extensible
**Considerations**: C++ implementation, complex integration

### 3. Ned Editor  
**Architecture Pattern**: Full-featured development environment
- **Tree Sitter**: Advanced syntax highlighting (15+ languages)
- **LSP integration**: Language server protocol support
- **Terminal emulator**: Embedded terminal with multiplexer
- **AI integration**: OpenRouter integration for completion
- **Multi-cursor**: Advanced cursor management

**Key Features for CUCO-OP:**
- **Retro aesthetics**: OpenGL shaders, customizable themes
- **File explorer**: Tree-based file navigation
- **Multi-tab interface**: Workspace management
- **Extensible architecture**: Plugin system for custom languages

## CUCO-OP Interface Architecture Design

### Core Components Required

#### 1. **Text Editor Component**
```lua
-- Text editor state management
local TextEditor = {
    content = "",           -- Current document content
    cursor_pos = {row=1, col=1},
    selection = {start_pos=nil, end_pos=nil},
    syntax_tokens = {},     -- Cached tokenization for highlighting
    error_markers = {},     -- Syntax error positions
    file_path = nil,        -- Current file (if saved)
    is_dirty = false       -- Has unsaved changes
}
```

**Functions needed:**
- `TextEditor:render()` - Main ImGui rendering
- `TextEditor:handle_input()` - Keyboard/mouse input processing
- `TextEditor:apply_syntax_highlighting()` - CUCO Stacks syntax coloring
- `TextEditor:update_error_markers()` - Real-time syntax validation

#### 2. **Execution Engine Integration**
```lua
-- Engine integration for live coding
local ExecutionEngine = {
    last_valid_ast = nil,   -- Cached valid parse
    execution_context = {}, -- Runtime context
    midi_output_buffer = {},-- Generated events
    error_state = nil,      -- Parse/execution errors
    auto_execute = false    -- Live coding mode
}
```

**Functions needed:**
- `ExecutionEngine:parse_and_validate()` - Real-time parsing
- `ExecutionEngine:execute_to_midi()` - Generate MIDI events
- `ExecutionEngine:send_to_reaper()` - Write MIDI items
- `ExecutionEngine:clear_output()` - Clean up previous output

#### 3. **Template Library System**
```lua
-- Template management
local TemplateLibrary = {
    categories = {
        "Basic Notation",
        "Chord Progressions", 
        "Rhythm Patterns",
        "System Functions",
        "Advanced Techniques"
    },
    templates = {},         -- Loaded template data
    current_filter = ""     -- Search filter
}
```

**Functions needed:**
- `TemplateLibrary:load_templates()` - Load from docs/templates/
- `TemplateLibrary:render_browser()` - Template selection UI
- `TemplateLibrary:insert_template()` - Add template to editor
- `TemplateLibrary:save_as_template()` - Save current as template

#### 4. **Documentation Browser**
```lua
-- Function reference integration
local DocumentationBrowser = {
    function_db = {},       -- Parsed function documentation
    current_search = "",    -- Search query
    selected_function = nil,-- Currently viewed function
    context_help = true     -- Show help for cursor position
}
```

**Functions needed:**
- `DocumentationBrowser:load_function_db()` - Parse docs/system_functions/
- `DocumentationBrowser:render_browser()` - Documentation UI
- `DocumentationBrowser:show_context_help()` - Cursor-based help
- `DocumentationBrowser:search_functions()` - Search functionality

#### 5. **REAPER Integration Layer**
```lua
-- REAPER-specific functionality
local ReaperIntegration = {
    selected_items = {},    -- Currently selected MIDI items
    target_track = nil,     -- Output track
    playback_state = "stopped",
    project_context = {}    -- Project-specific data
}
```

**Functions needed:**
- `ReaperIntegration:get_selected_items()` - Read current selection
- `ReaperIntegration:create_midi_item()` - Generate new MIDI
- `ReaperIntegration:update_existing_items()` - Modify selected items
- `ReaperIntegration:setup_playback()` - Live preview integration

## UI Layout Design

### Primary Window Layout
```
┌─────────────────────────────────────────────────────────────────────┐
│ Menu Bar: File | Edit | Code | Templates | Help                    │
├─────────────────────────┬───────────────────────────────────────────┤
│                         │ Editor Tabs: [Untitled*] [main.cuco]     │
│  Template Browser       ├───────────────────────────────────────────┤
│  ┌─ Basic Notation      │                                           │
│  ├─ Chord Progressions  │    MAIN TEXT EDITOR AREA                 │
│  ├─ Rhythm Patterns     │    ~16 @c.major                          │
│  └─ System Functions    │    melody = [c4 d4 e4 f4]                │
│                         │    ch1 = melody                           │
│                         │                                           │
├─────────────────────────┼───────────────────────────────────────────┤
│                         │ Output/Status Area                        │
│  Documentation Browser  │ ✓ Generated 4 events                     │
│  ┌─ Search: "ambitus"   │ ⚠ Warning: Channel 2 unused              │
│  ├─ ambitus()           │ [Execute] [Clear Output] [Send to REAPER] │
│  ├─ ambitus_filter()    │                                           │  
│  └─ ambitus_field()     │                                           │
└─────────────────────────┴───────────────────────────────────────────┘
```

### Key UI Features

#### Syntax Highlighting Scheme
Based on CUCO Stacks notation analysis:
- **Grid/Context**: `~16`, `@c.major` - **Blue/Bold**
- **Notes**: `c4`, `d#3` - **Green**
- **Special tokens**: `x`, `_`, `.` - **Yellow**  
- **Processors**: `!arp()`, `!vel()` - **Purple/Bold**
- **Assignments**: `=`, channel names - **White/Bold**
- **Comments**: `--` lines - **Gray/Italic**
- **Errors**: Invalid syntax - **Red background**

#### Auto-completion System
Context-aware suggestions:
- **After `!`**: Show available processors with parameters
- **After `@`**: Show scale/context options
- **After `~`**: Show grid resolution options
- **Variable names**: Show defined variables for reuse

#### Real-time Validation
- **Parse on keystroke** (with debounce): Immediate syntax highlighting
- **Error markers**: Red underlines with hover tooltips
- **Success indicators**: Green checkmark when valid

## Implementation Phases

### Phase 1: Core Editor (Week 1)
- Basic text editing with ImGui InputTextMultiline
- CUCO Stacks syntax highlighting
- Real-time parsing integration
- Simple execute button

### Phase 2: UI Enhancement (Week 2)  
- Template browser implementation
- Documentation browser integration
- Menu system and keyboard shortcuts
- File save/load functionality

### Phase 3: REAPER Integration (Week 3)
- MIDI output to REAPER items
- Selected item processing
- Live preview capabilities
- Project integration

### Phase 4: Advanced Features (Week 4)
- Auto-completion system
- Advanced error handling
- Theme/appearance customization
- Performance optimization

## Integration with Existing Engine

### Engine Interface Adaptation
The existing engine provides:
```lua
-- Available from engine.lua
engine.process_notation(notation_string) -> plan, context, ast
engine.tokenize(notation_string) -> tokens  
engine.parse(notation_string) -> ast
engine.execute(ast, context) -> plan, context
```

### UI-Engine Bridge Functions Needed
```lua
-- Bridge functions to implement
function get_syntax_highlighting(text) -> highlight_data
function validate_syntax(text) -> errors, warnings  
function get_completion_suggestions(text, cursor_pos) -> suggestions
function execute_live(text) -> midi_events, errors
```

## Success Metrics

### Functional Requirements
- **Text editing**: Smooth, responsive editing experience
- **Syntax highlighting**: Real-time CUCO Stacks highlighting
- **Error detection**: Immediate feedback on syntax errors  
- **Template system**: Easy access to example code
- **MIDI integration**: Seamless REAPER MIDI generation

### User Experience Goals
- **Learning curve**: New users can create basic sequences within 5 minutes
- **Power user efficiency**: Experienced users prefer it over external editors
- **Live coding**: Suitable for real-time performance scenarios
- **Documentation access**: Help system reduces need for external reference

### Performance Requirements  
- **Startup time**: < 1 second to fully loaded interface
- **Syntax highlighting**: < 100ms update on keystroke
- **Execution time**: < 500ms from code to MIDI output
- **Memory usage**: < 50MB for typical editing sessions

## Next Steps

1. **Create basic text editor component** with ImGui integration
2. **Implement CUCO Stacks syntax highlighting** using existing tokenizer
3. **Add execute functionality** using existing engine
4. **Build template browser** with example CUCO code
5. **Integrate documentation system** using system functions docs

This research provides the foundation for building a professional-quality IDE interface for CUCO-OP that leverages the existing robust engine while providing an intuitive creative environment for musical composition.