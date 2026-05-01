const fs = require("fs");
const path = require("path");

// 👇 change this if script is outside
const baseDir = path.join(__dirname, "supabase/functions");

const outputFile = path.join(baseDir, "all_functions.txt");

let output = "";

// read all folders
const folders = fs.readdirSync(baseDir);

folders.forEach((folder) => {
  const folderPath = path.join(baseDir, folder);

  if (fs.statSync(folderPath).isDirectory()) {
    const indexFile = path.join(folderPath, "index.ts");

    if (fs.existsSync(indexFile)) {
      const content = fs.readFileSync(indexFile, "utf-8");

      output += `and this is filename: ${folder}/index.ts\n`;
      output += content + "\n\n";
    }
  }
});

fs.writeFileSync(outputFile, output);

console.log("✅ Done! File created:", outputFile);