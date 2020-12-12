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
            { input = "|H0:item:36569:2:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:100000:0|h|h", expected = "9vP#2<17>q0U#0" },
            { input = "|H0:item:45330:365:50:0:0:0:0:0:0:0:0:0:0:0:0:9:0:0:0:0:0|h|h", expected = "bN8#5T#O<12>9<5>" },
            { input = "|H0:item:45357:308:50:0:0:0:0:0:0:0:0:0:0:0:0:4:0:0:0:10000:0|h|h", expected = "bNz#4Y#O<12>4<3>2Bi#0" },
            { input = "|H0:item:54171:32:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", expected = "e5J#w#1<18>" },
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
            { input = "e8r#4Y#O#0#0#0#0#0#0#0#0#0#0#0#0#A#0#0#0#0#ztvD", expected = "|H0:item:54339:308:50:0:0:0:0:0:0:0:0:0:0:0:0:36:0:0:0:0:8454917|h|h" },
            { input = "e8r#4Y#O<12>A<4>ztvD", expected = "|H0:item:54339:308:50:0:0:0:0:0:0:0:0:0:0:0:0:36:0:0:0:0:8454917|h|h" },
            { input = "e8r#4Y#O<13>A<5>ztvD", expected = "|H0:item:54339:308:50:0:0:0:0:0:0:0:0:0:0:0:0:36:0:0:0:0:8454917|h|h" },
            { input = "9vP#2<17>q0U#0", expected = "|H0:item:36569:2:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:100000:0|h|h" },
            { input = "bN8#5T#O<13>9<5>", expected = "|H0:item:45330:365:50:0:0:0:0:0:0:0:0:0:0:0:0:9:0:0:0:0:0|h|h" },
            { input = "bNz#4Y#O<13>4<4>2Bi#", expected = "|H0:item:45357:308:50:0:0:0:0:0:0:0:0:0:0:0:0:4:0:0:0:10000:0|h|h" },
            { input = "e5J#w#1<34>0", expected = "|H0:item:54171:32:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h" },
        }

        for i = 1, #testCases do
            local case = testCases[i]
            testDecodeItemLink(case.input, case.expected)
        end
    end)
end)
