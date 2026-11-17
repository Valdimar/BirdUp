-- BirdUp: digging rewards by zone, and the REWARDS window that shows them.
--
-- Data: BG-Wiki, "Category:Chocobo Digging" > "Digging Rewards by Zone"
-- (https://www.bg-wiki.com/ffxi/Category:Chocobo_Digging), November 2026.
-- Each zone is one line: "Item:CODE, Item:CODE(condition), ...".
-- Rarity codes, most to least common: VC very common, C common, U uncommon,
-- R rare, VR very rare, SR super rare, ? not listed on the wiki.
-- To update a zone, edit its line below; nothing else needs to change.
--
-- ctx gives: solid(w, h, a, r, g, b), mk_text(size), C (panel colors),
-- log(msg), found(zone_name) -> {item = count} (your digs there, all ranks)

local REWARDS = {
    {"West Sarutabaruta", "Gysahl Greens:C, Chamomile:R, Lauan Log:R, Little Worm:R, Pebble:R, Moko Grass:R, Ginger:R, Insect Wing:R, Yagudo Feather:R, Napa:VR, Saruta Cotton:VR, Bird Feather:VR, Ebony Log:VR, Tree Cuttings:VR, Rosewood Log:SR, Heavy Metal:SR"},
    {"East Sarutabaruta", "Gysahl Greens:C, Chamomile:R, Lauan Log:R, Pebble:R, Ginger:R, Insect Wing:R, Yagudo Feather:R, Saruta Cotton:R, Papaka Grass:R, Napa:VR, Bird Feather:VR, Ebony Log:VR, Green Rock:VR, Rosewood Log:SR, Heavy Metal:SR"},
    {"West Ronfaure", "Gysahl Greens:C, Chamomile:R, Ginger:R, Arrowwood Log:R, Little Worm:R, Ash Log:R, Acorn:R, Chocobo Fthr.:R, Moko Grass:R, Maple Log:R, Napa:R, Chestnut:VR, Vegetable Seeds:VR, Chestnut Log:VR, Mistletoe:VR, Heavy Metal:SR"},
    {"East Ronfaure", "Gysahl Greens:C, Chamomile:R, Ginger:R, Arrowwood Log:R, Little Worm:R, Ash Log:R, Acorn:R, Chocobo Fthr.:R, Moko Grass:R, Maple Log:R, Napa:R, Chestnut:VR, Vegetable Seeds:VR, Chestnut Log:VR, Mistletoe:VR, King Truffle:VR, Heavy Metal:SR"},
    {"South Gustaberg", "Gysahl Greens:C, Bird Feather:R, Bone Chip:R, Chamomile:R, Ginger:R, Grain Seeds:R, Insect Wing:R, Little Worm:R, Lizard Molt:R, Mtl. Beastcoin:R, Napa:R, Pebble:R, Rock Salt:R, White Rock:VR, Coin of Decay:SR, Heavy Metal:SR"},
    {"North Gustaberg", "Gysahl Greens:C, Bird Feather:R, Bone Chip:R, Chamomile:R, Fish Scales:R, Ginger:R, Insect Wing:R, Little Worm:R, Lizard Molt:R, Napa:R, Pebble:R, Cactus Stems:VR, Darksteel Ore:VR, Mtl. Beastcoin:VR, Mythril Ore:VR, Heavy Metal:SR"},
    {"La Theine Plateau", "Gysahl Greens:C, Yellow Ginseng:C, Chamomile:U, Arrowwood Log:R, Chocobo Fthr.:R, Ginger:R, Little Worm:R, Napa:R, Pebble:R, Tin Ore:R, Tree Cuttings:R, Wildgrass Seeds:R, Yew Log:R, Zinc Ore:R, Chestnut Log:VR, Dried Marjoram:VR, Cactus Stems:VR, Coin of Glory:SR, Heavy Metal:SR"},
    {"Valkurm Dunes", "Seashell:C, Black C. Feather:U, Bone Chip:U, Phoenix Feather:U, Fish Scales:R, Giant Femur:R, H.Q. Pugil Scale:R, Lizard Molt:R, Lugworm:R, Red Moko Grass:R, Shall Shell:R, Shell Bug:R, Spider Web:R, Titanictus Shell:R, Turtle Shell:R, Blue Rock:VR, Demon Horn:VR, Demon Skull:VR, Dragon Scales:VR, G. Bird Plume:VR, Wyvern Scales:VR, Coin of Decay:SR, O. Bronzepiece:SR, T. Whiteshell:SR"},
    {"Konschtat Highlands", "Black C. Feather:U, Phoenix Feather:U, Bone Chip:R, Elm Log:R, Fish Scales:R, Flint Stone:R, Lizard Molt:R, Pebble:R, Red Moko Grass:R, Spider Web:R, Zinc Ore:R, Bird Feather:VR, G. Bird Plume:VR, Coin of Birth:SR, Heavy Metal:SR, Mtl. Beastcoin:SR"},
    {"Tahrongi Canyon", "Beastcoin:C, Bone Chip:U, Seashell:U, Silver Beastcoin:U, Fish Scales:R, Gold Beastcoin:R, H.Q. Pugil Scale:R, Insect Wing:R, Mtl. Beastcoin:R, Pebble:R, Tin Ore:R, Titanictus Shell:R, Turtle Shell:R, Yagudo Feather:R, Demon Horn:VR, Demon Skull:VR, Dragon Scales:VR, Giant Femur:VR, Gold Ore:VR, Red Rock:VR, Coin of Adv.:SR, Heavy Metal:SR, Plt. Beastcoin:SR, Wyvern Scales:SR"},
    {"Buburimu Peninsula", "Black C. Feather:U, Phoenix Feather:U, Seashell:U, Bird Feather:R, Bone Chip:R, Demon Skull:R, Fish Scales:R, Giant Femur:R, H.Q. Pugil Scale:R, Lugworm:R, Red Moko Grass:R, Shall Shell:R, Shell Bug:R, Spider Web:R, Tin Ore:R, Titanictus Shell:R, Turtle Shell:R, Demon Horn:VR, Dragon Scales:VR, G. Bird Plume:VR, Platinum Ore:VR, 1 Byne Bill:SR, Coin of Birth:SR, Coin of Decay:SR, Heavy Metal:SR, Wyvern Scales:SR"},
    {"Jugner Forest", "Arrowwood Log:C, Acorn:R, Holly Log:R, Little Worm:R, Maple Log:R, Oak Log:R, Willow Log:R, Yew Log:R, Elm Log:VR, Lacquer Tree Log:VR, Mahogany Log:VR, Mistletoe:VR, Rosewood Log:VR, Ancient Lumber:SR, Scream Fungus:SR, Coin of Birth:SR, Heavy Metal:SR"},
    {"Pashhow Marshlands", "Yellow Ginseng:C, Black Rock:R, Insect Wing:R, Lizard Molt:R, Pebble:R, Silver Ore:R, Wildgrass Seeds:R, Mtl. Beastcoin:VR, Tree Cuttings:VR, Turtle Shell:VR, Willow Log:VR, Cactus Stems:SR, Coin of Adv.:SR, Heavy Metal:SR, Petrified Log:SR, Puffball:SR"},
    {"Meriphataud Mountains", "Flint Stone:VC, Silver Ore:U, Iron Ore:U, Kopparnickel Ore:U, Copper Ore:R, Giant Femur:R, Insect Wing:R, Lizard Molt:R, Mythril Ore:R, Pebble:R, Darksteel Ore:VR, Gold Beastcoin:VR, Adaman Ore:SR, Aluminum Ore:SR, Coin of Adv.:SR, Gold Ore:SR, Heavy Metal:SR"},
    {"Batallia Downs", "Yellow Ginseng:C, Beastcoin:U, Silver Beastcoin:U, Bird Feather:R, Bone Chip:R, Copper Ore:R, Flint Stone:R, Gold Beastcoin:R, Iron Ore:R, Mtl. Beastcoin:R, Pebble:R, Red Jar:R, Wildgrass Seeds:R, Plt. Beastcoin:VR, Purple Rock:VR, Tree Cuttings:VR, Black C. Feather:SR, Cactus Stems:SR, Coin of Adv.:SR, Heavy Metal:SR, Reishi Mushroom:SR"},
    {"Rolanberry Fields", "Beastcoin:U, Silver Beastcoin:U, Flint Stone:U, Sleepshroom:U, Woozyshroom:U, Danceshroom:R, Gold Beastcoin:R, Insect Wing:R, Little Worm:R, Mtl. Beastcoin:R, Pebble:R, Red Jar:R, Sage:R, Coral Fungus:VR, Puffball:VR, Reishi Mushroom:VR, Coin of Glory:SR, Deathball:SR, Heavy Metal:SR, Orichalcum Ore:SR, Plt. Beastcoin:SR"},
    {"Sauromugue Champaign", "Beastcoin:U, Silver Beastcoin:U, Bone Chip:U, Fish Scales:R, Flint Stone:R, Gold Beastcoin:R, H.Q. Pugil Scale:R, Insect Wing:R, Iron Ore:R, Lizard Molt:R, Mtl. Beastcoin:R, Pebble:R, Seashell:R, Turtle Shell:R, Black C. Feather:VR, Demon Horn:VR, Demon Skull:VR, Dragon Scales:VR, Red Jar:VR, Titanictus Shell:VR, Wyvern Scales:VR, Coin of Glory:SR, Heavy Metal:SR, Plt. Beastcoin:SR"},
    {"Carpenters' Landing", "Arrowwood Log:U, Little Worm:U, Acorn:R, Holly Log:R, Maple Log:R, Oak Log:R, Willow Log:R, Yew Log:R, Ancient Lumber:VR, Ebony Log:VR, Elm Log:VR, Mistletoe:VR, Rosewood Log:VR, Scream Fungus:VR, King Truffle:VR, Lacquer Tree Log:VR, Mahogany Log:VR"},
    {"Bibiki Bay", "Black C. Feather:U, Seashell:U, Bird Feather:R, Bone Chip:R, Fish Scales:R, Giant Femur:R, Lugworm:R, Phoenix Feather:R, Red Moko Grass:R, Shall Shell:R, Tin Ore:R, Titanictus Shell:R, Turtle Shell:R, Demon Horn:VR, Demon Skull:VR, Dragon Scales:VR, G. Bird Plume:VR, H.Q. Pugil Scale:VR, Shell Bug:VR, Spider Web:VR, Wyvern Scales:VR, Coin of Birth:SR, Coral Fragment:SR, Heavy Metal:SR, Platinum Ore:SR"},
    {"Purgonorgo Isle", "Black C. Feather:U, Phoenix Feather:U, Seashell:U, Bird Feather:R, Bone Chip:R, Giant Femur:R, Lugworm:R, Red Moko Grass:R, Shall Shell:R, Demon Horn:R, Fish Scales:R, H.Q. Pugil Scale:R, Tin Ore:R, Titanictus Shell:R, Demon Skull:VR, Dragon Scales:VR, G. Bird Plume:VR, Shell Bug:VR, Spider Web:VR, Turtle Shell:VR, Wyvern Scales:VR, Heavy Metal:SR, Platinum Ore:SR"},
    {"Attohwa Chasm", "Yellow Ginseng:VC, Bone Chip:U, Kopparnickel Ore:U, Silver Ore:U, Antlion Jaw:R, Iolite:R, Iron Ore:R, Mythril Ore:R, Pebble:R, Sulfur:R, Wildgrass Seeds:R, Cactus Stems:VR, Darksteel Ore:VR, Phoenix Feather:VR, Red Gravel:VR, Tree Cuttings:VR, Venom Dust:VR, Heavy Metal:SR, Titanium Ore:SR"},
    {"Beaucedine Glacier", "Beastcoin:U, Silver Beastcoin:U, Beaugreens:R, Blk. Tiger Fang:R, Gigas Necklace:R, Ice Cluster:R(double weather), Lugworm:R, Mtl. Beastcoin:R, Pebble:R, Petrified Log:R, Gold Beastcoin:VR, Ordrynite:VR, Platinum Leaf:VR"},
    {"Xarcabard", "Beastcoin:U, Silver Beastcoin:U, Ahriman Lens:R, Bone Chip:R, Frost Turnip:R, Gigas Socks:R, Mtl. Beastcoin:R, Old Arrow:R, Pebble:R, Demon Skull:VR, Gold Beastcoin:VR, Gold Ore:VR, Petrified Log:VR, Garnet:SR, Onyx:SR, Plt. Beastcoin:SR, Relic Iron:SR"},
    {"Uleguerand Range", "Beastcoin:U, Iron Ore:U, Kopparnickel Ore:U, Mythril Ore:U, Silver Beastcoin:U, Silver Ore:R, Blk. Tiger Fang:R, Buffalo Horn:R, Ice Cluster:R(double weather), Pebble:R, Rabbit Hide:R, Darksteel Ore:VR, Demon Horn:VR, Flame Geode:VR, Gold Beastcoin:VR, Plt. Beastcoin:VR, Snow Geode:VR, Heavy Metal:SR, Mammoth Tusk:SR"},
    {"Qufim Island", "Pebble:C, Lightning Crystal:C, Bone Chip:U, Silica:U, Yellow Rock:U, Zinc Ore:U, Red Jar:U, Beastcoin:U, Silver Beastcoin:U, Coral Fragment:R, Magic Pot Shard:R, Mtl. Beastcoin:R, Sparkling Stone:VR, Tin Ore:VR, Gold Beastcoin:VR, Elemental Ore:VR(elemental weather + moon), T. Whiteshell:SR, O. Bronzepiece:SR, 1 Byne Bill:SR, Coin of Ruin:SR, Heavy Metal:SR, Plt. Beastcoin:SR, Bkn. Single Rod:SR, Bkn. Clothespole:SR, Bkn. Mithran Rod:SR, Bkn. Willow Rod:SR, Bkn. Fast. Rod:SR, Bkn. Carbon Rod:SR, Bkn. Hume Rod:SR, Bkn. Halcyon Rod:SR"},
    {"Behemoth's Dominion", "Bat Wing:R, Bone Chip:R, Giant Femur:R, Lightning Cluster:R, Pebble:R, Silver Ore:R, Behemoth Hide:VR, Bloodthread:VR, Darksteel Ore:VR, Granite:VR, Burning Memory:SR, Conquest Points:SR, Heavy Metal:SR"},
    {"Behemoth's Dominion (Burrow)", "Yellow Ginseng:VC, Wildgrass Seeds:R, Cactus Stems:VR, Tree Cuttings:VR"},
    {"Behemoth's Dominion (Bore)", "Flint Stone:VC, Darksteel Ore:VR, Adaman Ore:SR, Aluminum Ore:SR, Gold Ore:SR, Platinum Ore:SR, Orichalcum Ore:?"},
    {"The Sanctuary of Zi'Tah", "Silver Beastcoin:C, Arrowwood Log:U, Beastcoin:U, Pebble:U, Yew Log:U, Bone Chip:R, Elm Log:R, Moko Grass:R, Mtl. Beastcoin:R, Oak Log:R, Ebony Log:VR, Gold Beastcoin:VR, Green Rock:VR(weather), Mahogany Log:VR, Rosewood Log:VR, Translucent Rock:VR, Ancient Lumber:SR, Coin of Decay:SR, Lacquer Tree Log:SR, Petrified Log:SR, Plt. Beastcoin:SR"},
    {"Eastern Altepa Desert", "Flint Stone:VC, Bone Chip:U, Fruit Seeds:R, Giant Femur:R, Grain Seeds:R, Herb Seeds:R, Pebble:R, Silver Ore:R, Vegetable Seeds:R, Wildgrass Seeds:R, Wyvern Scales:R, Zinc Ore:R, Aluminum Ore:VR, Cactus Stems:VR, Mythril Ore:VR, Orichalcum Ore:VR, Platinum Ore:VR, Tree Cuttings:VR, Gold Ore:SR, Heavy Metal:SR, Phil. Stone:SR"},
    {"Western Altepa Desert", "Bone Chip:C, Black C. Feather:U, Giant Femur:U, Phoenix Feather:U, Coral Fragment:R, Fish Scales:R, H.Q. Pugil Scale:R, Iron Ore:R, Pebble:R, Red Moko Grass:R, Seashell:R, Turtle Shell:R, Zinc Ore:R, Darksteel Ore:VR, Demon Horn:VR, Demon Skull:VR, Dragon Scales:VR, G. Bird Plume:VR, Gold Ore:VR, Phil. Stone:VR, Spider Web:VR, Titanictus Shell:VR, Wyvern Scales:VR, Heavy Metal:SR"},
    {"Cape Teriggan", "Arrowwood Log:U, Black C. Feather:U, Phoenix Feather:U, Bone Chip:R, Elm Log:R, Fish Scales:R, Lizard Molt:R, Lugworm:R, Manticore Hair:R, Oak Log:R, Red Moko Grass:R, Seashell:R, Shall Shell:R, Spider Web:R, Ebony Log:VR, G. Bird Plume:VR, Lacquer Tree Log:VR, Light Chest:VR, Mahogany Log:VR, Mythril Ore:VR, Phil. Stone:VR, Rosewood Log:VR, Shadow Geode:VR, Yew Log:VR, Ancient Lumber:SR"},
    {"Valley of Sorrows", "Black C. Feather:U, Kopparnickel Ore:U, Phoenix Feather:U, Silver Ore:U, Bone Chip:R, Fish Scales:R, Giant Femur:R, Iron Ore:R, Kitron:R, Lugworm:R, Mythril Ore:R, Red Moko Grass:R, Seashell:R, Spider Web:R, Turtle Shell:R, Darksteel Ore:VR, Gold Leaf:VR, Gold Ore:VR, Phil. Stone:VR, G. Bird Plume:SR"},
    {"Yuhtunga Jungle", "Arrowwood Log:U, Bone Chip:U, Danceshroom:U, Woozyshroom:U, Cinnamon:R, Ebony Log:R, Elm Log:R, Puffball:R, Rattan Lumber:R, Rosewood Log:R, Sleepshroom:R, Yew Log:R, Deathball:VR, King Truffle:VR, Oak Log:VR, Petrified Log:VR, Reishi Mushroom:VR, Ancient Lumber:SR, Heavy Metal:SR, Lacquer Tree Log:SR, Mahogany Log:SR"},
    {"Yhoator Jungle", "Arrowwood Log:U, Bone Chip:U, Sleepshroom:U, Woozyshroom:U, Danceshroom:R, Dryad Root:R, Ebony Log:R, Elm Log:R, Kazham Pineapl.:R, Lauan Log:R, Mahogany Log:R, Oak Log:R, Reishi Mushroom:R, Rosewood Log:R, Yew Log:R, Coral Fungus:VR, Petrified Log:VR, Puffball:VR, Ancient Lumber:SR, Deathball:SR, Lacquer Tree Log:SR"},
    {"Lufaise Meadows", "Acorn:U, Apple Mint:R, Cibol:R, Dark Crystal:R, Earth Crystal:R, Fire Crystal:R, Holy Basil:R, Ice Crystal:R, Light Crystal:R, Lightning Crystal:R, Lufaise Fly:R, Misx. Parsley:R, Moko Grass:R, Popoto:R, Red Moko Grass:R, Water Crystal:R, Wind Crystal:R, Beehive Chip:VR, Blue Peas:VR, Giant Stinger:VR, Light Chest:VR, Puffball:VR, Ram Horn:VR, Wild Onion:VR, Gold Beastcoin:SR, Griffon Hide:SR, Heavy Metal:SR, Vegetable Seeds:SR"},
    {"Misareaux Coast", "Acorn:U, Apple Mint:U, Arrowwood Log:U, Blue Peas:R, Cibol:R, Flytrap Leaf:R, Herb Seeds:R, Holy Basil:R, Misx. Parsley:R, Moko Grass:R, Oak Log:R, Popoto:R, Wild Onion:R, Yew Log:R, Beehive Chip:VR, Ebony Log:VR, Elm Log:VR, Gold Beastcoin:VR, Lacquer Tree Log:VR, Lightning Crystal:VR, Mahogany Log:VR, Puffball:VR, Red Moko Grass:VR, Rosewood Log:VR, Saffron Blossom:VR, Shadow Geode:VR, Wind Crystal:VR, Ancient Lumber:SR, Breeze Geode:SR, Heavy Metal:SR, Oxblood:SR"},
    {"Bhaflau Thickets", "Flint Stone:VC, Arrowwood Log:C, Colibri Feather:R, Dried Marjoram:R, Moko Grass:R, Oak Log:R, Pebble:R, Petrified Log:R, Pine Nuts:R, Yew Log:R, Aluminum Ore:VR, Black C. Feather:VR, Blue Rock:VR, Ebony Log:VR, Elm Log:VR, Gold Ore:VR, Mahogany Log:VR, Orichalcum Ore:VR, Platinum Ore:VR, Rosewood Log:VR, Wind Crystal:VR, Alexandrite:SR, Ancient Lumber:SR, Darksteel Ore:SR, Lacquer Tree Log:SR, Lesser Chigoe:SR, Peph. Hive Chip:SR, Spider Web:SR"},
    {"Wajaom Woodlands", "Flint Stone:VC, Arrowwood Log:C, Moko Grass:U, Black C. Feather:R, Blue Rock:R, Ebony Log:R, Elm Log:R, Oak Log:R, Pebble:R, Pine Nuts:R, Yew Log:R, Adaman Ore:VR, Aluminum Ore:VR, Darksteel Ore:VR, Gold Ore:VR, Mahogany Log:VR, Orichalcum Ore:VR, Peph. Hive Chip:VR, Spider Web:VR, Wind Crystal:VR, Alexandrite:SR, Ancient Lumber:SR, Kaolin:SR, Lacquer Tree Log:SR, Platinum Ore:SR, Rosewood Log:SR"},
    {"Caedarva Mire", "Flint Stone:VC, Arrowwood Log:C, Bone Chip:U, Dogwood Log:R, Ebony Log:R, Imp Wing:R, Mistletoe:R, Rosewood Log:R, Treant Bulb:R, Water Crystal:R, Water Lily:R, Yew Log:R, Aluminum Ore:VR, Ancient Lumber:VR, Bloodwood Log:VR, Darksteel Ore:VR, Khroma Ore:VR, Lesser Chigoe:VR, Lightning Crystal:VR, Petrified Log:VR, Alexandrite:SR, Heavy Metal:SR, Kaolin:SR, Lancewood Log:SR, Platinum Ore:SR, Tama-Hagane:SR, Wootz Ore:SR"},
    {"East Ronfaure (S)", "Gysahl Greens:C, Arrowwood Log:U, Chamomile:U, Acorn:R, Black C. Feather:R, Chestnut:R, Elm Log:R, Ginger:R, Lacquer Tree Log:R, Ladybug Wing:R, Napa:R, Oak Log:R, Red Moko Grass:R, Feyweald Log:VR, Fruit Seeds:VR, Grove Cuttings:VR, Mtl. Beastcoin:VR, Silver Leaf:VR, Teak Log:VR, Ancient Lumber:SR, Bottled Pixie:SR, Coin of Birth:SR, Exalted Log:SR, Heavy Metal:SR, Jacaranda Log:SR, O. Bronzepiece:SR"},
    {"Jugner Forest (S)", "Arrowwood Log:VC, Oak Log:U, Pebble:U, Sleepshroom:U, Woozyshroom:U, Danceshroom:R, Gnole Claw:R, Grove Cuttings:R, Holly Log:R, Bottled Pixie:VR, Deathball:VR, Elm Log:VR, Exalted Log:VR, Feyweald Log:VR, King Truffle:VR, Lacquer Tree Log:VR, Reishi Mushroom:VR, Scream Fungus:VR, Teak Log:VR, Ancient Lumber:SR, Coin of Adv.:SR, Heavy Metal:SR, Jacaranda Log:SR, O. Bronzepiece:SR, Puffball:SR, Tree Cuttings:SR"},
    {"Vunkerl Inlet (S)", "Yellow Ginseng:VC, Black C. Feather:U, Phoenix Feather:U, Acorn:R, Fish Scales:R, Mahogany Log:R, Red Moko Grass:R, Shungiku:R, Spider Web:R, Treant Bulb:R, Wildgrass Seeds:R, Chestnut Log:VR, G. Bird Plume:VR, Gold Leaf:VR, Lightning Crystal:VR, Mtl. Beastcoin:VR, Tree Cuttings:VR, Wind Crystal:VR, Bottled Pixie:SR, Cactus Stems:SR, Heavy Metal:SR, Herb Seeds:SR, Maliya. Coral:SR, O. Bronzepiece:SR"},
    {"Batallia Downs (S)", "Black C. Feather:U, Iron Ore:U, Kopparnickel Ore:U, Phoenix Feather:U, Silver Ore:U, Copper Ore:R, Goblin Mess Tin:R, Lycopodium Flower:R, Mahogany Log:R, Mythril Ore:R, Pebble:R, Purple Rock:R, Red Moko Grass:R, Smilodon Hide:R, Spider Web:R, Bottled Pixie:VR, Darksteel Ore:VR, G. Bird Plume:VR, Gold Beastcoin:VR, Beetle Blood:SR, Coin of Glory:SR, Grain Seeds:SR, Heavy Metal:SR, O. Bronzepiece:SR"},
    {"North Gustaberg (S)", "Black C. Feather:U, Iron Ore:U, Phoenix Feather:U, Silver Ore:U, Aluminum Ore:R, Flint Stone:R, Kopparnickel Ore:R, Moblin Sheepskin:R, Obsidian:R, Pebble:R, Red Moko Grass:R, Spider Web:R, Zinc Ore:R, Adaman Ore:VR, Bottled Pixie:VR, Cactus Stems:VR, Darksteel Ore:VR, Fool's Gold Ore:VR, G. Bird Plume:VR, Hepatizon Ore:VR, P. Brass Ore:VR, Squamous Hide:VR, Swamp Ore:VR, 1 Byne Bill:SR, Coin of Decay:SR, Heavy Metal:SR"},
    {"Grauberg (S)", "Arrowwood Log:U, Gardenia Seed:U, Grauberg Lettuce:U, Little Worm:U, Pebble:U, Elm Log:R, Iron Ore:R, Jacaranda Log:R, Lacquer Tree Log:R, Oak Log:R, Rosewood Log:R, Wildgrass Seeds:R, Yew Log:R, Feyweald Log:VR, Tree Cuttings:VR, Vegetable Seeds:VR, Wyvern Wing:VR, 1 Byne Bill:SR, Ancient Lumber:SR, Beryllium Ore:SR, Cactus Stems:SR, Teak Log:SR, Yellow Ginseng:SR, Heavy Metal:SR"},
    {"Pashhow Marshlands (S)", "Yellow Ginseng:C, Black Rock:R, Earth Crystal:R, Fire Crystal:R, Ice Crystal:R, Insect Wing:R, Light Crystal:R, Lightning Crystal:R, Little Worm:R, Peiste Skin:R, Silver Ore:R, Water Crystal:R, Wildgrass Seeds:R, Wind Crystal:R, Agaricus:VR, Herb Seeds:VR, H.Q. Crab Shell:VR, Malboro Fiber:VR, Tree Cuttings:VR, Willow Log:VR, 1 Byne Bill:SR, Cactus Stems:SR, Coin of Birth:SR, Heavy Metal:SR"},
    {"Rolanberry Fields (S)", "Beastcoin:U, Mtl. Beastcoin:U, Silver Beastcoin:U, Sleepshroom:U, Woozyshroom:U, Acorn:R, Coral Fungus:R, Danceshroom:R, Lycopodium Flower:R, Pebble:R, Rolanberry:R, Sage:R, Bottled Pixie:VR, Deathball:VR, Gold Beastcoin:VR, Light Chest:VR, Reishi Mushroom:VR, Sif's Macrame:VR, Water Crystal:VR, Wyrdstrand:VR, 1 Byne Bill:SR, Coin of Adv.:SR, Heavy Metal:SR, Plt. Beastcoin:SR, Puffball:SR, Wildgrass Seeds:SR"},
    {"West Sarutabaruta (S)", "Gysahl Greens:C, Burdock:R, Chamomile:R, Dark Crystal:R, Earth Crystal:R, Fire Crystal:R, Ginger:R, Grain Seeds:R, Green Rock:R, Ice Crystal:R, Light Crystal:R, Lightning Crystal:R, Lycopodium Flower:R, Napa:R, Pebble:R, Red Moko Grass:R, Water Crystal:R, Wind Crystal:R, G. Bird Plume:VR, Maliya. Coral:VR, Rosewood Log:VR, Saruta Cotton:VR, Coin of Glory:SR, Heavy Metal:SR, T. Whiteshell:SR"},
    {"Fort Karugo-Narugo (S)", "Flint Stone:VC, Darksteel Ore:R, Dragon Fruit:R, Iron Ore:R, Karugo Clay:R, Kopparnickel Ore:R, Obsidian:R, Pebble:R, Rafflesia Vine:R, Red Rock:R, Silver Ore:R, Wildgrass Seeds:R, Adaman Ore:VR, Aluminum Ore:VR, Bottled Pixie:VR, Fool's Gold Ore:VR, Goblin Mess Tin:VR, Gold Ore:VR, Phil. Stone:SR, Swamp Ore:SR, Heavy Metal:SR, Kaolin:SR, P. Brass Ore:SR, Platinum Ore:SR, T. Whiteshell:SR"},
    {"Meriphataud Mountains (S)", "Bone Chip:R, Fish Scales:R, Flint Stone:R, Giant Femur:R, Grain Seeds:R, H.Q. Pugil Scale:R, Iron Ore:R, Kopparnickel Ore:R, Lynx Hide:R, Obsidian:R, Pebble:R, Red Gravel:R, Seashell:R, Silver Ore:R, Sunflower Seeds:R, Titanictus Shell:R, Treant Bulb:R, Yellow Rock:R, Adaman Ore:VR, Darksteel Ore:VR, Demon Horn:VR, Demon Skull:VR, Dragon Scales:VR, Fool's Gold Ore:VR, P. Brass Ore:VR, Swamp Ore:VR, Turtle Shell:VR, Coin of Decay:SR, Heavy Metal:SR, Hepatizon Ore:SR, T. Whiteshell:SR, Wyvern Scales:SR"},
    {"Sauromugue Champaign (S)", "Silver Beastcoin:C, Arrowwood Log:U, Beastcoin:U, Antique Bullet:R, Elm Log:R, Flint Stone:R, Gnat Wing:R, Lacquer Tree Log:R, Mtl. Beastcoin:R, Oak Log:R, Pebble:R, Translucent Rock:R, Vegetable Seeds:R, Feyweald Log:VR, G. Bird Plume:VR, Gold Beastcoin:VR, Jacaranda Log:VR, Light Chest:VR, Teak Log:VR, Ancient Lumber:SR, Beryllium Ore:SR, Coin of Ruin:SR, Heavy Metal:SR, Plt. Beastcoin:SR, T. Whiteshell:SR"},
    {"Beaucedine Glacier (S)", "Ice Cluster:VC(double weather), Blk. Tiger Fang:R, Darksteel Ore:R, Flint Stone:R, Ice Crystal:R, Iron Ore:R, Kopparnickel Ore:R, Lugworm:R, Obsidian:R, Pebble:R, Petrified Log:R, Silver Ore:R, Dark Crystal:VR, Dogbolt:VR, Earth Crystal:VR, Fire Crystal:VR, Fool's Gold Ore:VR, Gargouille Horn:VR, Light Crystal:VR, Lightning Crystal:VR, Platinum Leaf:VR, Swamp Ore:VR, Wind Crystal:VR, 1 Byne Bill:SR, Adaman Ore:SR, Amphiptere Hide:SR, O. Bronzepiece:SR, P. Brass Ore:SR, T. Whiteshell:SR"},
    {"Xarcabard (S)", "Arrowwood Log:U, Beastcoin:U, Silver Beastcoin:U, Bone Chip:R, Frost Turnip:R, Gigas Helm:R, Mtl. Beastcoin:R, Mythril Leaf:R, Oak Log:R, Old Arrow:R, Pebble:R, Ruszor Fang:R, Yew Log:R, Ancient Lumber:VR, Elm Log:VR, Feyweald Log:VR, Gold Beastcoin:VR, Jacaranda Log:VR, Lacquer Tree Log:VR, Painite:VR, Plt. Beastcoin:VR, Teak Log:VR, Tourmaline:VR, 1 Byne Bill:SR, Dragon Heart:SR, O. Bronzepiece:SR, Peridot:SR, Shagreen:SR, Sif's Macrame:SR, T. Whiteshell:SR"},
    {"Ceizak Battlegrounds", "Arrowwood Log:U, Akaso:R, Ash Log:R, Blue Peas:R, Chapuli Horn:R, Chestnut Log:R, Felicifruit:R, Feyweald Log:R, Guatambu Log:R, Insect Wing:R, Isleracea:R, Leafkin Frond:R, Paprika:R, Rosewood Log:R, Sleepshroom:R, Walnut:R, Walnut Log:R, White Sand:R, Zucchini:R, Beech Log:VR, Gold Leaf:VR, Reishi Mushroom:VR, Saffron Blossom:VR, Ulbuconut:VR, Urunday Log:VR, C. Ygg. Shard I:SR, C. Ygg. Shard II:SR, C. Ygg. Shard III:SR, C. Ygg. Shard IV:SR, C. Ygg. Shard V:SR, Faithful's Legs I:SR, Faithful's Legs II:SR, Faithful's Legs III:SR, Faithful's Legs IV:SR, Faithful's Legs V:SR, Faithful's Torso I:SR, Faithful's Torso II:SR, Faithfl. Torso III:SR, Faithfl. Torso IV:SR, Faithful's Torso V:SR, Gr. Velkk Coffer:SR, H-P Bayld:SR, Rala Visage I:SR, Rala Visage II:SR, Rala Visage III:SR, Rala Visage IV:SR, Rala Visage V:SR"},
    {"Yahse Hunting Grounds", "Acorn:U, Ash Log:R, Akaso:R, Arrowwood Log:R, Blue Peas:R, Chapuli Wing:R, Chestnut Log:R, Felicifruit:R, Rosewood Log:R, Silver Leaf:R, Sleepshroom:R, Walnut:R, Walnut Log:R, Yellow Ginseng:R, Zucchini:R, Beech Log:VR, Guatambu Log:VR, Isleracea:VR, Leafkin Frond:VR, Paprika:VR, Saffron Blossom:VR, Ulbuconut:VR, Urunday Log:VR, Eudaemon Ring:VR, Eudaemon Cape:SR, Eudaemon Sash:SR, Eudaemon Shld.:SR, Eudaemon Blade:SR, Faithful's Torso I:SR, Faithful's Torso II:SR, Faithfl. Torso III:SR, Faithfl. Torso IV:SR, Faithful's Torso V:SR, Gr. Velkk Coffer:SR, H-P Bayld:SR, Rala Visage I:SR, Rala Visage II:SR, Rala Visage III:SR, Rala Visage IV:SR, Rala Visage V:SR"},
    {"Foret de Hennetiel", "Flint Stone:VC, Pebble:U, Sleepshroom:U, Woozyshroom:U, Danceshroom:R, Deathball:R, Gnatbane:R, Loc. Elutriator:R, Tin Ore:R, Adaman Ore:VR, Aluminum Ore:VR, Darksteel Ore:VR, King Truffle:VR, Orobon Lure:VR, Orpiment:VR, Platinum Ore:VR, Puffball:VR, Reishi Mushroom:VR, Eudaemon Ring:VR, Eudaemon Cape:SR, Eudaemon Sash:SR, Eudaemon Shld.:SR, Eudaemon Blade:SR, Faithful's Torso I:SR, Faithful's Torso II:SR, Faithfl. Torso III:SR, Faithfl. Torso IV:SR, Faithful's Torso V:SR, Gold Ore:SR, Gr. Velkk Coffer:SR, H-P Bayld:SR, Z. Ygg. Shard I:SR, Z. Ygg. Shard II:SR, Z. Ygg. Shard III:SR, Z. Ygg. Shard IV:SR, Z. Ygg. Shard V:SR"},
    {"Morimar Basalt Fields", "Yellow Ginseng:VC, Lizard Molt:U, Copper Ore:R, Darksteel Ore:R, Igneous Rock:R, Iron Ore:R, Matamata Shell:R, Midrium Ore:R, Pebble:R, Silver Ore:R, Sulfur:R, Wildgrass Seeds:R, Cactus Stems:VR, Gold Ore:VR, Marble Nugget:VR, Orpiment:VR, Tree Cuttings:VR, Vanadium Ore:VR, Eudaemon Ring:VR, A. Ygg. Shard I:SR, A. Ygg. Shard II:SR, A. Ygg. Shard III:SR, A. Ygg. Shard IV:SR, A. Ygg. Shard V:SR, Eudaemon Cape:SR, Eudaemon Sash:SR, Eudaemon Shld.:SR, Eudaemon Blade:SR, Faithful's Torso I:SR, Faithful's Torso II:SR, Faithfl. Torso III:SR, Faithfl. Torso IV:SR, Faithful's Torso V:SR, Gr. Velkk Coffer:SR, H-P Bayld:SR, Rhodium Ore:SR, Snowsteel Ore:SR, Yorcia Visage I:SR, Yorcia Visage II:SR, Yorcia Visage III:SR, Yorcia Visage IV:SR, Yorcia Visage V:SR"},
    {"Yorcia Weald", "Yellow Ginseng:C, Acorn:U, Arrowwood Log:R, Ash Log:R, Chestnut Log:R, Divine Log:R, Guatambu Log:R, Leafkin Frond:R, Lesser Chigoe:R, Little Worm:R, Rosewood Log:R, Snap. Tendril:R, Verboshroom:R, Walnut Log:R, Wildgrass Seeds:R, Beech Log:VR, Cactus Stems:VR, Tree Cuttings:VR, Urunday Log:VR, Faithful's Legs I:SR, Faithful's Legs II:SR, Faithful's Legs III:SR, Faithful's Legs IV:SR, Faithful's Legs V:SR, Faithful's Torso I:SR, Faithful's Torso II:SR, Faithfl. Torso III:SR, Faithfl. Torso IV:SR, Faithful's Torso V:SR, Gr. Velkk Coffer:SR, H-P Bayld:SR, R. Ygg. Shard I:SR, R. Ygg. Shard II:SR, R. Ygg. Shard III:SR, R. Ygg. Shard IV:SR, R. Ygg. Shard V:SR, Yorcia Visage I:SR, Yorcia Visage II:SR, Yorcia Visage III:SR, Yorcia Visage IV:SR, Yorcia Visage V:SR"},
    {"Marjami Ravine", "Arrowwood Log:U, Akaso:R, Ash Log:R, Chestnut Log:R, Copper Ore:R, Darksteel Ore:R, Fish Scales:R, Iron Ore:R, Little Worm:R, Mythril Leaf:R, Rosewood Log:R, Silver Ore:R, Tulfaire Feather:R, Walnut Log:R, Beech Log:VR, Gold Ore:VR, Guatambu Log:VR, Leafkin Frond:VR, Orpiment:VR, Rhodium Ore:VR, Snowsteel Ore:VR, Urunday Log:VR, Vanadium Ore:VR, Velkk Coffer:VR, Faithful's Legs I:SR, Faithful's Legs II:SR, Faithful's Legs III:SR, Faithful's Legs IV:SR, Faithful's Legs V:SR, Faithful's Torso I:SR, Faithful's Torso II:SR, Faithfl. Torso III:SR, Faithfl. Torso IV:SR, Faithful's Torso V:SR, Gr. Velkk Coffer:SR, H-P Bayld:SR, Ra'Ka. Visage I:SR, Ra'Ka. Visage II:SR, Ra'Ka. Visage III:SR, Ra'Ka. Visage IV:SR, Ra'Ka. Visage V:SR"},
    {"Kamihr Drifts", "Arrowwood Log:U, Blk. Tiger Fang:R, Bone Chip:R, Copper Ore:R, Darksteel Ore:R, Elm Log:R, Iron Ore:R, Leafkin Frond:R, Pebble:R, Raaz Tusk:R, Sheep Tooth:R, Silver Ore:R, Yew Log:R, Ancient Lumber:VR, Ebony Log:VR, Gold Ore:VR, Lacquer Tree Log:VR, Mahogany Log:VR, Midrium Ore:VR, Oak Log:VR, Orpiment:VR, Rhodium Ore:VR, Rosewood Log:VR, Snowsteel Ore:VR, Vanadium Ore:VR, As. Ygg. Sh. I:SR, As. Ygg. Sh. II:SR, As. Ygg. Sh. III:SR, As. Ygg. Sh. IV:SR, As. Ygg. Sh. V:SR, Faithful's Torso I:SR, Faithful's Torso II:SR, Faithfl. Torso III:SR, Faithfl. Torso IV:SR, Faithful's Torso V:SR, Gr. Velkk Coffer:SR, H-P Bayld:SR, Ra'Ka. Visage I:SR, Ra'Ka. Visage II:SR, Ra'Ka. Visage III:SR, Ra'Ka. Visage IV:SR, Ra'Ka. Visage V:SR"},
}

return function(ctx)
    local C = ctx.C
    local W = {}

    -- rarity order and how each is shown
    local TIERS = {
        {'VC', 'Very common', '\\cs(235,238,245)'},
        {'C',  'Common',      '\\cs(235,238,245)'},
        {'U',  'Uncommon',    '\\cs(140,220,140)'},
        {'R',  'Rare',        '\\cs(120,190,255)'},
        {'VR', 'Very rare',   '\\cs(200,150,255)'},
        {'SR', 'Super rare',  '\\cs(255,200,90)'},
        {'?',  'Unknown',     '\\cs(160,165,180)'},
    }

    -- zone names as Windower spells them ("East Ronfaure [S]") or the wiki
    -- does ("East Ronfaure (S)") -> one comparable key
    local function norm(s)
        return (s or ''):lower():gsub('%[s%]', '(s)'):gsub("[^%w()]", '')
    end

    -- parse the data once: list of {name, entries}, plus lookup by key
    local zones, by_key = {}, {}
    for _, z in ipairs(REWARDS) do
        local entries = {}
        for ent in z[2]:gmatch('[^,]+') do
            ent = ent:gsub('^%s+', ''):gsub('%s+$', '')
            local item, code, cond = ent:match('^(.-):([%a%?]+)%((.-)%)$')
            if not item then item, code = ent:match('^(.-):([%a%?]+)$') end
            if item then entries[#entries + 1] = {item = item, code = code, cond = cond} end
        end
        local key = norm(z[1])
        -- Behemoth's Dominion has extra Burrow / Bore tables: attach them to the zone
        local base, part = z[1]:match('^(.-) %((%a+)%)$')
        if base and (part == 'Burrow' or part == 'Bore') then
            local parent = by_key[norm(base)]
            if parent then parent.parts[#parent.parts + 1] = {name = part, entries = entries} end
        else
            local zone = {name = z[1], entries = entries, parts = {}}
            zones[#zones + 1] = zone
            by_key[key] = zone
        end
    end
    W.zones = zones

    -- find a zone by (part of) its name
    function W.find(name)
        local k = norm(name)
        if k == '' then return nil end
        if by_key[k] then return by_key[k] end
        for _, z in ipairs(zones) do
            if norm(z.name):find(k, 1, true) then return z end
        end
    end

    -- which zone the window shows: nil = follow the zone you're in
    W.view = nil

    -- window pieces
    local GAP, MIN_W = 6, 240
    local win = {
        bg     = ctx.solid(MIN_W, 100, 215, 18, 20, 28),
        header = ctx.solid(MIN_W, 26, 255, 38, 52, 84),
        b_prev = ctx.solid(22, 18, 255, 60, 75, 110),
        b_next = ctx.solid(22, 18, 255, 60, 75, 110),
        title  = ctx.mk_text(11),
        l_prev = ctx.mk_text(10),
        l_next = ctx.mk_text(10),
    }
    win.l_prev:text('<')
    win.l_next:text('>')
    local pool, ry, used = {}, {}, 0
    local x0, y0, width, height, shown = 0, 0, MIN_W, 100, false
    W.gap = GAP

    local function place()
        win.bg:pos(x0, y0)
        win.header:pos(x0, y0)
        win.title:pos(x0 + 10, y0 + 5)
        win.b_prev:pos(x0 + width - 56, y0 + 4)
        win.b_next:pos(x0 + width - 28, y0 + 4)
        win.l_prev:pos(x0 + width - 56 + 7, y0 + 5)
        win.l_next:pos(x0 + width - 28 + 7, y0 + 5)
        for i = 1, used do pool[i]:pos(x0 + 10, y0 + (ry[i] or 0)) end
    end

    function W.move(x, y) x0, y0 = x, y; if shown then place() end end

    function W.hide()
        if not shown then return end
        shown = false
        for _, e in pairs(win) do e:hide() end
        for _, t in ipairs(pool) do t:hide() end
    end

    function W.visible() return shown end

    -- where a click landed: 'prev', 'next', 'window' or nil
    function W.hit(mx, my)
        if not shown then return nil end
        local function inside(x, y, w, h) return mx >= x and mx <= x + w and my >= y and my <= y + h end
        if inside(x0 + width - 56, y0 + 4, 22, 18) then return 'prev' end
        if inside(x0 + width - 28, y0 + 4, 22, 18) then return 'next' end
        if inside(x0, y0, width, height) then return 'window' end
    end

    -- step through the zones in the wiki's order
    function W.step(dir, here_name)
        local cur = W.view or W.find(here_name)
        local idx = 1
        for i, z in ipairs(zones) do if z == cur then idx = i end end
        if not cur then idx = dir > 0 and 0 or 1 end
        idx = (idx - 1 + dir) % #zones + 1
        W.view = zones[idx]
    end

    -- draw the window for the zone being viewed. here_name = the zone you're in.
    function W.draw(x, y, sp, here_name)
        x0, y0 = x, y
        local zone = W.view or W.find(here_name)
        local following = (W.view == nil)
        local out, yy = {}, 34
        local function add(text) out[#out + 1] = {text, yy}; yy = yy + sp end

        win.title:text(C.acc .. 'REWARDS' .. C.r)
        if not zone then
            add(C.val .. (here_name or 'Unknown zone') .. C.r)
            add(C.dim .. 'No chocobo digging here. Use < > to browse,' .. C.r)
            add(C.dim .. 'or //bup rewards <zone>.' .. C.r)
        else
            local found = ctx.found(zone.name) or {}
            local here = norm(zone.name) == norm(here_name)
            add(C.val .. zone.name .. C.r .. C.dim .. (here and '  (here)' or (following and '' or '  (browsing)')) .. C.r)

            local sections = {{name = nil, entries = zone.entries}}
            for _, p in ipairs(zone.parts) do sections[#sections + 1] = p end
            local total, have = 0, 0
            -- column width from the longest name in this zone
            local colw = 10
            for _, sec in ipairs(sections) do
                for _, e in ipairs(sec.entries) do
                    local n = #e.item + (e.cond and (#e.cond + 3) or 0)
                    if n > colw then colw = n end
                end
            end
            colw = math.min(colw, 30)
            for _, sec in ipairs(sections) do
                if sec.name then
                    yy = yy + 4
                    add(C.acc .. sec.name:upper() .. C.r .. C.dim .. (sec.name == 'Burrow' and ' (burrow spots)' or ' (bore spots)') .. C.r)
                end
                for _, t in ipairs(TIERS) do
                    local list = {}
                    for _, e in ipairs(sec.entries) do if e.code == t[1] then list[#list + 1] = e end end
                    if #list > 0 then
                        add(t[3] .. t[2] .. C.r .. C.dim .. (' (%d)'):format(#list) .. C.r)
                        -- two items per line; '*' = you've dug it here
                        for i = 1, #list, 2 do
                            local cells = {}
                            for j = i, math.min(i + 1, #list) do
                                local e = list[j]
                                total = total + 1
                                local got = (found[e.item] or 0) > 0
                                if got then have = have + 1 end
                                local label = e.item .. (e.cond and (' (' .. e.cond .. ')') or '')
                                if #label > colw then label = label:sub(1, colw - 1) .. '.' end
                                cells[#cells + 1] = (got and (C.good .. '*' .. C.r) or ' ') ..
                                    t[3] .. label .. C.r .. string.rep(' ', colw - #label)
                            end
                            add('  ' .. table.concat(cells, '  '))
                        end
                    end
                end
            end
            yy = yy + 4
            add(C.dim .. ('* = you\'ve dug it here: %d of %d'):format(have, total) .. C.r)
        end
        add(C.dim .. 'Source: BG-Wiki   < > other zones' .. C.r)

        -- draw the lines
        for i, l in ipairs(out) do
            local t = pool[i]
            if not t then t = ctx.mk_text(10); pool[i] = t end
            t:text(l[1])
            ry[i] = l[2]
            t:show()
        end
        for i = #out + 1, #pool do pool[i]:hide() end
        used = #out

        -- size to the widest line (Consolas 10 ~7.5 px per character)
        local widest = 0
        for _, l in ipairs(out) do
            local plain = l[1]:gsub('\\cs%(%d+,%d+,%d+%)', ''):gsub('\\cr', '')
            widest = math.max(widest, #plain * 7.5)
        end
        width = math.max(MIN_W, math.ceil(widest) + 24)
        height = yy + 6
        win.header:size(width, 26)
        win.bg:size(width, height)
        if following then win.b_prev:color(60, 75, 110) else win.b_prev:color(80, 120, 170) end
        if not shown then
            shown = true
            for _, e in pairs(win) do e:show() end
        end
        place()
    end

    return W
end
