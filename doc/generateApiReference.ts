// SPDX-FileCopyrightText: 2025 sirinsidiator
//
// SPDX-License-Identifier: Artistic-2.0

import fs = require("fs");
import path = require("path");
import { exec } from "child_process";

const HOME_PATH = process.env["USERPROFILE"];
const VSCODE_EXTENSIONS_PATH = path.join(HOME_PATH, ".vscode", "extensions");
const extensions = fs.readdirSync(VSCODE_EXTENSIONS_PATH).filter((ext) => ext.startsWith("sumneko.lua")).map(ext => {
    const matches = RegExp(/sumneko\.lua-(\d+)\.(\d+)\.(\d+)-win32-x64/).exec(ext);
    if (!matches) {
        return null;
    }
    const [major, minor, patch] = matches.slice(1).map(Number);
    return { major, minor, patch, ext };
}).filter(ext => ext !== null).sort((a, b) => {
    if (a.major !== b.major) {
        return b.major - a.major;
    } else if (a.minor !== b.minor) {
        return b.minor - a.minor;
    } else {
        return b.patch - a.patch;
    }
}).map(ext => ext.ext);

const LS_SERVER_PATH = path.join(VSCODE_EXTENSIONS_PATH, extensions[0], "server", "bin", "lua-language-server.exe");
const PROJECT_PATH = path.resolve(process.cwd(), "../src");
const OUTPUT_PATH = path.resolve(process.cwd(), "./");
const PROJECT_URI = toFileUri(PROJECT_PATH);

function toFileUri(filePath: string) {
    filePath = filePath.replace(/^(\w:)/, (_, letter) => letter.toLowerCase());
    let uri = new URL(`file://${filePath}`).href + "/";
    return uri.replace(/file:\/\/\/(\w):/g, "file:///$1%3A");
}

const cmd = `${LS_SERVER_PATH} --doc=${PROJECT_PATH} --doc_out_path=${OUTPUT_PATH} --logpath=${OUTPUT_PATH}`;
console.log(cmd);

exec(cmd, (error, stdout, stderr) => {
    if (error) {
        console.error(error);
        return;
    }

    const jsonFile = path.join(OUTPUT_PATH, "doc.json");
    const content = fs.readFileSync(jsonFile, "utf-8");
    const data = JSON.parse(content);

    const entries = data.filter(isDefinedInAnyAllowedFile);

    const enums = new Map<string, DocEntry>();
    entries.forEach((entry) => {
        if (entry.defines[0].type === "doc.enum") {
            enums.set(entry.name, entry);
        } else {
            const parts = entry.name.split(".")[0];
            if (enums.has(parts)) {
                const enumEntry = enums.get(parts);
                enumEntry.fields.push(entry);
            }
        }
    });

    entries.sort((a, b) => {
        if (a.name === "LibHistoire") {
            return -1;
        } else if (b.name === "LibHistoire") {
            return 1;
        } else if (
            a.defines[0].type === "doc.enum" &&
            b.defines[0].type !== "doc.enum"
        ) {
            return 1;
        } else if (
            a.defines[0].type !== "doc.enum" &&
            b.defines[0].type === "doc.enum"
        ) {
            return -1;
        } else {
            return a.name.localeCompare(b.name);
        }
    });

    const DEPRECATED_FIELDS = new Map<string, string>();
    DEPRECATED_FIELDS.set(
        "CreateGuildHistoryListener",
        "This method will be removed in a future version. Use CreateGuildHistoryProcessor instead."
    );
    DEPRECATED_FIELDS.set(
        "Callbacks.HISTORY_RESCAN_STARTED",
        "Rescan no longer exists."
    );
    DEPRECATED_FIELDS.set(
        "Callbacks.HISTORY_RESCAN_ENDED",
        "Rescan no longer exists."
    );
    DEPRECATED_FIELDS.set(
        "Callbacks.LINKED_RANGE_LOST",
        "Use MANAGED_RANGE_LOST instead."
    );
    DEPRECATED_FIELDS.set(
        "Callbacks.LINKED_RANGE_FOUND",
        "Use MANAGED_RANGE_FOUND instead."
    );

    const output = [
        '; SPDX-FileCopyrightText: 2025 sirinsidiator',
        ';',
        '; SPDX-License-Identifier: Artistic-2.0',
        ''
    ];
    const processedSymbols = new Set<string>();
    entries.forEach((entry) => {
        if (entry.defines[0].type === "tablefield") {
            return;
        }

        output.push(`[SIZE="3"]${entry.name}[/SIZE]`);
        entry.fields.forEach((field) => {
            if (field.name === "StopReason" || field.name === "callback") {
                return;
            }
            if (
                !processedSymbols.has(field.name) &&
                (entry.name !== "GuildHistoryEventProcessor" ||
                    (field.type !== "setfield" && field.desc !== " @internal"))
            ) {
                output.push("[INDENT]");
                if (DEPRECATED_FIELDS.has(field.name)) {
                    output.push(
                        `[SIZE="2"][STRIKE]${field.name}[/STRIKE] [COLOR="DarkOrange"](deprecated)[/COLOR][/SIZE]`
                    );
                } else {
                    output.push(`[SIZE="2"]${field.name}[/SIZE]`);
                }
                output.push("[INDENT]");
                if (DEPRECATED_FIELDS.has(field.name)) {
                    output.push('[COLOR="DarkOrange"]');
                    output.push(DEPRECATED_FIELDS.get(field.name));
                    output.push("[/COLOR]");
                }
                if (field.extends?.view) {
                    output.push('[highlight="Lua"]');
                    output.push(field.extends.view);
                    output.push("[/highlight]");
                }
                if (field.desc) {
                    output.push(convertDescriptionToBBCode(field.desc));
                }
                output.push("[/INDENT]");
                output.push("[/INDENT]");
                processedSymbols.add(field.name);
            }
        });
    });

    const outPathTxt = path.join(process.cwd(), "api_reference.txt");
    fs.writeFileSync(outPathTxt, output.join("\n"));
});

