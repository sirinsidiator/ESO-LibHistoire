require 'setup/setup'

local function testEncodeItemLink(input, expected)
    it(input, function()
        local encoded = LibHistoire.internal.EncodeValue("itemLink", input)
        assert.are.equal(expected, encoded)
    end)
end

local function testDecodeItemLink(input, expected)
    it(input, function()
        local encoded = LibHistoire.internal.DecodeValue("itemLink", input)
        assert.are.equal(expected, encoded)
    end)
end

describe("encode", function()
    describe("item link", function()
        local testCases = {
            { input = "|H0:item:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", expected = "1<20>" },
            { input = "|H0:item:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0|h|h", expected = "0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0" },
            { input = "|H0:item:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1|h|h", expected = "1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1" },
            { input = "|H0:item:45358:365:50:0:0:0:0:0:0:0:0:0:0:0:0:3:0:0:0:10000:0|h|h", expected = "bNA#5T#O<12>3<3>2Bi#0" },
            { input = "|H0:item:97290:363:50:0:0:0:0:0:0:0:0:0:0:0:0:6:0:0:0:0:0|h|h", expected = "pjc#5R#O<12>6<5>" },
            { input = "|H0:item:121533:6:1:0:0:0:41:190:5:408:25:5:0:0:0:0:0:0:0:0:1152000|h|h", expected = "vCd#6#1<3>F#34#5#6A#p#5<8>4PGE" },
        }

        for i = 1, #testCases do
            local case = testCases[i]
            testEncodeItemLink(case.input, case.expected)
        end
    end)
end)

describe("decode", function()
    describe("item link", function()
        local testCases = {
            { input = "1<20>", expected =  "|H0:item:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h" },
            { input = "0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0", expected = "|H0:item:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0|h|h" },
            { input = "1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1#0#1", expected = "|H0:item:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1:0:1|h|h" },
            { input = "bNA#5T#O<12>3<3>2Bi#0", expected = "|H0:item:45358:365:50:0:0:0:0:0:0:0:0:0:0:0:0:3:0:0:0:10000:0|h|h" },
            { input = "pjc#5R#O<12>6<5>", expected = "|H0:item:97290:363:50:0:0:0:0:0:0:0:0:0:0:0:0:6:0:0:0:0:0|h|h" },
            { input = "bMD#4Y#O#0#0#0#0#0#0#0#0#0#0#0#0#8#0#0#0#0#0", expected = "|H0:item:45299:308:50:0:0:0:0:0:0:0:0:0:0:0:0:8:0:0:0:0:0|h|h" },
            { input = "vCd#6#1<4>F#34#5#6A#p#5<9>4PGE", expected = "|H0:item:121533:6:1:0:0:0:41:190:5:408:25:5:0:0:0:0:0:0:0:0:1152000|h|h" },
            { input = "vCd#6#1<3>F#34#5#6A#p#5<8>4PGE", expected = "|H0:item:121533:6:1:0:0:0:41:190:5:408:25:5:0:0:0:0:0:0:0:0:1152000|h|h" },
        }

        for i = 1, #testCases do
            local case = testCases[i]
            testDecodeItemLink(case.input, case.expected)
        end
    end)
end)
