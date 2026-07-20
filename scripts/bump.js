const fs = require('fs');
const newVersion = process.argv[2];

if (!newVersion) {
  console.error("No version provided");
  process.exit(1);
}

const file = 'moon.mod.json';
const data = JSON.parse(fs.readFileSync(file, 'utf8'));
data.version = newVersion;
fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
console.log(`Updated ${file} to version ${newVersion}`);
