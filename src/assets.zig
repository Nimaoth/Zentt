const std = @import("std");

const AssetDB = @import("rendering/assetdb.zig");

pub fn loadAssets(assetdb: *AssetDB) !void {
    try assetdb.loadTexturePack("assets/img/characters.json", .{ .filter = .nearest });
    try assetdb.loadTexturePack("assets/img/enemies.json", .{ .filter = .nearest });
    try assetdb.loadTexturePack("assets/img/items.json", .{ .filter = .nearest });
    try assetdb.loadTexturePack("assets/img/vfx.json", .{ .filter = .nearest });
    try assetdb.loadTexturePack("assets/img/UI.json", .{ .filter = .nearest });
    try assetdb.loadTexturePack("assets/tilesets/ForestTexturePacked.json", .{ .filter = .nearest });

    // Items
    // ArmorIron.png
    // Axe.png
    // Bone.png
    // Book2.png
    // BoxOpen.png
    // BoxOpen2.png
    // BoxOpen3.png
    // Brazier1.png
    // Brazier2.png
    // Brazier21.png
    // Brazier22.png
    // Brazier23.png
    // Brazier3.png
    // Candelabra.png
    // Candelabrone1.png
    // Candelabrone2.png
    // Candelabrone3.png
    // Cart1.png
    // Cart2.png
    // Cart3.png
    // CartWheel.png
    // Cherry.png
    // Clover.png
    // Clover2.png
    // Coff.png
    // Coffin.png
    // CoffinLid.png
    // Coin.png
    // CoinGold.png
    // CoinSilver.png
    // Cross.png
    // Crown.png
    // Curse.png
    // Diamond2.png
    // Dice.png
    // EmblemEye.png
    // Garlic.png
    // Gauntlet.png
    // Gem1.png
    // Gem2.png
    // Gem3.png
    // Gem4.png
    // Gem5.png
    // Gem6.png
    // Gem7.png
    // Gem8.png
    // GemBlue.png
    // GemGreen.png
    // GemRed.png
    // HeartBlack.png
    // HeartMini.png
    // HeartRuby.png
    // HeavenSword.png
    // Hellfire.png
    // HolyBook.png
    // HolyWater.png
    // Knife.png
    // Knife2.png
    // Lampost1.png
    // Lampost2.png
    // Lampost3.png
    // Lampost4.png
    // Lancet.png
    // Laurel.png
    // Leaf.png
    // LighningRing.png
    // Map.png
    // Mask.png
    // MoneyBagColor.png
    // MoneyBagGreen.png
    // MoneyBagRed.png
    // Nft1.png
    // Nft2.png
    // Nft3.png
    // Nft4.png
    // OrbGlow.png
    // OrbOrange.png
    // Page.png
    // Pentagram.png
    // Pizza.png
    // PocketWatch.png
    // PocketWatch1.png
    // PocketWatch2.png
    // PocketWatch3.png
    // QuestionMark.png
    // Ring.png
    // Roast.png
    // Rosary1.png
    // Rosary2.png
    // Rosary3.png
    // Scythe.png
    // ShadowSpot.png
    // Silf1.png
    // Silf2.png
    // Silf3.png
    // Skip.png
    // Song.png
    // Song2.png
    // SpearIce.png
    // Tarots.png
    // Thunderloop.png
    // Tiramisu.png
    // UnholyBook.png
    // Vacuum1.png
    // Vacuum2.png
    // Vacuum3.png
    // WandBall.png
    // WandFire.png
    // WandFire2.png
    // WandHoly.png
    // WandHoly2.png
    // Water2.png
    // Whip.png
    // Whip2.png
    // Wing.png
    // blackDot.png
    // blurBlack.png
    // coin-spin-gold_01.png
    // coin-spin-gold_02.png
    // coin-spin-gold_03.png
    // coin-spin-gold_04.png
    // coin-spin-gold_05.png
    // coin-spin-silver_01.png
    // coin-spin-silver_02.png
    // coin-spin-silver_03.png
    // coin-spin-silver_04.png
    // coin-spin-silver_05.png

    // UI
    // Coff.png
    // CoinGold.png
    // ExclamationMark.png
    // MoneyBagGreen.png
    // MoneyPile.png
    // QuestionMark.png
    // SkullToken.png
    // TreasureIdle_01.png
    // TreasureOpenFront_01.png
    // TreasureOpen_01.png
    // arrow_01.png
    // blackDot.png
    // button_c5_mouseover.png
    // button_c5_normal.png
    // button_c5_pressed.png
    // button_c8_normal.png
    // button_c9_desaturated.png
    // button_c9_mouseover.png
    // button_c9_normal.png
    // button_c9_normal_mini.png
    // button_c9_normal_mini_desaturated.png
    // button_c9_pressed.png
    // frame1_c2.png
    // frame1_c4.png
    // frame4_c3.png
    // frame5_c4.png
    // frame5_c4_ad.png
    // frame5_c4_in.png
    // frameB.png
    // frameB9.png
    // frameC.png
    // frameD.png
    // frameE.png
    // frameF.png
    // lock16.png
    // menu_checkbox_16_bg.png
    // menu_checkbox_16_checkmark.png
    // menu_checkbox_24_bg.png
    // menu_checkbox_24_checkmark.png
    // menu_slider_button_strip3.png
    // menu_square_flat_24.png
    // no16.png
    // p_arca.png
    // p_cavallo.png
    // p_clerici.png
    // p_croci.png
    // p_dommario.png
    // p_lama.png
    // p_mortaccio.png
    // p_poe.png
    // p_porta.png
    // passiveBG.png
    // pause.png
    // selectionSquareActive_01.png
    // selectionSquare_01.png
    // sliderrail_c4.png
    // stage_forest.png
    // stage_forest_icon.png
    // stage_green.png
    // stage_green_unlock.png
    // stage_library.png
    // stage_library_icon.png
    // stage_library_unlock.png
    // stage_plant.png
    // stage_plant_icon.png
    // stage_plant_unlock.png
    // stage_sinking.png
    // weaponBG.png
    // weaponLevelEmpty.png
    // weaponLevelFull.png
    // weaponSlots.psd
    // whiteDot.png
    // yes16.png

    // VFX
    // Blood1.png
    // Blood2.png
    // Blood3.png
    // Burst1.png
    // Burst2.png
    // Burst3.png
    // Burst4.png
    // Burst5.png
    // Burst6.png
    // Flame1.png
    // Flame2.png
    // Gradient.png
    // Gradient2.png
    // Gradient3.png
    // Gradient3_4px.png
    // Gradient3_6px.png
    // Gradient3_8px.png
    // Gradient4_4px.png
    // Gradient4_6px.png
    // Gradient4_8px.png
    // GradientRed_8px.png
    // Hit1.png
    // Hit2.png
    // HitBlack1.png
    // HitBlue1.png
    // HitBlue2.png
    // HitBoom1.png
    // HitBoom2.png
    // HitCloud1.png
    // HitCloud2.png
    // HitGreen1.png
    // HitGreen2.png
    // HitMoon1.png
    // HitMoon2.png
    // HitRed1.png
    // HitRed2.png
    // HitSmoke1.png
    // HitSmoke2.png
    // HitStar1.png
    // HitStar2.png
    // HitStarRed1.png
    // HitStarRed2.png
    // HitStarWhite1.png
    // HitStarWhite2.png
    // HitWhite1.png
    // HitWhite2.png
    // HolyBook.png
    // Lightning1.png
    // Lightning2.png
    // Lightning3.png
    // NoDraw.png
    // Page.png
    // Page2.png
    // PfxBlue.png
    // PfxColor1.png
    // PfxColor2.png
    // PfxDot.png
    // PfxGreen.png
    // PfxHoly1.png
    // PfxHoly2.png
    // PfxLightGreen.png
    // PfxLine.png
    // PfxPink.png
    // PfxPurple.png
    // PfxRed.png
    // PfxYellow.png
    // Pierce1.png
    // Pierce2.png
    // Pierce3.png
    // Pierce4.png
    // Pierce5.png
    // Prism1_8px.png
    // Prism2_8px.png
    // Prism3_8px.png
    // Prism4_8px.png
    // Prism5_8px.png
    // Prism6_8px.png
    // Prism7_8px.png
    // Prism8_8px.png
    // Prism9_8px.png
    // PrizeBG.png
    // ProjectileArrow.png
    // ProjectileAxe1.png
    // ProjectileAxe2.png
    // ProjectileBird1.png
    // ProjectileBird2.png
    // ProjectileBird3.png
    // ProjectileBird4.png
    // ProjectileBird5.png
    // ProjectileBird7.png
    // ProjectileBird8.png
    // ProjectileBlue1.png
    // ProjectileBlue2.png
    // ProjectileBone1.png
    // ProjectileBone2.png
    // ProjectileBone3.png
    // ProjectileBottle.png
    // ProjectileBullet.png
    // ProjectileBullet2.png
    // ProjectileCloud.png
    // ProjectileCross1.png
    // ProjectileCross2.png
    // ProjectileFireball.png
    // ProjectileFireball2.png
    // ProjectileFireballDouble.png
    // ProjectileFlameBlue.png
    // ProjectileFlameBlue2.png
    // ProjectileFlameGreen.png
    // ProjectileFlameHoly.png
    // ProjectileFlameHoly2.png
    // ProjectileFlameRed.png
    // ProjectileFluff1.png
    // ProjectileFluff2.png
    // ProjectileGreen1.png
    // ProjectileGreen2.png
    // ProjectileHellfireLarge.png
    // ProjectileHellfireSmall.png
    // ProjectileHoly1.png
    // ProjectileHoly2.png
    // ProjectileJavelin.png
    // ProjectileKnife1.png
    // ProjectileKnife2.png
    // ProjectileKnife3.png
    // ProjectileRock1.png
    // ProjectileRock2.png
    // ProjectileScythe.png
    // ProjectileSpike1.png
    // ProjectileSpike2.png
    // ProjectileSpin.png
    // ProjectileSword.png
    // ProjectileWave.png
    // Ribbon1.png
    // Rings1.png
    // Rings2.png
    // Rings3.png
    // Shockwave1.png
    // Shockwave2.png
    // Shockwave3.png
    // Smoke1.png
    // Smoke2.png
    // Smoke3.png
    // Sword.png
    // SwordBW.png
    // WhiteDot.png
    // _blur.png
    // _blur2.png
    // _blur3.png
    // a.png
    // b.png
    // blur.png
    // c.png
    // center.png
    // circle.png
    // d.png
    // e.png
    // f.png
    // feedback-1.png
    // feedback-2.png
    // feedback-3.png
    // feedback-4.png
    // feedback-5.png
    // fuzzA.png
    // g.png
    // h.png
    // i.png
    // inner1.png
    // inner2.png
    // inner3.png
    // j.png
    // k.png
    // l.png
    // leaf0000.png
    // leaf0001.png
    // leaf0002.png
    // leaf0003.png
    // leaf0004.png
    // leaf0005.png
    // leaf0006.png
    // leaf0007.png
    // leaf0008.png
    // leaf0009.png
    // leaf0010.png
    // leaf0011.png
    // leaf0012.png
    // leaf0013.png
    // leaf0014.png
    // leaf0015.png
    // leaf0016.png
    // leaf0017.png
    // leaf0018.png
    // leaf0019.png
    // m.png
    // n.png
    // o.png
    // outer0.png
    // outer1.png
    // outer2.png
    // outer3.png
    // p.png
    // q.png
    // r.png
    // rays.png
    // round.png
    // s.png
    // sPFX_ring_64.png
    // s_pfx_rainbow_32.png
    // s_pfx_rainbow_64.png
    // slash.png
    // spring.png
    // t.png
    // u.png
    // v.png
    // w.png
    // x.png
    // y.png
    // z.png

    // Monsters
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("ArmorSpear", 5, "ArmorSpear_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("ArmorSpeari", 5, "ArmorSpear_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Armor", 5, "Armor_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Armori", 5, "Armor_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat1", 2, "Bat1_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat1i", 2.5, "Bat1_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat2", 5, "Bat2_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat2i", 5, "Bat2_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat3", 5, "Bat3_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat3i", 5, "Bat3_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat4", 5, "Bat4_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat4i", 5, "Bat4_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat5", 5, "Bat5_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bat5i", 5, "Bat5_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Buer", 5, "Buer_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Bueri", 5, "Buer_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Dullahan1", 5, "Dullahan1_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Dullahan1i", 5, "Dullahan1_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Dullahan2", 5, "Dullahan2_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Dullahan2i", 5, "Dullahan2_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Ecto1", 5, "Ecto1_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Ecto1i", 5, "Ecto1_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Ecto2", 5, "Ecto2_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Ecto2i", 5, "Ecto2_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Fishman", 5, "Fishman_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Fishmani", 5, "Fishman_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Flower1", 5, "Flower1_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLFlower1", 5, "XLFlower1_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLFlower1i", 5, "XLFlower1_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLGolem1", 5, "XLGolem1_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLGolem1i", 5, "XLGolem1_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLGolem2", 5, "XLGolem2_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLGolem2i", 5, "XLGolem2_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLMantis", 5, "XLMantis_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLMantisi", 5, "XLMantis_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLMedusa", 5, "XLMedusa_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLMedusai", 5, "XLMedusa_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLMummy", 5, "XLMummy_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLMummyi", 5, "XLMummy_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLReaper", 5, "XLReaper_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLReaperi", 5, "XLReaper_i");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLTriton", 5, "XLTriton_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("XLTritoni", 5, "XLTriton_i");

    // Players
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Antonio", 2, "Antonio_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Arca", 2, "Arca_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Cavallo", 2, "Cavallo_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Dommario", 2, "Dommario_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Exdash", 2, "Exdash_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Gennaro", 2, "Gennaro_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Imelda", 2, "Imelda_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Krochi", 2, "Krochi_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Lama", 2, "Lama_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Mortaccio", 2, "Mortaccio_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Old3", 2, "Old3_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Pasqualina", 2, "Pasqualina_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Poppea", 2, "Poppea_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Porta", 2, "Porta_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("Suora", 2, "Suora_");
    _ = try assetdb.defineSpriteAnimationFromInTexturePack("0x00000000", 2, "_0x00000000_i");
}
