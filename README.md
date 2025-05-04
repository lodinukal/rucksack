# Rucksack

Inspired by [rokit](https://github.com/rojo-rbx/rokit), this is a simple dependency manager. Think npx degit but you can specify a list of files and a folder to copy them to.

## Installation

### Rokit (recommended) 
```
rokit add lodinukal/rucksack
```

### Github releases
Obtain the latest release from [here](https://github.com/lodinukal/rucksack/releases/latest) and place it in your PATH.

### Usage
1. Create `rucksack.toml` file in the root of the project. 
2. Add dependencies in the form of `name = "git [git url]"`. 
3. Run `rucksack install`.
4. If you need to clean up the dependencies, run `rucksack clean`.

## TODO:
- [ ] make the exe traverse the parent folders to find the rucksack.toml file
- [ ] make the installation folder relative to the rucksack.toml file
- [ ] support tar files
- [ ] support zip files
- [ ] support git submodules
- [ ] call rucksack install on all dependencies in the rucksack.toml file (maybe?)