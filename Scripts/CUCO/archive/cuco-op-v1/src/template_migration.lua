-- Template Migration Utility
-- Migrates hardcoded templates from main file to script library system

local template_migration = {}

-- Extract hardcoded templates - this mirrors the structure from CUCO OP.lua
local function get_hardcoded_templates()
    return {
        -- Basic Notation
        {
            name = "Basic Sequence",
            category = "Basic Notation", 
            code = "~16 @c.major\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        {
            name = "Grid 16th Notes",
            category = "Basic Notation",
            code = "~16\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        {
            name = "Grid 8th Notes", 
            category = "Basic Notation",
            code = "~8\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        {
            name = "Scale Context",
            category = "Basic Notation",
            code = "~16 @f#.minor\nmelody = [c4 d4 e4 f4]\nch1 = melody"
        },
        
        -- Chord Progressions
        {
            name = "Chord Progress maj7-min7",
            category = "Chord Progressions",
            code = "~16 @c.major\nprog = [c4.maj7 d4.min7 g4.7 c4.maj7]\nch1 = prog"
        },
        {
            name = "Jazz Chords",
            category = "Chord Progressions", 
            code = "~8\njazz = [c4.maj7 a4.min7 d4.min7 g4.7]\nch1 = jazz"
        },
        {
            name = "Manual Chord Notes",
            category = "Chord Progressions",
            code = "~16\nchord1 = (c4 e4 g4)\nchord2 = (d4 f4 a4)\nseq = [chord1 chord2]\nch1 = seq"
        },
        
        -- Rhythm Patterns
        {
            name = "Sustain Pattern",
            category = "Rhythm Patterns",
            code = "~16\ndrums = [- _ - _]*4\nch10 = drums"
        },
        {
            name = "Multi-Channel",
            category = "Rhythm Patterns", 
            code = "~16\nkick = [- _ _ _]*4\nsnare = [_ - _ -]*4\nch1 = kick\nch2 = snare"
        },
        {
            name = "Rest Pattern",
            category = "Rhythm Patterns",
            code = "~16\npattern = [c4 . d4 . e4 . f4 .]\nch1 = pattern"
        },
        
        -- Processors
        {
            name = "Vel Linear Envelope", 
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !vel(linear,60,120)\nch1 = melody"
        },
        {
            name = "Transpose Up +7",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !transpose(7)\nch1 = melody"
        },
        {
            name = "Retrograde",
            category = "Processors", 
            code = "~16\nmelody = [c4 d4 e4 f4] !retro()\nch1 = melody"
        },
        {
            name = "Random Velocity",
            category = "Processors",
            code = "~16\nmelody = [c4 d4 e4 f4] !rand(uniform,velocity,50,100)\nch1 = melody"
        },
        
        -- Ambitus Functions
        {
            name = "Ambitus Transpose",
            category = "Ambitus Functions",
            code = "~16\nmelody = [c4 d4 e4 f4 g4] !ambitus(c3,c5)\nch1 = melody"
        },
        {
            name = "Ambitus Filter",
            category = "Ambitus Functions", 
            code = "~16\nmelody = [c2 d4 e4 f4 g6] !ambitus_filter(c3,c5)\nch1 = melody"
        }
    }
end

-- Map template categories to folder IDs
local category_to_folder = {
    ["Basic Notation"] = "basic_notation",
    ["Chord Progressions"] = "chord_progressions", 
    ["Rhythm Patterns"] = "rhythm_patterns",
    ["Processors"] = "processors",
    ["Ambitus Functions"] = "ambitus_functions",
    ["Existing Tests"] = "existing_tests",
    ["Debug Tests (Broken)"] = "debug_tests"
}

function template_migration.migrate_templates(script_library_module)
    local library = script_library_module.load_library()
    
    -- Create template subfolders
    local template_folder = nil
    for _, folder in ipairs(library.folders) do
        if folder.id == "templates" then
            template_folder = folder
            break
        end
    end
    
    if not template_folder then
        error("Templates folder not found in library")
    end
    
    -- Clear existing template children
    template_folder.children = {}
    
    -- Group templates by category
    local templates_by_category = {}
    local templates = get_hardcoded_templates()
    
    for _, template in ipairs(templates) do
        local category = template.category
        if not templates_by_category[category] then
            templates_by_category[category] = {}
        end
        table.insert(templates_by_category[category], template)
    end
    
    -- Create category subfolders and add scripts
    local category_folders = {}
    for category, category_templates in pairs(templates_by_category) do
        -- Create category folder
        local category_id = category_to_folder[category] or category:lower():gsub("%s+", "_")
        local category_folder = {
            id = category_id,
            name = category,
            type = "template_category", 
            expanded = false,
            children = {}
        }
        
        -- Add scripts to category
        for _, template in ipairs(category_templates) do
            local script_id = script_library_module.add_script(library, category_id, template.name, template.code)
            table.insert(category_folder.children, script_id)
        end
        
        category_folders[category_id] = category_folder
        table.insert(template_folder.children, category_id)
    end
    
    -- Add category folders to library
    library.template_categories = category_folders
    
    -- Save the updated library
    script_library_module.save_library(library)
    
    return library
end

return template_migration