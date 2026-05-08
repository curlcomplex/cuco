-- name: token_semantics_test
notation = [[
~16

-- Test rest token (.) = musical silence
test_rest = [c4 . d4 .]

-- Test sustain token (_) = continue previous note
test_sustain = [c4 _ d4 _]

-- Test inherit token (-) = inherit previous note/chord 
test_inherit = [c4 d4 - e4]

-- Test mixed usage
test_mixed = [c4 _ . - d4]

@test_rest = test_rest
@test_sustain = test_sustain  
@test_inherit = test_inherit
@test_mixed = test_mixed
]]

expected = {
  -- Should generate some MIDI events from the test sequences
  -- The exact number depends on how rest/sustain/inherit are processed
}