const ALLOWED_FILES = {
    "api.lua": true,
    "guildHistoryCache/GuildHistoryEventProcessor.lua": true,
};
function isDefinedInAnyAllowedFile(entry: DocEntry) {
    return entry.defines.some((definition) => {
        return Object.keys(ALLOWED_FILES).some((allowedFile) => {
            return definition.file?.endsWith(allowedFile)
        });
    });
}

function convertDescriptionToBBCode(desc: string) {
    desc = desc.replace(
        /@\*(.*?)\* `(.+)` (.+)\n\n/g,
        "[I]@$1[/I] [B]$2[/B] $3\n"
    );
    desc = desc.replace(/@\*(.*?)\* `(.+)` (.+)/g, "[I]@$1[/I] [B]$2[/B] $3");

    if (desc.includes("See:")) {
        let parts = desc.split("See:");
        let output = [parts[0]];
        output.push("See:");
        output.push("[LIST]");
        parts[1].split("\n").forEach((reference) => {
            reference = reference.trim();
            reference = reference.replace(/^\*\s*/, "");
            reference = replaceUrls(reference);
            output.push(`[*]${reference}`);
        });
        output.push("[/LIST]");
        desc = output.join("\n");
    }

    return desc;
}

const URL_REPLACEMENTS = new Map<string, string>();
URL_REPLACEMENTS.set(
    PROJECT_URI,
    "https://github.com/sirinsidiator/ESO-LibHistoire/blob/master/src/"
);

const ESO_SOURCE_LINKS = new Map<string, string>();
ESO_SOURCE_LINKS.set(
    "ZO_GuildHistoryEventData_Base",
    "https://github.com/esoui/esoui/blob/master/esoui/ingame/guildhistory/guildhistory_data.lua#L49"
);

function replaceUrls(markdown: string) {
    let matches = markdown.match(/\[(.*)\]\((.*)\)/);
    if (matches) {
        let url = matches[2];
        URL_REPLACEMENTS.forEach((value, key) => {
            if (url.startsWith(key)) {
                url = url.replace(key, value);
                url = url.replace(/#(\d+)#\d+$/, "#L$1");
            }
        });
        return `[URL='${url}']${matches[1]}[/URL]`;
    } else {
        matches = markdown.match(/~(.*)~/);
        if (matches) {
            let label = matches[1];
            if (ESO_SOURCE_LINKS.has(label)) {
                return `[URL='${ESO_SOURCE_LINKS.get(label)}']${label}[/URL]`;
            }
        }
        return markdown;
    }
}

interface DocEntry {
    defines: DocEntryDefines[];
    fields: DocEntryFields[];
    name: string;
    type: string;
}

interface DocEntryFields {
    desc: string;
    name: string;
    type: string;
    extends: DocEntryExtends;
}

interface DocEntryDefines {
    extends: DocEntryExtends;
    file: string;
    finish: number;
    start: number;
    type: string;
}

interface DocEntryExtends {
    finish: number;
    start: number;
    type: string;
    view: string;
}
