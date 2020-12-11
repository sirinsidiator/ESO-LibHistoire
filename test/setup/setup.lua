package.path = package.path .. ';../src/?.lua'
require 'setup/mockups'
require 'Codec'

function specify(desc, test)
    it(desc, function(done)
        async()
        test(done)
        resolveTimeouts()
    end)
end