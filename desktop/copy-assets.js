// Pull the current game + music from the repo root into the app folder before packaging.
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
fs.copyFileSync(path.join(root, "index.html"), path.join(__dirname, "index.html"));
fs.cpSync(path.join(root, "audio"), path.join(__dirname, "audio"), { recursive: true });
console.log("Copied index.html and audio/ into desktop/");
