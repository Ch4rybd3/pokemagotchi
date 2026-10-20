# Third-party notices

Pokemagotchi bundles data and images from the projects below. They keep their own
licenses; the MIT license in [LICENSE](LICENSE) covers only Pokemagotchi's own code.

## pokemon-colorscripts

`sprites/regular`, `sprites/shiny` and `sprites/silhouette` (derived) come from
<https://gitlab.com/phoneybadger/pokemon-colorscripts>.

```
MIT License

Copyright (c) 2021 phoneybadger

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in the
Software without restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

Those sprites are based on PokéSprite (<https://github.com/msikma/pokesprite>, MIT).

## PokeAPI

`Dex.js`, `Info.js`, `Items.js` (names), `Moves.js` and `Battle.js` are generated from
PokeAPI (<https://github.com/PokeAPI/pokeapi>, BSD 3-Clause License).
Item sprites in `sprites/items` come from <https://github.com/PokeAPI/sprites>,
except `apple.png` and `big-apple.png`, drawn for Pokemagotchi, and the PokéSprite
ones listed below.

## Pokémon Showdown

`Showdown.mjs` is built by `tools/gen-showdown.mjs` from Pokémon Showdown
(<https://github.com/smogon/pokemon-showdown>): its battle simulator and data,
bundled into one module. `BattleText.mjs` uses its battle texts. The damage
formula in `Combat.js` follows the order of operations and rounding of the
Pokémon Showdown damage calculator (<https://github.com/smogon/damage-calc>, MIT).

```
The MIT License (MIT)

Copyright (c) 2011-2026 Guangcong Luo and other contributors http://pokemonshowdown.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

The generic trainers of `Trainers.js` are built from Pokémon Showdown's Random
Battle sets (same license).

## Pokémon Radical Red

The Radical Red Tower's trainers in `Trainers.js` come from the Pokémon Radical
Red 4.1 trainer data (Normal mode) dumped by Rudo2204, based on luckytyphlosion's
dump (<https://gist.github.com/Rudo2204/7f9e4a3ceaf077d623d3c37b1f921601>).
Pokémon Radical Red is a romhack by soupercell. Its teams are used here with
credit, in a non-commercial fan project; a few of its own moves, Mega Stones and
forms are replaced by the closest official ones.

## Pixelify Sans

`fonts/PixelifySans.ttf` is Pixelify Sans by The Pixelify Sans Project Authors
(<https://github.com/eifetx/Pixelify-Sans>), under the SIL Open Font License 1.1
(`fonts/OFL.txt`).

## PokéSprite (item sprites)

`sprites/items/heavy-duty-boots.png`, `eject-pack.png`, `throat-spray.png`,
`room-service.png` and `ability-patch.png` come from PokéSprite
(<https://github.com/msikma/pokesprite>, MIT License).

## Pokémon

Pokémon names, images and game data are © Nintendo / Creatures Inc. /
GAME FREAK inc. This is an unofficial, non-commercial fan project. It is not
affiliated with or endorsed by Nintendo, Game Freak, Creatures Inc. or
The Pokémon Company.
