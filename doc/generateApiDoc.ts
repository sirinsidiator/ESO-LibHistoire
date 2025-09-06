// SPDX-FileCopyrightText: 2025 sirinsidiator
//
// SPDX-License-Identifier: Artistic-2.0

const PROJECT_PATH = "../src";
const INCLUDED_FILES = new Set([
    "api.lua",
    "guildHistoryCache/GuildHistoryEventProcessor.lua",
]);

import fs = require("fs");
import path = require("path");

const output = [
    `-- SPDX-FileCopyrightText: 2025 sirinsidiator
--
-- SPDX-License-Identifier: Artistic-2.0

--- @meta LibHistoire

--- @class LibHistoire
local LibHistoire = {}

--- @class GuildHistoryEventProcessor
local GuildHistoryEventProcessor = {}

--- @class GuildHistoryLegacyEventListener
local GuildHistoryLegacyEventListener = {}`,
];
INCLUDED_FILES.forEach((file) => {
    const filePath = path.join(PROJECT_PATH, file);
    const content = fs.readFileSync(filePath, "utf8");
    const lines = content.split("\n");

    let isPublicPart = false;
    let inEnum = false;
    let inFunction = false;
    lines.forEach((line) => {
        if (!isPublicPart) {
            if (line.startsWith("--- public api")) {
                isPublicPart = true;
            }
            return;
        } else if (inEnum) {
            if (line.trim() === "}") {
                inEnum = false;
            } else if (line.trim().endsWith(",")) {
                line = line.replace(/ = .+/, ' = "",');
            }
            output.push(line);
        } else if (inFunction) {
            if (line.startsWith("end")) {
                inFunction = false;
            }
        } else {
            if (line.startsWith("lib.")) {
                line = line.replace("lib.", "LibHistoire.");
            } else if (line.startsWith("internal:Initialize()")) {
                return;
            } else if (line.startsWith("--- @enum")) {
                inEnum = true;
            } else if (line.startsWith("function")) {
                inFunction = true;
                line = line.replace("lib:", "LibHistoire:");
                output.push(line.trim() + " end");
                return;
            } else if (line.startsWith("local function")) {
                inFunction = true;
                return;
            }

            if (line.trim() === "" || !line.startsWith("    ")) {
                output.push(line);
            }
        }
    });
});

// write the output to a file
const outputFile = path.join(PROJECT_PATH, "api.doc.lua");
fs.writeFileSync(outputFile, output.join("\n"));
